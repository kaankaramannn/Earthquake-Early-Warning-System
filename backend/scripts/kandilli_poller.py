"""
Kandilli deprem verisini periyodik olarak backend'e OTOMATIK besleyen script.

Aşama 4 (Google kıyaslaması plani): resmi kaynak entegrasyonu artik elle (admin
Swagger'dan tek tek POST atarak) degil, bu BAGIMSIZ script sayesinde otomatik.
Backend'in KENDISI hic degismedi — script sadece mevcut POST /test/earthquakes/
uc noktasini, Kandilli'de YENI bir deprem gordugunde kendiliginden cagiriyor.
Bu endpoint zaten sunucu tarafinda tespitleri_dogrula + uzak_bilgilendirme_olustur'u
otomatik tetikliyor (bkz. src/dev/router.py) — bu script onlari bir daha hic
import/cagirmiyor, hatta bilmiyor bile.

kandilli_cek.py gibi bu script de "backend'in parcasi" degil (bkz. kandilli_cek.py'nin
kendi docstring'i) — bu yuzden src.* import ETMIYOR, kendi kucuk haversine_km kopyasini
tasiyor (routers/notifications.py'deki ile AYNI formul, kasitli kucuk kod tekrari).

Calistirma: proje kokunden (deprem/) `python scripts/kandilli_poller.py`
Tek seferlik test icin: `python scripts/kandilli_poller.py --tek-seferlik`
"""
import sys
import time
import argparse
from datetime import datetime
from math import radians, sin, cos, sqrt, atan2

import requests

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import kandilli_cek

VARSAYILAN_URL = "http://127.0.0.1:8000"
VARSAYILAN_ARALIK_SN = 120.0
DEDUP_ZAMAN_TOLERANSI_DK = 5   # bu kadar dakika icinde olusan kayitlar "ayni olay" sayilir
DEDUP_MESAFE_TOLERANSI_KM = 5  # bu kadar km icinde olusan kayitlar "ayni olay" sayilir


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Iki nokta arasi mesafe (km) — src/notify/router.py'deki ile AYNI formul."""
    R = 6371
    lat1_rad, lon1_rad = radians(lat1), radians(lon1)
    lat2_rad, lon2_rad = radians(lat2), radians(lon2)
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    a = sin(dlat / 2) ** 2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c


def admin_token_al(base_url: str, username: str, password: str) -> str:
    """Login olup JWT access token dondurur (bildirim_takip.py'deki ile ayni desen)."""
    cevap = requests.post(
        f"{base_url}/auth/login/",
        data={"username": username, "password": password},
    )
    cevap.raise_for_status()
    return cevap.json()["access_token"]


def bilinen_depremleri_getir(base_url: str) -> list[dict]:
    """GET /earthquakes/ — herkese acik, dedup icin mevcut resmi kayitlari ceker."""
    cevap = requests.get(f"{base_url}/earthquakes/", params={"limit": 100})
    cevap.raise_for_status()
    return cevap.json()


def zaten_eklenmis_mi(hedef: dict, bilinenler: list[dict]) -> bool:
    """Kandilli'nin kendi listesinde benzersiz bir ID olmadigi icin, yeni bir kaydin
    backend'de ZATEN var olan bir depremle ayni olup olmadigina zaman+konum yakinligiyla
    bakar (tam eslesme degil, tolerans payi — bkz. DEDUP_* sabitleri)."""
    for b in bilinenler:
        bilinen_zaman = datetime.fromisoformat(b["occurred_at"])
        zaman_farki_dk = abs((hedef["occurred_at"] - bilinen_zaman).total_seconds()) / 60
        if zaman_farki_dk > DEDUP_ZAMAN_TOLERANSI_DK:
            continue
        mesafe = haversine_km(hedef["latitude"], hedef["longitude"], b["latitude"], b["longitude"])
        if mesafe <= DEDUP_MESAFE_TOLERANSI_KM:
            return True
    return False


def deprem_ekle(base_url: str, token: str, hedef: dict) -> dict:
    """POST /test/earthquakes/ (admin) — bu cagri sunucu tarafinda tespitleri_dogrula +
    uzak_bilgilendirme_olustur'u OTOMATIK tetikliyor, script bunlari hic bilmiyor."""
    cevap = requests.post(
        f"{base_url}/test/earthquakes/",
        json={
            "magnitude": hedef["magnitude"],
            "latitude": hedef["latitude"],
            "longitude": hedef["longitude"],
            "depth_km": hedef["depth_km"],
            "occurred_at": hedef["occurred_at"].isoformat(),
            "location_name": hedef["location_name"],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    cevap.raise_for_status()
    return cevap.json()


def bir_tur_calistir(base_url: str, token: str, kontrol_edilecek_sayi: int) -> int:
    """Kandilli'nin en yeni N depremini kontrol eder, backend'de olmayanlari ekler.
    Donen: bu turda eklenen yeni deprem sayisi."""
    depremler = kandilli_cek.depremleri_getir()[:kontrol_edilecek_sayi]
    bilinenler = bilinen_depremleri_getir(base_url)

    eklenen = 0
    for hedef in depremler:
        if zaten_eklenmis_mi(hedef, bilinenler):
            continue
        try:
            sonuc = deprem_ekle(base_url, token, hedef)
            print(f"[YENI] M{hedef['magnitude']} | {hedef['location_name']} | "
                  f"({hedef['latitude']}, {hedef['longitude']}) -> id={sonuc['id']}, "
                  f"eslesen_kullanici_sayisi={sonuc['eslesen_kullanici_sayisi']}")
            eklenen += 1
            bilinenler.append(sonuc)  # ayni tur icinde bir kez daha eklenmesin
        except requests.RequestException as e:
            print(f"[HATA] '{hedef['location_name']}' eklenemedi: {e}")
    return eklenen


def main() -> None:
    parser = argparse.ArgumentParser(description="Kandilli -> backend otomatik deprem besleyici")
    parser.add_argument("--url", default=VARSAYILAN_URL, help="Backend adresi")
    parser.add_argument("--aralik", type=float, default=VARSAYILAN_ARALIK_SN,
                        help="Kontroller arasi bekleme (sn, varsayilan 120)")
    parser.add_argument("--admin-kullanici", default="Kaan")
    parser.add_argument("--admin-sifre", default="Kaan123")
    parser.add_argument("--kontrol-sayisi", type=int, default=5,
                        help="Kandilli listesinin en yeni kac kaydi kontrol edilsin")
    parser.add_argument("--tek-seferlik", action="store_true",
                        help="Sadece bir kez calistir, surekli dongu YAPMA (test icin)")
    args = parser.parse_args()

    print(f"-> {args.url} adresine admin olarak giris yapiliyor...")
    token = admin_token_al(args.url, args.admin_kullanici, args.admin_sifre)
    print(f"-> Giris basarili. Kandilli her {args.aralik:.0f} sn'de bir kontrol edilecek "
          f"(durdurmak icin Ctrl+C).\n")

    def tek_tur() -> None:
        try:
            eklenen = bir_tur_calistir(args.url, token, args.kontrol_sayisi)
            if eklenen == 0:
                print(f"   ... yeni deprem yok ({time.strftime('%H:%M:%S')})")
        except requests.RequestException as e:
            print(f"[UYARI] Kontrol basarisiz, sonraki turda tekrar denenecek: {e}")

    if args.tek_seferlik:
        tek_tur()
        return

    try:
        while True:
            tek_tur()
            time.sleep(args.aralik)
    except KeyboardInterrupt:
        print("\n-> Otomatik besleme durduruldu.")


if __name__ == "__main__":
    main()
