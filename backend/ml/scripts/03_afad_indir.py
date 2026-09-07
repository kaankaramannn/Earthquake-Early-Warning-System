"""Asama 7.2 - AFAD TADAS'tan secilen 19 deprem icin, epimerkeze EN YAKIN istasyonun
ham (unprocessed) 3-eksenli ivme kaydini indirir.

Misafir (guest) erisim notlari (reverse-engineering ile bulundu, tadas.afad.gov.tr'nin
kendi Angular kodundan):
  - Giris: POST ivmeservis.afad.gov.tr/Admin/Login/GuestUser/<nonce> -> JWT token
  - Sorgu/indirme istekleri UC ozel header GEREKTIRIYOR: Authorization, Username, IsGuest
  - Tarih alanlari 'Z' (UTC) soneki OLMADAN gonderilmeli, yoksa sunucu sessizce
    bos sonuc donuyor (500 ya da 204, hata mesaji YOK - bulmasi zor bir davranis).
  - Ham veri indirme AYRI bir servisten geliyor: ivmeprocessguest.afad.gov.tr/ExportData
    (misafir icin ozel ikinci bir process sunucusu) - normal ivmeservis'ten degil.
  - Misafir hesabi TEK istekte en fazla 10 dosya adi kabul ediyor (kod: "auth.isUserGuest()
    && mySelection.length>10" uyarisi) - biz zaten istek basina 1 istasyon indiriyoruz.

Calistirma: proje kokunden (deprem/) `python ml/scripts/03_afad_indir.py`
"""
import json
import time
import zipfile
from pathlib import Path

import requests

GUEST_LOGIN_URL = "https://ivmeservis.afad.gov.tr/Admin/Login/GuestUser/LyxC5kJSiz4Eu95SYWyQ"
EVENTS_URL = "https://ivmeservis.afad.gov.tr/Event/GetEvents"
WAVEFORMS_BY_EVENT_URL = "https://ivmeservis.afad.gov.tr/Waveforms/GetWaveformsByEventId/{}"
EXPORT_URL = "https://ivmeprocessguest.afad.gov.tr/ExportData"

SECILEN_OLAYLAR_YOLU = "ml/raw_data/afad_secilen_olaylar.json"
CIKTI_DIZINI = Path("ml/raw_data/afad")


def guest_oturumu_ac() -> dict:
    """Misafir girisi yapar, sonraki tum istekler icin gereken 3 ozel header'i dondurur."""
    r = requests.get(GUEST_LOGIN_URL, headers={"User-Agent": "Mozilla/5.0"}, timeout=30)
    r.raise_for_status()
    veri = r.json()
    return {
        "Authorization": f"Bearer {veri['token']}",
        "Username": veri["username"],
        "IsGuest": "true",
    }


def en_yakin_istasyonu_bul(headers: dict, event_id: int) -> dict | None:
    """Bu olay icin kayitli tum istasyonlari ceker, epimerkeze (repi) en yakin ve
    GECERLI bir PGA degeri olani (bos/sifir kayitlari elemek icin) dondurur."""
    r = requests.get(WAVEFORMS_BY_EVENT_URL.format(event_id), headers=headers, timeout=30)
    r.raise_for_status()
    kayitlar = r.json()
    gecerli = [
        k for k in kayitlar
        if k.get("repi") is not None and k.get("pgaMagnitude") and k.get("recordFile")
    ]
    if not gecerli:
        return None
    return min(gecerli, key=lambda k: k["repi"])


def ham_veriyi_indir(headers: dict, kayit: dict, hedef_dizin: Path) -> bool:
    """En yakin istasyonun HAM (unprocessed) 3-eksenli .asc dosyalarini indirir ve cikarir."""
    process_type = "unprocessed" if kayit.get("isUnprocessed") else (
        "mp" if kayit.get("isManual") else "ap"
    )
    govde = {
        "filename": [kayit["recordFile"]],
        "file_type": [process_type],
        "file_status": "RawAcc",
        "export_type": "asc2",
        "user_name": headers["Username"],
        "call": "afad",
    }
    r = requests.post(EXPORT_URL, json=govde, headers=headers, timeout=60)
    if r.status_code != 200 or len(r.content) < 100:
        print(f"    HATA: export basarisiz (durum={r.status_code}, boyut={len(r.content)})")
        return False

    zip_yolu = hedef_dizin / f"{kayit['recordFile']}.zip"
    zip_yolu.write_bytes(r.content)
    try:
        with zipfile.ZipFile(zip_yolu) as z:
            z.extractall(hedef_dizin)
    except zipfile.BadZipFile:
        print(f"    HATA: gecersiz zip - {zip_yolu}")
        return False
    zip_yolu.unlink()  # zip'i sil, sadece cikarilan .asc dosyalari kalsin
    return True


def main() -> None:
    CIKTI_DIZINI.mkdir(parents=True, exist_ok=True)
    olaylar = json.loads(Path(SECILEN_OLAYLAR_YOLU).read_text(encoding="utf-8"))
    print(f"Misafir oturumu aciliyor...")
    headers = guest_oturumu_ac()
    print(f"  basarili, kullanici: {headers['Username']}")

    basarili, basarisiz = 0, []
    for i, olay in enumerate(olaylar):
        print(f"[{i + 1}/{len(olaylar)}] {olay['eqLocation']} (id={olay['id']})...")
        istasyon = en_yakin_istasyonu_bul(headers, olay["id"])
        if istasyon is None:
            print("    UYARI: gecerli istasyon bulunamadi, atlaniyor")
            basarisiz.append(olay["id"])
            continue
        print(
            f"    en yakin istasyon: {istasyon['stationCode']} "
            f"(repi={istasyon['repi']:.1f}km, pga={istasyon['pgaMagnitude']:.1f})"
        )
        if ham_veriyi_indir(headers, istasyon, CIKTI_DIZINI):
            basarili += 1
        else:
            basarisiz.append(olay["id"])
        time.sleep(1)  # sunucuya nazik olmak icin kucuk bir bekleme

    print(f"\nTamamlandi: {basarili}/{len(olaylar)} basarili")
    if basarisiz:
        print(f"Basarisiz event_id'ler: {basarisiz}")


if __name__ == "__main__":
    main()
