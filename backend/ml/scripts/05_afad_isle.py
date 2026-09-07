"""Asama 7.2 - AFAD TADAS'tan indirilen 54 .asc dosyasini (18 istasyon x 3 eksen),
STEAD/CSN ile AYNI kompakt .npz formatina cevirir - boylece 7.3 (fuzyon) adimi
uc kaynagi da tek tip bir arayuzden okuyabilir.

.asc format notu: ilk ~60 satir 'ANAHTAR: deger' seklinde header (SAMPLING_INTERVAL_S,
STATION_CODE, PGA_CM/S^2 vb. icerir), sonrasi tek sutunluk sayisal veri (birim: cm/s^2).
Header/veri ayrimi: header satirlarinin HEPSİ ':' iceriyor, veri satirlari icermiyor.

Calistirma: proje kokunden (deprem/) `python ml/scripts/05_afad_isle.py`
"""
import re
from pathlib import Path

import numpy as np

AFAD_DIZINI = Path("ml/raw_data/afad")
CIKTI_YOLU = "ml/data/afad_dalgaformlari.npz"

DOSYA_DESENI = re.compile(r"^(.+)_unprocessed_RawAcc_(E|N|U)\.asc$")


def _header_ve_veriyi_ayir(satirlar: list[str]) -> tuple[dict[str, str], np.ndarray]:
    header, veri_satirlari = {}, []
    for s in satirlar:
        s = s.strip()
        if not s:
            continue
        if ":" in s:
            anahtar, _, deger = s.partition(":")
            header[anahtar.strip()] = deger.strip()
        else:
            veri_satirlari.append(s)
    veri = np.array([float(x) for x in veri_satirlari], dtype=np.float32)
    return header, veri


def main() -> None:
    dosyalar = sorted(AFAD_DIZINI.glob("*.asc"))
    print(f"Toplam .asc dosyasi: {len(dosyalar)}")

    gruplar: dict[str, dict[str, Path]] = {}
    for dosya in dosyalar:
        eslesme = DOSYA_DESENI.match(dosya.name)
        if not eslesme:
            print(f"  UYARI: beklenmeyen dosya adi, atlaniyor: {dosya.name}")
            continue
        kok, eksen = eslesme.groups()
        gruplar.setdefault(kok, {})[eksen] = dosya

    dalgalar, kayit_adi_listesi, istasyon_listesi = [], [], []
    magnitude_listesi, mesafe_listesi, tepe_genlik_listesi, ornekleme_hizi_listesi = [], [], [], []

    for kok, eksenler in sorted(gruplar.items()):
        if set(eksenler) != {"E", "N", "U"}:
            print(f"  {kok}: eksik eksen ({set(eksenler)}), atlaniyor")
            continue

        headerlar, veriler = {}, {}
        for eksen, dosya in eksenler.items():
            header, veri = _header_ve_veriyi_ayir(dosya.read_text(encoding="utf-8", errors="replace").split("\n"))
            headerlar[eksen] = header
            veriler[eksen] = veri

        min_uzunluk = min(len(v) for v in veriler.values())
        dalga = np.stack(
            [veriler["E"][:min_uzunluk], veriler["N"][:min_uzunluk], veriler["U"][:min_uzunluk]],
            axis=-1,
        )

        ornek_header = headerlar["E"]
        ornekleme_hizi = 1.0 / float(ornek_header["SAMPLING_INTERVAL_S"])
        magnitude = float(ornek_header["MAGNITUDE_W"]) if ornek_header.get("MAGNITUDE_W") else None
        mesafe = float(ornek_header["EPICENTRAL_DISTANCE_KM"]) if ornek_header.get("EPICENTRAL_DISTANCE_KM") else None

        dalgalar.append(dalga)
        kayit_adi_listesi.append(kok)
        istasyon_listesi.append(ornek_header.get("STATION_CODE", ""))
        magnitude_listesi.append(magnitude)
        mesafe_listesi.append(mesafe)
        tepe_genlik_listesi.append(float(np.abs(dalga).max()))
        ornekleme_hizi_listesi.append(ornekleme_hizi)
        print(f"  {kok}: M{magnitude}, {mesafe}km, {ornekleme_hizi:.0f}Hz, {dalga.shape[0]} ornek")

    print(f"\nToplam islenen kayit: {len(dalgalar)}")

    dalgalar_obj = np.empty(len(dalgalar), dtype=object)
    for i, d in enumerate(dalgalar):
        dalgalar_obj[i] = d

    np.savez_compressed(
        CIKTI_YOLU,
        dalgalar=dalgalar_obj,
        kayit_adi=np.array(kayit_adi_listesi),
        istasyon=np.array(istasyon_listesi),
        magnitude=np.array(magnitude_listesi, dtype=np.float32),
        distance_km=np.array(mesafe_listesi, dtype=np.float32),
        tepe_genlik=np.array(tepe_genlik_listesi),
        ornekleme_hizi=np.array(ornekleme_hizi_listesi),
    )
    print(f"Yazildi: {CIKTI_YOLU}")


if __name__ == "__main__":
    main()
