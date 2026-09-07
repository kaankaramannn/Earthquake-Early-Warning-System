"""
Kandilli "son depremler" (lst4.asp) çekici/ayrıştırıcı.

Bu script BACKEND'in parçası değildir. Kandilli'nin son deprem listesini CANLI çeker,
sabit-genişlikli metni ayrıştırıp deprem kayıtlarına (dict) çevirir ve yerel bir kopya
(`data/kandilli.txt`) kaydeder. İnternet yoksa bu kopyadan okur.

Deprem dict formatı:
    {occurred_at, latitude, longitude, depth_km, magnitude, location_name}
"""

import sys
import re
import random
from pathlib import Path
from datetime import datetime

# Windows konsolu icin UTF-8
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import requests

KANDILLI_URL = "http://www.koeri.boun.edu.tr/scripts/lst4.asp"
# scripts/kandilli_cek.py -> parent (scripts) -> parent (deprem/) -> data/kandilli.txt
YEREL_KOPYA = Path(__file__).resolve().parent.parent / "data" / "kandilli.txt"

# Veri satirlari "YYYY.MM.DD" ile baslar; baslik satirlarini bu desenle eleriz.
_TARIH_DESENI = re.compile(r"\d{4}\.\d{2}\.\d{2}")


def _ham_veri_al() -> str:
    """Kandilli sayfasini ceker (<pre> blogu). Basarisizsa yerel kopyadan okur."""
    try:
        cevap = requests.get(KANDILLI_URL, timeout=15)
        cevap.encoding = "iso-8859-9"  # Kandilli Turkce kodlamasi
        metin = cevap.text
        bas = metin.lower().find("<pre>")
        son = metin.lower().find("</pre>")
        icerik = metin[bas + 5:son] if (bas != -1 and son != -1) else metin
        with open(YEREL_KOPYA, "w", encoding="utf-8") as dosya:
            dosya.write(icerik)
        return icerik
    except Exception as hata:
        print(f"[UYARI] Canli cekme basarisiz ({hata}); yerel kopyadan okunuyor.")
        with open(YEREL_KOPYA, "r", encoding="utf-8") as dosya:
            return dosya.read()


def _sayi(deger: str):
    """'-.-' gibi gecersiz degerleri None yapar, sayiyi float dondurur."""
    try:
        return float(deger)
    except (ValueError, TypeError):
        return None


def depremleri_getir() -> list[dict]:
    """Kandilli listesini ayristirip deprem dict'lerinin listesini dondurur
    (en yeniden eskiye sirali).
    """
    ham = _ham_veri_al()
    depremler = []
    for satir in ham.splitlines():
        parcalar = satir.split()
        # Sutunlar: tarih saat enlem boylam derinlik MD ML Mw Yer... Cozum
        if len(parcalar) < 10 or not _TARIH_DESENI.fullmatch(parcalar[0]):
            continue
        try:
            occurred_at = datetime.strptime(parcalar[0] + " " + parcalar[1], "%Y.%m.%d %H:%M:%S")
            latitude = float(parcalar[2])
            longitude = float(parcalar[3])
            depth_km = float(parcalar[4])
            # Buyukluk oncelik sirasi: ML (parcalar[6]) > Mw (parcalar[7]) > MD (parcalar[5])
            magnitude = next(
                (m for m in (_sayi(parcalar[6]), _sayi(parcalar[7]), _sayi(parcalar[5])) if m is not None),
                None,
            )
            if magnitude is None:
                continue
            # Yer, 8. token'dan son token'a (Cozum Niteligi) kadar olan kisim
            location_name = " ".join(parcalar[8:-1])
        except (ValueError, IndexError):
            continue

        depremler.append({
            "occurred_at": occurred_at,
            "latitude": latitude,
            "longitude": longitude,
            "depth_km": depth_km,
            "magnitude": magnitude,
            "location_name": location_name,
        })
    return depremler


def deprem_sec(depremler: list[dict] = None, secim="en_buyuk") -> dict:
    """Listeden bir deprem secer. secim: 'en_buyuk' | 'en_yeni' | int (index)."""
    if depremler is None:
        depremler = depremleri_getir()
    if not depremler:
        return None
    if secim == "en_buyuk":
        return max(depremler, key=lambda d: d["magnitude"])
    if secim == "en_yeni":
        return depremler[0]  # liste en yeniden eskiye sirali
    if secim == "rastgele":
        return random.choice(depremler)
    return depremler[int(secim)]


if __name__ == "__main__":
    depremler = depremleri_getir()
    print(f"Toplam {len(depremler)} deprem ayristirildi.\n")
    print("Ilk 5 deprem:")
    for d in depremler[:5]:
        print(f"  {d['occurred_at']} | M{d['magnitude']} | "
              f"({d['latitude']}, {d['longitude']}) | {d['depth_km']} km | {d['location_name']}")
    en_buyuk = deprem_sec(depremler, "en_buyuk")
    print(f"\nEn buyuk deprem: M{en_buyuk['magnitude']} | {en_buyuk['location_name']} | "
          f"({en_buyuk['latitude']}, {en_buyuk['longitude']})")
