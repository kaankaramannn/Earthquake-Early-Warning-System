"""
Zaman Cizelgesi Demosu (Google-tarzi erken uyari + Kandilli teyidi) — GERCEK HTTP ile.

Gercek dunyayi taklit eder: bir Kandilli depremini "canlandirir".
  Faz 1 (t=0)   : crowd kullanicilari titreme raporu -> tespit -> "Yakininizda deprem!" (hizli)
  Faz 2 (t=~15s): resmi Kandilli verisi gelir -> tespit DOGRULANDI -> "Kandilli: M.., derinlik.., yer" (detayli)

Eskiden bu script in-process calisiyordu (DB'ye dogrudan yazip tespit/dogrulama
fonksiyonlarini elle cagiriyordu). Artik:
  - Faz 1: simulasyon.sahte_kullanicilari_hazirla + simulasyon.dalga_gonder_ve_tespit_bekle
    ile GERCEK HTTP istekleri (POST /tremor-reports/) atilir; olgunlasma penceresi +
    POST /detections/run ile TEK temiz kumede tespit garanti edilir (bkz. src/detect/router.py).
  - Faz 2: resmi deprem, admin login + POST /test/earthquakes/ ile HTTP uzerinden girilir —
    bu endpoint zaten tespitleri_dogrula + uzak_bilgilendirme_olustur'u sunucu tarafinda
    otomatik tetikler; script bu fonksiyonlari bir daha hic import/cagirmiyor.

Canli izlemek icin AYRI bir terminalde: python scripts/bildirim_takip.py --username Toprak --password Toprak123 --interval 2
(Sunucu da acik olmali: uvicorn src.main:app --host 0.0.0.0 --port 8000)

Calistirma: proje kokunden (deprem/) `python scripts/deprem_senaryosu.py ...`
"""

import sys
import time
import random
import argparse
from datetime import datetime
from pathlib import Path

import requests

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# scripts/ kendi klasorunu sys.path'e ekler, proje kokunu (deprem/) DEGIL —
# "src.*" import'larinin calismasi icin proje kokunu elle ekliyoruz.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import src.main  # noqa: F401 — SQLModel metadata'sini kaydettirir (temizlik icin)
from sqlmodel import Session, select
from src.database import engine
from src.users.models import User
from src.quakes.models import Earthquake
from src.notify.models import Notification
from src.tremor.models import TremorReport
from src.detect.models import DetectionEvent, PreliminaryAlert, FeltReport
from src.notify.router import haversine_km, BILGI_MIN_KM, BILGI_MAX_KM
import simulasyon
import kandilli_cek

engine.echo = False


def _her_seyi_temizle(session: Session) -> None:
    """Demo hijyeni: raporlar, tespitler, depremler ve sim kullanicilari temizlenir (in-process —
    bu, plandaki --temizle istisnasiyla ayni gerekceyle: test/demo orkestrasyonu, gercek
    endpoint'in tespit etmesi gereksinimiyle ilgisi yok). GERCEK kullanicilarin bildirimleri
    KORUNUR (gecmis, uygulama listesinde birikir; tam sifirlama icin: python scripts/simulasyon.py --temizle).
    Sim kullanicilarin bildirimleri sahipleriyle birlikte silinir (yetim kayit kalmasin)."""
    sim_kullanicilar = session.exec(select(User).where(User.username.like("sim_%"))).all()
    sim_idler = {u.id for u in sim_kullanicilar}
    for b in session.exec(select(Notification)).all():
        if b.user_id in sim_idler:
            session.delete(b)
    for model in (TremorReport, FeltReport, DetectionEvent, PreliminaryAlert, Earthquake):
        for row in session.exec(select(model)).all():
            session.delete(row)
    for u in sim_kullanicilar:
        session.delete(u)
    session.commit()


def _izlenen_bilgisi_al(username: str) -> tuple[str, dict]:
    """Izlenen GERCEK kullanicinin kendi hesabiyla giris yapip guncel /user/me/ bilgisini alir.
    Donen: (token, {'pref_latitude':..., 'pref_longitude':..., ...})."""
    sifre = simulasyon.BILINEN_SIFRELER.get(username, f"{username}123")
    token = simulasyon.giris_yap(username, sifre)
    cevap = requests.get(
        f"{simulasyon.BASE_URL}/user/me/",
        headers={"Authorization": f"Bearer {token}"},
        timeout=simulasyon.ISTEK_ZAMAN_ASIMI,
    )
    cevap.raise_for_status()
    return token, cevap.json()


