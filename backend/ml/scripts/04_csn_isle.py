"""Asama 7.2 - CSN'nin 19 olaylik zip arsivlerini isler: her olayda YUZLERCE istasyon
var (agin genisligi yuzunden), hepsini kullanmak hem gereksiz hem de cogu istasyon
depremden COK UZAK/ZAYIF sinyal iceriyor. Bu script her olay icin EN GUCLU sinyalli
(tepe genligi en yuksek) 2 istasyonu secip, 3 bileseni (HNE/HNN/HNZ) birlikte
kompakt bir .npz'ye yazar.

Dosya adi deseni: {olay_zamani}.{ag}.{istasyon}.{kanal}.sac (kanal: HNE/HNN/HNZ)

Calistirma: proje kokunden (deprem/) `python ml/scripts/04_csn_isle.py`
"""
import io
import re
import zipfile
from pathlib import Path

import numpy as np
from obspy import read

CSN_DIZINI = Path("ml/raw_data/csn")
CIKTI_YOLU = "ml/data/csn_dalgaformlari.npz"
ISTASYON_BASINA_HEDEF = 2  # olay basina en guclu kac istasyon secilecek

DOSYA_DESENI = re.compile(r"^(.+)\.([A-Z0-9]+)\.([A-Za-z0-9]+)\.(HN[ENZ])\.sac$")


def _olayin_istasyonlarini_grupla(z: zipfile.ZipFile) -> dict[str, dict[str, str]]:
    """SAC dosya adlarini istasyon koduna gore gruplar: {istasyon: {kanal: dosya_adi}}."""
    gruplar: dict[str, dict[str, str]] = {}
    for isim in z.namelist():
        eslesme = DOSYA_DESENI.match(isim)
        if not eslesme:
            continue
        _, _ag, istasyon, kanal = eslesme.groups()
        gruplar.setdefault(istasyon, {})[kanal] = isim
    return gruplar


def _sac_oku(z: zipfile.ZipFile, dosya_adi: str) -> np.ndarray:
    with z.open(dosya_adi) as f:
        st = read(io.BytesIO(f.read()), format="SAC")
    return st[0]


def main() -> None:
    zip_dosyalari = sorted(CSN_DIZINI.glob("*.zip"))
    print(f"Islenecek olay sayisi: {len(zip_dosyalari)}")

    dalgalar, eq_id_listesi, istasyon_listesi, tepe_genlik_listesi = [], [], [], []
    ornekleme_hizi_listesi = []

    for zip_yolu in zip_dosyalari:
        eq_id = zip_yolu.stem
        with zipfile.ZipFile(zip_yolu) as z:
            gruplar = _olayin_istasyonlarini_grupla(z)
            tam_istasyonlar = {k: v for k, v in gruplar.items() if set(v) == {"HNE", "HNN", "HNZ"}}
            if not tam_istasyonlar:
                print(f"  {eq_id}: 3 bileseni TAM olan istasyon yok, atlaniyor")
                continue

            # Her istasyonun tepe genligini (3 kanalin maksimumu) hesapla, en gucluleri sec.
            tepe_genlikler = {}
            okunan_izler = {}
            for istasyon, kanallar in tam_istasyonlar.items():
                try:
                    izler = {k: _sac_oku(z, v) for k, v in kanallar.items()}
                except Exception as hata:
                    print(f"  {eq_id}/{istasyon}: okuma hatasi ({hata}), atlaniyor")
                    continue
                # Farkli kanallarin ornek sayisi FARKLI olabilir (nadir de olsa) - hizalamak
                # icin EN KISA olana kirp, boylece stack() hata vermez.
                min_uzunluk = min(len(iz.data) for iz in izler.values())
                if min_uzunluk < 100:
                    continue
                okunan_izler[istasyon] = (izler, min_uzunluk)
                tepe_genlikler[istasyon] = max(
                    np.abs(iz.data[:min_uzunluk]).max() for iz in izler.values()
                )

            if not tepe_genlikler:
                print(f"  {eq_id}: okunabilir istasyon yok, atlaniyor")
                continue

            en_gucluler = sorted(tepe_genlikler, key=tepe_genlikler.get, reverse=True)
            en_gucluler = en_gucluler[:ISTASYON_BASINA_HEDEF]

            for istasyon in en_gucluler:
                izler, min_uzunluk = okunan_izler[istasyon]
                dalga = np.stack(
                    [izler["HNE"].data[:min_uzunluk],
                     izler["HNN"].data[:min_uzunluk],
                     izler["HNZ"].data[:min_uzunluk]],
                    axis=-1,
                ).astype(np.float32)
                dalgalar.append(dalga)
                eq_id_listesi.append(eq_id)
                istasyon_listesi.append(istasyon)
                tepe_genlik_listesi.append(float(tepe_genlikler[istasyon]))
                ornekleme_hizi_listesi.append(float(izler["HNE"].stats.sampling_rate))

            print(f"  {eq_id}: {len(tam_istasyonlar)} istasyon bulundu, en guclu {len(en_gucluler)} tanesi secildi")

    print(f"\nToplam secilen kayit: {len(dalgalar)}")
    # Dalga formlarinin uzunlugu istasyondan istasyona FARKLI olabilir (bazi olaylarda
    # kayit suresi degisebiliyor) - tek bir (N, T, 3) matrise SIGDIRAMAYIZ, bu yuzden
    # numpy'in object-array ozelligiyle DEGISKEN uzunluklu bir dizi olarak saklıyoruz.
    dalgalar_obj = np.empty(len(dalgalar), dtype=object)
    for i, d in enumerate(dalgalar):
        dalgalar_obj[i] = d

    np.savez_compressed(
        CIKTI_YOLU,
        dalgalar=dalgalar_obj,
        eq_id=np.array(eq_id_listesi),
        istasyon=np.array(istasyon_listesi),
        tepe_genlik=np.array(tepe_genlik_listesi),
        ornekleme_hizi=np.array(ornekleme_hizi_listesi),
    )
    print(f"Yazildi: {CIKTI_YOLU}")


if __name__ == "__main__":
    main()
