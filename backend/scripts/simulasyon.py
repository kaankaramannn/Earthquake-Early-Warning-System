"""Deprem tespit simulasyonu — GERCEK HTTP istekleriyle (Faz: HTTP'ye gecis).

Eskiden bu script veritabanina DOGRUDAN (in-process) yaziyor ve tespiti
tespit_et_ve_kaydet(session) fonksiyonunu ELLE cagirarak tetikliyordu. Artik
sahte kullanicilar GERCEKTEN /auth/register/ + /auth/login/ ile hesap acip
giris yapiyor, raporlarini da PARALEL HTTP istekleriyle POST /tremor-reports/'a
gonderiyor. Tespit kararini artik GERCEK endpoint (ve onun tetikledigi
tespit_et_ve_kaydet) veriyor — bu script bir daha o fonksiyonu cagirmiyor.

Tek istisna: --temizle hala in-process (test hijyeni; bulk-delete admin
endpoint'i yok, kapsam disi).

Bilinen davranis (kod degisikligi GEREKTIRMEZ): POST /tremor-reports/ her
istekten SONRA senkron olarak tespit_et_ve_kaydet'i cagiriyor (toplu degil,
istek basina). Paralel gelen bir dalga, sunucuya inis sirasina gore 1 yerine
birkac kucuk kumeye PARCALANABILIR. Bu yuzden asagidaki senaryo kontrolleri
katı "== beklenen sayi" yerine "en az / tam 0" gibi siralamadan bagimsiz,
saglam esiklere dayanir.

Calistirma: proje kokunden (deprem/) `python scripts/simulasyon.py ...`
"""
import sys
import time
import math
import random
import argparse
import concurrent.futures as cf
from pathlib import Path

import requests

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# scripts/ kendi klasorunu sys.path'e ekler, proje kokunu (deprem/) DEGIL —
# "src.*" import'larinin calismasi icin proje kokunu elle ekliyoruz.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import src.main  # noqa: F401 — SQLModel metadata'sini kaydettirir (--temizle icin)
from sqlmodel import Session, select
from src.database import engine
from src.users.models import User
from src.notify.models import Notification
from src.tremor.models import TremorReport
from src.detect.models import DetectionEvent, PreliminaryAlert, FeltReport
from src.notify.router import haversine_km
from src.detect.router import ALARM_ESIK, TAZE_RAPOR_BEKLEME_SN  # sadece sabit — fonksiyon cagirmiyoruz
import kandilli_cek

# Simulasyon ciktisini temiz tutmak icin SQL log selini sustur (--temizle icin).
engine.echo = False

# --- Ayarlar ---
BASE_URL = "http://127.0.0.1:8000"
SIM_SIFRE = "sim123"  # eski in-process kullanicilarla da uyumlu (ayni hash kaynagi)
MAX_WORKER = 20
ISTEK_ZAMAN_ASIMI = 10

# Test kullanicilarinin bilinen sifreleri (rastgele/deprem_senaryosu --izlenen icin).
BILINEN_SIFRELER = {"Kaan": "Kaan123", "Toprak": "Toprak123", "Ahmet": "Ahmet123"}

# Kume yayilimi (km): tespit yaricapi 2 km'nin rahat altinda kalsin (max ikili mesafe ~2*bu).
KUME_YAYILIM_KM = 0.7
TURKIYE_MERKEZI = (39.0, 35.0)
GURULTU_YAYILIM_KM = 300.0  # gurultu senaryosu: ulke capina dagitmak icin genis yayilim

# Kandilli deprem listesi bir kez cekilip cache'lenir (tekrar tekrar ag istegi olmasin).
_kandilli_cache = None


def _kandilli_depremler() -> list[dict]:
    global _kandilli_cache
    if _kandilli_cache is None:
        _kandilli_cache = kandilli_cek.depremleri_getir()
    return _kandilli_cache


def _hedef_deprem() -> dict:
    """Kandilli listesindeki EN BUYUK depremi dondurur (senaryo hedefi)."""
    return max(_kandilli_depremler(), key=lambda d: d["magnitude"])