def _resmi_deprem_gir(hedef: dict) -> dict:
    """Admin login + POST /test/earthquakes/ — resmi Kandilli verisini HTTP uzerinden girer.
    Bu endpoint zaten tespitleri_dogrula + uzak_bilgilendirme_olustur'u sunucu tarafinda
    otomatik tetikler (src/dev/router.py); script bu fonksiyonlari hic cagirmiyor."""
    admin_token = simulasyon.admin_token_al()
    cevap = requests.post(
        f"{simulasyon.BASE_URL}/test/earthquakes/",
        json={
            "magnitude": hedef["magnitude"],
            "latitude": hedef["latitude"],
            "longitude": hedef["longitude"],
            "depth_km": hedef["depth_km"],
            "occurred_at": datetime.utcnow().isoformat(),
            "location_name": hedef["location_name"],
        },
        headers={"Authorization": f"Bearer {admin_token}"},
        timeout=simulasyon.ISTEK_ZAMAN_ASIMI,
    )
    cevap.raise_for_status()
    return cevap.json()


def senaryo_calistir(bekleme: int = 15, izlenen: str = "Toprak",
                     kullanici_sayisi: int = 50, tasima: bool = False,
                     uzak: bool = False) -> None:
    with Session(engine) as session:
        _her_seyi_temizle(session)

    # 1) Hedef deprem secimi:
    #    VARSAYILAN: izlenen kullanicinin (kendi HTTP hesabindan okunan) KONUMUNA EN YAKIN
    #    Kandilli depremi secilir, kullanici TASINMAZ -> bildirimdeki mesafe GERCEK olur.
    #    --tasima verilirse eski demo modu: rastgele deprem + kullanici depremin yanina tasinir.
    izlenen_token, izlenen_bilgi = None, None
    try:
        izlenen_token, izlenen_bilgi = _izlenen_bilgisi_al(izlenen)
    except Exception as e:
        print(f"[UYARI] '{izlenen}' bilgisi alinamadi ({e}); rastgele/tasima moduna geciliyor.")

    k_lat = izlenen_bilgi.get("pref_latitude") if izlenen_bilgi else None
    k_lon = izlenen_bilgi.get("pref_longitude") if izlenen_bilgi else None

    if tasima or k_lat is None or k_lon is None:
        hedef = kandilli_cek.deprem_sec(secim="rastgele")
        secim_notu = "rastgele (tasima modu)"
    elif uzak:
        # UZAK MOD: izlenen kullanicinin etki alani DISINDA, bilgilendirme bandinda
        # (150-550 km) bir deprem sec -> kullanici alarm ALMAZ, BILGI bildirimi ALIR.
        adaylar = [
            d for d in kandilli_cek.depremleri_getir()
            if BILGI_MIN_KM <= haversine_km(k_lat, k_lon, d["latitude"], d["longitude"]) <= BILGI_MAX_KM
        ]
        if not adaylar:
            print("UYARI: 150-550 km bandinda deprem yok; en yakin bant disi secilecek.")
            adaylar = sorted(
                kandilli_cek.depremleri_getir(),
                key=lambda d: abs(haversine_km(k_lat, k_lon, d["latitude"], d["longitude"]) - 300),
            )[:1]
        hedef = random.choice(adaylar)
        mesafe = haversine_km(k_lat, k_lon, hedef["latitude"], hedef["longitude"])
        secim_notu = f"UZAK mod: '{izlenen}' kullanicisina {mesafe:.0f} km (bantta {len(adaylar)} aday icinden rastgele)"
    else:
        hedef = min(
            kandilli_cek.depremleri_getir(),
            key=lambda d: haversine_km(k_lat, k_lon, d["latitude"], d["longitude"]),
        )
        mesafe = haversine_km(k_lat, k_lon, hedef["latitude"], hedef["longitude"])
        secim_notu = f"'{izlenen}' kullanicisina en yakin ({mesafe:.0f} km)"

    print(f"HEDEF DEPREM (Kandilli): M{hedef['magnitude']} | {hedef['location_name']} | "
          f"({hedef['latitude']}, {hedef['longitude']}) | {hedef['depth_km']} km")
    print(f"Secim: {secim_notu}\n")

    # 2) Kullanicilari hedef cevresine yerlestir (HTTP: kayit+giris+tercih, PARALEL)
    kullanicilar = simulasyon.sahte_kullanicilari_hazirla(
        kullanici_sayisi, hedef["latitude"], hedef["longitude"], simulasyon.KUME_YAYILIM_KM,
    )
    if tasima:
        # ESKI demo hilesi (artik varsayilan degil): izleneni depremin yanina HTTP ile tasi.
        try:
            sifre = simulasyon.BILINEN_SIFRELER.get(izlenen, f"{izlenen}123")
            token = izlenen_token or simulasyon.giris_yap(izlenen, sifre)
            lat, lon = simulasyon._rastgele_nokta_km(hedef["latitude"], hedef["longitude"], 10)
            simulasyon.tercihleri_guncelle(token, lat, lon, radius_km=100, min_mag=1.0)
            print(f"{len(kullanicilar)} sim kullanici yerlestirildi (+ '{izlenen}' hedefe TASINDI).\n")
        except Exception as e:
            print(f"[UYARI] '{izlenen}' tasinamadi: {e}\n")
    else:
        print(f"{len(kullanicilar)} sim kullanici yerlestirildi ('{izlenen}' KENDI konumunda kaldi).\n")

    # 3) FAZ 1 — crowd erken uyarisi (GERCEK HTTP, PARALEL — detection GERCEK endpoint'te calisir)
    print("=" * 60)
    print("[FAZ 1 | t=0]  Crowd titreme raporlari PARALEL HTTP ile gonderiliyor...")
    basarili, basarisiz = simulasyon.dalga_gonder_ve_tespit_bekle(kullanicilar)
    olaylar = simulasyon.detections_al()
    print(f"  -> {basarili} basarili / {basarisiz} basarisiz rapor | {len(olaylar)} tespit su an mevcut. "
          f"CROWD ERKEN UYARISI gonderildi ('{izlenen}' ekranina dusmeli).")
    print("=" * 60 + "\n")

    # 4) Bekleme (gercek hayatta Kandilli dakikalar sonra aciklar)
    print(f"[BEKLEME]  Resmi Kandilli verisi {bekleme} sn sonra gelecek...\n")
    time.sleep(bekleme)

    # 5) FAZ 2 — resmi Kandilli verisi (HTTP: POST /test/earthquakes/, occurred_at = SIMDI)
    print("=" * 60)
    print("[FAZ 2 | resmi]  Kandilli olcumu HTTP ile giriliyor, dogrulaniyor...")
    sonuc = _resmi_deprem_gir(hedef)
    print(f"  -> Resmi deprem eklendi (id={sonuc['id']}). Dogrulama ve UZAK BILGILENDIRME "
          f"sunucu tarafinda otomatik calisti (POST /test/earthquakes/ icinde). "
          f"KANDILLI TEYIDI gonderildi.")
    print("=" * 60 + "\n")

    print("Demo bitti. Izlenen kullanici once crowd uyarisini, sonra Kandilli teyidini gormeli.")
    print("(Temizlik: python scripts/simulasyon.py --temizle)")


def main():
    parser = argparse.ArgumentParser(description="Deprem zaman cizelgesi demosu (GERCEK HTTP ile)")
    parser.add_argument("--url", default=simulasyon.BASE_URL, help="Backend adresi")
    parser.add_argument("--bekleme", type=int, default=15, help="Faz 1 ile Faz 2 arasi saniye (varsayilan 15)")
    parser.add_argument("--izlenen", default="Toprak", help="Iki bildirimi de alacak izlenen kullanici")
    parser.add_argument("--kullanici-sayisi", type=int, default=50, help="Crowd kullanici sayisi (>= alarm esigi)")
    parser.add_argument("--tasima", action="store_true",
                        help="ESKI demo modu: rastgele deprem sec + izleneni depremin yanina tasi")
    parser.add_argument("--uzak", action="store_true",
                        help="UZAK mod: izlenene 150-550 km mesafede deprem sec (BILGI bildirimi demosu)")
    args = parser.parse_args()
    simulasyon.BASE_URL = args.url
    senaryo_calistir(bekleme=args.bekleme, izlenen=args.izlenen,
                     kullanici_sayisi=args.kullanici_sayisi, tasima=args.tasima,
                     uzak=args.uzak)


if __name__ == "__main__":
    main()