def _rastgele_deprem() -> dict:
    """Kandilli listesinden RASTGELE bir deprem secer."""
    return random.choice(_kandilli_depremler())


def _iki_uzak_deprem(min_mesafe_km: float = 100) -> tuple[dict, dict]:
    """Birbirinden en az min_mesafe_km uzakta iki deprem secer (iki bolge senaryosu icin)."""
    depremler = sorted(_kandilli_depremler(), key=lambda d: d["magnitude"], reverse=True)
    ilk = depremler[0]
    for d in depremler[1:]:
        if haversine_km(ilk["latitude"], ilk["longitude"], d["latitude"], d["longitude"]) >= min_mesafe_km:
            return ilk, d
    return depremler[0], depremler[1]  # fallback


def _rastgele_nokta_km(merkez_lat: float, merkez_lon: float, yaricap_km: float) -> tuple[float, float]:
    """merkez etrafinda, 0..yaricap_km uzakliginda RASTGELE bir (lat, lon) noktasi dondurur.
    Aci + mesafe yontemi (haversine ile tutarli) — _izleyiciyi_yaklastir'daki formulun genel hali.
    """
    aci = random.uniform(0, 2 * math.pi)
    mesafe = random.uniform(0, yaricap_km)
    dlat = (mesafe / 111.0) * math.cos(aci)
    dlon = (mesafe / (111.0 * math.cos(math.radians(merkez_lat)))) * math.sin(aci)
    return merkez_lat + dlat, merkez_lon + dlon


# ============================================================
# HTTP cekirdegi — bildirim_takip.py'deki auth desenini izler
# ============================================================

def kaydol(username: str, email: str, sifre: str) -> None:
    """Kullanici kaydeder. Zaten kayitliysa (409) sessizce gecer (idempotent)."""
    cevap = requests.post(
        f"{BASE_URL}/auth/register/",
        json={"username": username, "email": email, "password": sifre},
        timeout=ISTEK_ZAMAN_ASIMI,
    )
    if cevap.status_code not in (200, 201, 409):
        raise RuntimeError(f"Kayit basarisiz ({username}): {cevap.status_code} {cevap.text}")


def giris_yap(username: str, sifre: str) -> str:
    """Login olup JWT access token dondurur (bildirim_takip.token_al ile ayni desen)."""
    cevap = requests.post(
        f"{BASE_URL}/auth/login/",
        data={"username": username, "password": sifre},
        timeout=ISTEK_ZAMAN_ASIMI,
    )
    if cevap.status_code != 200:
        raise RuntimeError(f"Giris basarisiz ({username}): {cevap.status_code} {cevap.text}")
    return cevap.json()["access_token"]


def tercihleri_guncelle(token: str, lat: float, lon: float,
                        radius_km: float = 100.0, min_mag: float = 3.0) -> None:
    cevap = requests.patch(
        f"{BASE_URL}/user/preferences/",
        json={
            "pref_latitude": lat,
            "pref_longitude": lon,
            "pref_radius_km": radius_km,
            "pref_min_magnitude": min_mag,
        },
        headers={"Authorization": f"Bearer {token}"},
        timeout=ISTEK_ZAMAN_ASIMI,
    )
    if cevap.status_code != 200:
        raise RuntimeError(f"Tercih guncelleme basarisiz: {cevap.status_code} {cevap.text}")


def titresim_gonder(token: str, lat: float, lon: float, intensity: float) -> requests.Response:
    return requests.post(
        f"{BASE_URL}/tremor-reports/",
        json={"latitude": lat, "longitude": lon, "intensity": intensity},
        headers={"Authorization": f"Bearer {token}"},
        timeout=ISTEK_ZAMAN_ASIMI,
    )


def admin_token_al() -> str:
    return giris_yap("Kaan", BILINEN_SIFRELER["Kaan"])


def detections_tetikle(admin_token: str | None = None) -> list[dict]:
    """POST /detections/run (admin) — kumeleme algoritmasini SIMDI, TEK seferde calistirir.
    Olgunlasma penceresi (TAZE_RAPOR_BEKLEME_SN) ile birlikte kullanilir: bir dalga
    gonderildikten sonra bu pencere kadar beklenip bu fonksiyon cagrilirsa, TUM raporlar
    henuz hicbiri "kullanilmamis" halde iken TEK kumede degerlendirilir — paralel HTTP'nin
    istek-basina-erken-tetikleme yuzunden kucuk parcalara bolunmesini engeller."""
    token = admin_token or admin_token_al()
    cevap = requests.post(
        f"{BASE_URL}/detections/run",
        headers={"Authorization": f"Bearer {token}"},
        timeout=ISTEK_ZAMAN_ASIMI,
    )
    cevap.raise_for_status()
    return cevap.json()


def dalga_gonder_ve_tespit_bekle(kullanici_haritasi: dict[str, tuple[str, float, float]],
                                 admin_token: str | None = None,
                                 ekstra_bekleme: float = 1.0,
                                 **dalga_gonder_kwargs) -> tuple[int, int]:
    """dalga_gonder + olgunlasma penceresi kadar bekleme + TEK temiz tespit tetiklemesi.
    Boylece GERCEK paralel HTTP trafiginde bile tek fiziksel patlama TEK kumede kalir —
    hem gercekci (gercek istek, gercek endpoint tespit ediyor) hem de temiz/deterministik."""
    admin_token = admin_token or admin_token_al()
    sonuc = dalga_gonder(kullanici_haritasi, **dalga_gonder_kwargs)
    time.sleep(TAZE_RAPOR_BEKLEME_SN + ekstra_bekleme)
    detections_tetikle(admin_token)
    return sonuc


def detections_al(admin_token: str | None = None) -> list[dict]:
    """GET /detections/ (admin) — dogrulama/yazdirma icin. Dalga_gonder senkron dondugu
    an (her POST kendi icinde detection'i bitirmis oldugundan) ekstra bekleme gerekmez."""
    token = admin_token or admin_token_al()
    cevap = requests.get(
        f"{BASE_URL}/detections/",
        headers={"Authorization": f"Bearer {token}"},
        timeout=ISTEK_ZAMAN_ASIMI,
    )
    cevap.raise_for_status()
    return cevap.json()


# ============================================================
# Kullanici hazirlama + rapor gonderme (PARALEL, ThreadPoolExecutor)
# ============================================================

def _tek_kullanici_hazirla(i: int, merkez_lat: float, merkez_lon: float, yayilim_km: float,
                          radius_km: float, min_mag: float) -> tuple[str, str, float, float]:
    username = f"sim_{i:05d}"
    email = f"{username}@example.com"
    kaydol(username, email, SIM_SIFRE)
    token = giris_yap(username, SIM_SIFRE)
    lat, lon = _rastgele_nokta_km(merkez_lat, merkez_lon, yayilim_km)
    tercihleri_guncelle(token, lat, lon, radius_km, min_mag)
    return username, token, lat, lon


def sahte_kullanicilari_hazirla(n: int, merkez_lat: float, merkez_lon: float,
                                yayilim_km: float = KUME_YAYILIM_KM, baslangic: int = 1,
                                radius_km: float = 100.0, min_mag: float = 3.0,
                                max_worker: int | None = None) -> dict[str, tuple[str, float, float]]:
    """n sahte kullaniciyi HTTP uzerinden kaydet+giris+tercih ayarlar (PARALEL).
    Donen: {username: (token, lat, lon)} — rapor gonderirken konum tekrar hesaplanmasin.
    """
    # max_worker'i CAGRI ANINDA global'den oku (--max-worker CLI override'i icin);
    # varsayilan parametre degeri modul yuklenirken donacagi icin sonradan degismezdi.
    max_worker = max_worker or MAX_WORKER
    sonuc: dict[str, tuple[str, float, float]] = {}
    basarisiz: list[tuple[int, str]] = []
    with cf.ThreadPoolExecutor(max_workers=max_worker) as havuz:
        gorevler = {
            havuz.submit(_tek_kullanici_hazirla, i, merkez_lat, merkez_lon, yayilim_km, radius_km, min_mag): i
            for i in range(baslangic, baslangic + n)
        }
        for gorev in cf.as_completed(gorevler):
            i = gorevler[gorev]
            try:
                username, token, lat, lon = gorev.result()
                sonuc[username] = (token, lat, lon)
            except Exception as e:
                basarisiz.append((i, str(e)))
    if basarisiz:
        print(f"  [UYARI] {len(basarisiz)} kullanici hazirlanamadi (ilk hata: {basarisiz[0][1]})")
    return sonuc


def _tek_rapor_gonder(username: str, token: str, lat: float, lon: float,
                      intensity: float) -> tuple[str, int | None]:
    try:
        cevap = titresim_gonder(token, lat, lon, intensity)
        return username, cevap.status_code
    except requests.RequestException:
        return username, None  # ag hatasi -> basarisiz sayilir


def dalga_gonder(kullanici_haritasi: dict[str, tuple[str, float, float]],
                 intensity_alt: float = 3.0, intensity_ust: float = 8.0,
                 max_worker: int | None = None) -> tuple[int, int]:
    """kullanici_haritasi: {username: (token, lat, lon)}. Her kullanici KENDI (lat,lon)'undan
    PARALEL rapor gonderir. Donen: (basarili, basarisiz) istek sayisi."""
    max_worker = max_worker or MAX_WORKER
    basarisiz = 0
    with cf.ThreadPoolExecutor(max_workers=max_worker) as havuz:
        gorevler = [
            havuz.submit(_tek_rapor_gonder, username, token, lat, lon,
                        random.uniform(intensity_alt, intensity_ust))
            for username, (token, lat, lon) in kullanici_haritasi.items()
        ]
        for gorev in cf.as_completed(gorevler):
            _, kod = gorev.result()
            if kod not in (200, 201):
                basarisiz += 1
    return len(kullanici_haritasi) - basarisiz, basarisiz


# ============================================================
# Temizlik — TEK ISTISNA: in-process kalir (test hijyeni, kapsam disi)
# ============================================================

def veriyi_temizle(session: Session, kullanicilari_da_sil: bool = False) -> None:
    for model in (Notification, TremorReport, FeltReport, DetectionEvent, PreliminaryAlert):
        for row in session.exec(select(model)).all():
            session.delete(row)
    if kullanicilari_da_sil:
        for u in session.exec(select(User).where(User.username.like("sim_%"))).all():
            session.delete(u)
    session.commit()


def _sim_verilerini_temizle() -> None:
    """Onceki calistirmalardan kalan sim verisini + sim kullanicilarini siler.
    Her senaryo/dalga testi bununla temiz baslar (eski senaryo_calistir'in davranisiyla ayni)."""
    with Session(engine) as session:
        veriyi_temizle(session, kullanicilari_da_sil=True)


# ============================================================
# Senaryolar (artik GERCEK HTTP ile — detection'i script CAGIRMIYOR)
# ============================================================

def senaryo_gercek_deprem() -> dict:
    d = _hedef_deprem()
    kullanicilar = sahte_kullanicilari_hazirla(50, d["latitude"], d["longitude"], KUME_YAYILIM_KM)
    dalga_gonder_ve_tespit_bekle(kullanicilar)
    return kullanicilar


def senaryo_rastgele_gurultu() -> dict:
    kullanicilar = sahte_kullanicilari_hazirla(50, *TURKIYE_MERKEZI, GURULTU_YAYILIM_KM)
    dalga_gonder_ve_tespit_bekle(kullanicilar)
    return kullanicilar


def senaryo_yanlis_pozitif() -> dict:
    d = _hedef_deprem()
    kullanicilar = sahte_kullanicilari_hazirla(2, d["latitude"], d["longitude"], KUME_YAYILIM_KM)
    dalga_gonder_ve_tespit_bekle(kullanicilar)
    return kullanicilar


def senaryo_iki_bolge() -> dict:
    d1, d2 = _iki_uzak_deprem()
    k1 = sahte_kullanicilari_hazirla(50, d1["latitude"], d1["longitude"], KUME_YAYILIM_KM, baslangic=1)
    k2 = sahte_kullanicilari_hazirla(50, d2["latitude"], d2["longitude"], KUME_YAYILIM_KM, baslangic=51)
    kullanicilar = {**k1, **k2}
    dalga_gonder_ve_tespit_bekle(kullanicilar)
    return kullanicilar


def senaryo_buyuk_olcek() -> dict:
    d = _hedef_deprem()
    kullanicilar = sahte_kullanicilari_hazirla(200, d["latitude"], d["longitude"], KUME_YAYILIM_KM)
    dalga_gonder_ve_tespit_bekle(kullanicilar)
    return kullanicilar


# (fonksiyon, beklenen_aciklama, kontrol(olay_sayisi)->bool, aciklama)
# Olgunlasma penceresi + tek seferlik /detections/run tetiklemesi sayesinde artik
# GERCEK paralel HTTP trafiginde bile TEK temiz kume garantili — kontroller kesin sayiya
# sikilastirildi (eskiden parcalanma riski yuzunden "en az/tam 0" gibi yumusakti).
SENARYOLAR = {
    "gercek":  (senaryo_gercek_deprem,    "1", lambda n: n == 1, "Gercek deprem (Kandilli konumu, 50 kullanici)"),
    "gurultu": (senaryo_rastgele_gurultu, "0", lambda n: n == 0, "Rastgele gurultu (Turkiye'ye dagilmis 50)"),
    "yanlis":  (senaryo_yanlis_pozitif,   "0", lambda n: n == 0, "Yanlis pozitif (2 kullanici)"),
    "iki":     (senaryo_iki_bolge,        "2", lambda n: n == 2, "Iki bolge (iki uzak Kandilli depremi)"),
    "buyuk":   (senaryo_buyuk_olcek,      "1", lambda n: n == 1, "Buyuk olcek (200 kullanici, HTTP paralel)"),
}


def senaryo_calistir(ad: str) -> bool:
    fonksiyon, beklenen_aciklama, kontrol, aciklama = SENARYOLAR[ad]
    _sim_verilerini_temizle()

    t0 = time.time()
    kullanicilar = fonksiyon()
    sure = time.time() - t0

    olaylar = detections_al()
    gecti = kontrol(len(olaylar))
    isaret = "OK  " if gecti else "HATA"
    alarm_gecen = sum(1 for o in olaylar if o["report_count"] >= ALARM_ESIK)

    print(f"[{isaret}] {aciklama:44} -> {len(olaylar)} olay (beklenen {beklenen_aciklama}) | "
          f"report_count={[o['report_count'] for o in olaylar]} | alarm_esigini_asan={alarm_gecen} | "
          f"{len(kullanicilar)} kullanici (HTTP) | {sure:.2f} sn")
    return gecti


def rastgele_deprem_simule_et(kullanici_sayisi: int = 50, izlenen: str = "Toprak") -> list[dict]:
    """Kandilli listesinden RASTGELE bir depremi secip simule eder: o konuma kullanicilari
    HTTP uzerinden yerlestirir, herkes PARALEL rapor gonderir, GERCEK endpoint tespiti tetikler.
    Izlenen GERCEK kullanici (orn. Toprak), kendi hesabiyla giris yapilip PATCH /user/preferences/
    ile depremin 10 km yakinina tasinir ki bildirimi gorebilsin.
    """
    _sim_verilerini_temizle()
    d = _rastgele_deprem()
    print(f"Rastgele secilen Kandilli depremi: M{d['magnitude']} | {d['location_name']} | "
          f"({d['latitude']}, {d['longitude']}) | {d['depth_km']} km")

    kullanicilar = sahte_kullanicilari_hazirla(kullanici_sayisi, d["latitude"], d["longitude"], KUME_YAYILIM_KM)

    try:
        izlenen_sifre = BILINEN_SIFRELER.get(izlenen, f"{izlenen}123")
        izlenen_token = giris_yap(izlenen, izlenen_sifre)
        lat, lon = _rastgele_nokta_km(d["latitude"], d["longitude"], 10)
        tercihleri_guncelle(izlenen_token, lat, lon, radius_km=100, min_mag=1.0)
    except Exception as e:
        print(f"  [UYARI] '{izlenen}' konumu guncellenemedi: {e}")

    basarili, basarisiz = dalga_gonder_ve_tespit_bekle(kullanicilar)
    olaylar = detections_al()
    print(f"  -> {len(olaylar)} tespit olustu | report_count={[o['report_count'] for o in olaylar]} | "
          f"basarili_rapor={basarili} basarisiz={basarisiz} ('{izlenen}' de bildirim aldi)")
    return olaylar


def dalgalar_calistir(dalga_boyutlari: list[int], merkez_lat: float, merkez_lon: float,
                      yayilim_km: float, dalga_araligi: float) -> None:
    """Ayni merkezde ardisik PARALEL dalgalar gonderir. Her dalga kendi icinde olgunlasma
    penceresi + /detections/run ile TEK temiz kumeye toplanir, sonra sonuc yazdirilir.
    Beklenen: her dalga tek basina ALARM_ESIK (40) altinda kalirsa sessiz/pending kalir —
    yani '30 sonra 1 dk sonra 10' gibi ayri dalgalar TEK TEK, TEK'er temiz olay olarak
    degerlendirilir, toplanmaz.

    NOT: merkez, cagiran taraf (main()) tarafindan cozulur — bkz. --izlenen mantigi.
    Bir GERCEK kullaniciyi buraya tasimaya CALISMAYIN: mobil uygulamanin kendi konum
    senkronu (Faz 3), cihazin GERCEK GPS/emulator konumunu periyodik olarak geri yazar
    ve HTTP ile yapilan manuel tasimayi SESSIZCE geri alir (deprem_senaryosu.py'de
    ayni sebeple --tasima varsayilan olmaktan cikarilmisti). Dogru yontem: dalganin
    MERKEZINI kullanicinin GUNCEL konumuna gore secmek (bkz. --izlenen: en_yakin).
    """
    _sim_verilerini_temizle()
    admin_token = admin_token_al()
    baslangic_id = 1
    for i, boyut in enumerate(dalga_boyutlari, start=1):
        print(f"\n[DALGA {i}] {boyut} kullanici merkeze ({merkez_lat:.4f},{merkez_lon:.4f}) "
              f"PARALEL rapor gonderiyor...")
        kullanicilar = sahte_kullanicilari_hazirla(boyut, merkez_lat, merkez_lon, yayilim_km,
                                                   baslangic=baslangic_id)
        baslangic_id += boyut

        t0 = time.time()
        basarili, basarisiz = dalga_gonder_ve_tespit_bekle(kullanicilar, admin_token=admin_token)
        sure = time.time() - t0

        olaylar = detections_al(admin_token)
        print(f"  -> {basarili} basarili / {basarisiz} basarisiz istek | {sure:.2f} sn")
        if olaylar:
            ozet = ", ".join(f"[id={o['id']} n={o['report_count']} durum={o['status']}]" for o in olaylar)
        else:
            ozet = "yok"
        print(f"  -> Su an toplam {len(olaylar)} tespit: {ozet}")

        alarm_gecen = [o for o in olaylar if o["report_count"] >= ALARM_ESIK]
        if alarm_gecen:
            print(f"  -> UYARI: {len(alarm_gecen)} tespit ALARM ESIGINI (>= {ALARM_ESIK}) asti, bildirim gitti!")
        else:
            print(f"  -> Hicbir tespit alarm esigini (>= {ALARM_ESIK}) asmadi -> sessiz/pending kaldi (beklenen).")

        if i < len(dalga_boyutlari):
            print(f"  -> {dalga_araligi:.0f} sn bekleniyor (sonraki dalga icin)...")
            time.sleep(dalga_araligi)


def main():
    global BASE_URL, MAX_WORKER
    parser = argparse.ArgumentParser(description="Deprem tespit simulasyonu (GERCEK HTTP istekleriyle)")
    parser.add_argument("--url", default=BASE_URL, help="Backend adresi")
    parser.add_argument("--hepsi", action="store_true", help="Tum senaryolari calistir (varsayilan)")
    parser.add_argument("--senaryo", choices=SENARYOLAR.keys(), help="Sadece tek bir senaryo calistir")
    parser.add_argument("--temizle", action="store_true", help="Sim verisini ve sim kullanicilarini silip cik")
    parser.add_argument("--rastgele", action="store_true", help="Kandilli'den rastgele bir depremi simule et")
    parser.add_argument("--izlenen", default="Toprak",
                        help="--rastgele/--dalgalar ile: merkeze tasinacak GERCEK kullanici (varsayilan Toprak)")
    parser.add_argument("--dalgalar", default=None,
                        help="Virgulle ayrilmis dalga boyutlari, orn: '30,10' (paralel HTTP dalga testi)")
    parser.add_argument("--dalga-araligi", type=float, default=60.0, help="Dalgalar arasi bekleme (sn)")
    parser.add_argument("--dalga-yayilim-km", type=float, default=KUME_YAYILIM_KM,
                        help="Dalga kullanicilarinin merkez etrafindaki yayilimi (km)")
    parser.add_argument("--max-worker", type=int, default=MAX_WORKER, help="Paralel istek havuzu boyutu")
    args = parser.parse_args()

    BASE_URL = args.url
    MAX_WORKER = args.max_worker

    if args.temizle:
        _sim_verilerini_temizle()
        print("Temizlendi: sim verisi ve sim kullanicilari silindi.")
        return

    if args.dalgalar:
        boyutlar = [int(x) for x in args.dalgalar.split(",") if x.strip()]
        # Merkez: --izlenen GERCEK kullanicinin SU ANKI konumu (uygulamada gorunsun diye).
        # Kullaniciyi TASIMIYORUZ (mobil konum senkronu geri alir) — dalgayi ONUN konumuna
        # goturuyoruz. Konum okunamazsa (kullanici yok/konumu bos) en buyuk Kandilli
        # depremine duser (eski davranis).
        merkez_lat = merkez_lon = None
        if args.izlenen:
            try:
                sifre = BILINEN_SIFRELER.get(args.izlenen, f"{args.izlenen}123")
                token = giris_yap(args.izlenen, sifre)
                cevap = requests.get(f"{BASE_URL}/user/me/", headers={"Authorization": f"Bearer {token}"},
                                     timeout=ISTEK_ZAMAN_ASIMI)
                cevap.raise_for_status()
                bilgi = cevap.json()
                merkez_lat, merkez_lon = bilgi.get("pref_latitude"), bilgi.get("pref_longitude")
            except Exception as e:
                print(f"[UYARI] '{args.izlenen}' konumu okunamadi ({e}); en buyuk Kandilli depremine dusuluyor.")

        if merkez_lat is not None and merkez_lon is not None:
            print(f"Dalga testi merkezi: '{args.izlenen}' kullanicisinin GUNCEL konumu ({merkez_lat:.4f}, {merkez_lon:.4f})")
        else:
            d = _hedef_deprem()
            merkez_lat, merkez_lon = d["latitude"], d["longitude"]
            print(f"Dalga testi merkezi: {d['location_name']} ({merkez_lat}, {merkez_lon})")

        dalgalar_calistir(boyutlar, merkez_lat, merkez_lon, args.dalga_yayilim_km, args.dalga_araligi)
        print("\n(Veriyi temizlemek icin: python scripts/simulasyon.py --temizle)")
        return

    if args.rastgele:
        rastgele_deprem_simule_et(izlenen=args.izlenen)
        print("\n(Veriyi temizlemek icin: python scripts/simulasyon.py --temizle)")
        return

    if args.senaryo:
        senaryo_calistir(args.senaryo)
    else:
        sonuclar = [senaryo_calistir(ad) for ad in SENARYOLAR]
        print(f"\nGecen senaryo: {sum(sonuclar)}/{len(sonuclar)}")

    print("\n(Veriyi temizlemek icin: python scripts/simulasyon.py --temizle)")


if __name__ == "__main__":
    main()
