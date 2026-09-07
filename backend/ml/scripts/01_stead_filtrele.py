"""Asama 7.2 - STEAD chunk2.csv'den prototip icin kullanilabilir bir alt-kume secer.

Neden filtreleme gerekli: chunk2'deki depremlerin buyuk cogunlugu COK KUCUK buyuklukte
(ortalama M1.3) - bunlar bir telefonun ASLA hissedemeyecegi kadar hafif. Amac, telefon
MEMS ivmeolceriyle "hissedilebilir" olmasi muhtemel (buyuk + yakin) depremleri secmek,
ustune de kalite (SNR) filtresi eklemek.

Cikti: ml/data/stead_secilen.csv - sadece secilen satirlarin metadata'si (kucuk dosya,
bir sonraki adimda (02_stead_dalgaformu_cikar.py) bu trace_name'lere gore 15 GB'lik
HDF5'ten SADECE ilgili dalga formlari okunacak, tumu belleğe/diske alinmayacak).

Calistirma: proje kokunden (deprem/) `python ml/scripts/01_stead_filtrele.py`
"""
import re

import numpy as np
import pandas as pd

CSV_YOLU = "ml/raw_data/chunk2_extracted/chunk2.csv"
CIKTI_YOLU = "ml/data/stead_secilen.csv"

# Filtre esikleri (prototip icin baslangic degerleri):
MIN_BUYUKLUK = 3.0
MAKS_MESAFE_KM = 100.0
MIN_ORTALAMA_SNR_DB = 20.0  # STEAD literaturunde yaygin kullanilan bir kalite esigi

HEDEF_ORNEK_SAYISI = 2000
RASTGELE_TOHUM = 42  # tekrarlanabilirlik icin sabit


def _snr_ortalamasini_hesapla(snr_metni: str) -> float:
    """'[56.79999924 55.40000153 47.40000153]' -> 53.2 (3 kanalin ortalamasi).
    STEAD'in CSV'si bu alani numpy array'in string temsili olarak yaziyor (gercek
    liste/JSON degil) - regex ile sayilari cikarip kendimiz ortaliyoruz."""
    sayilar = re.findall(r"[-\d.]+", snr_metni)
    if not sayilar:
        return float("nan")
    return float(np.mean([float(s) for s in sayilar]))


def main() -> None:
    print(f"CSV okunuyor: {CSV_YOLU}")
    df = pd.read_csv(CSV_YOLU, low_memory=False)
    print(f"  toplam satir: {len(df)}")

    print("SNR ortalamasi hesaplaniyor (her satir icin 3 kanalin ortalamasi)...")
    df["snr_ortalama"] = df["snr_db"].apply(_snr_ortalamasini_hesapla)

    aday = df[
        (df["source_magnitude"] >= MIN_BUYUKLUK)
        & (df["source_distance_km"] <= MAKS_MESAFE_KM)
        & (df["snr_ortalama"] >= MIN_ORTALAMA_SNR_DB)
    ].copy()
    print(
        f"Filtre sonrasi aday sayisi (M>={MIN_BUYUKLUK}, mesafe<={MAKS_MESAFE_KM}km, "
        f"SNR>={MIN_ORTALAMA_SNR_DB}dB): {len(aday)}"
    )

    if len(aday) <= HEDEF_ORNEK_SAYISI:
        secilen = aday
        print(f"Aday sayisi hedeften (<={HEDEF_ORNEK_SAYISI}) az/esit, TUMU kullaniliyor.")
    else:
        # Buyukluk dilimlerine gore DENGELI ornekleme: sadece en yuksek buyuklukleri
        # secmek CESITLILIGI azaltirdi (ornegin M3.0-3.2 arasi COK daha kalabalik
        # olabilir, sadece rastgele secim de bu dagilima gomulur). Bunun yerine
        # 0.5'lik buyukluk dilimlerine bolup HER dilimden ORANTILI pay aliyoruz.
        # Dilimi DataFrame'e kolon olarak eklemek yerine ayri bir Series olarak
        # gruplayoruz - boylece "secilen" DataFrame'inde hic yer almiyor, sonradan
        # drop etmeye gerek kalmiyor (pandas surumune gore apply'in grup kolonunu
        # koruyup korumamasiyla ilgili tutarsizliktan bagimsiz, daha saglam).
        dilim = (aday["source_magnitude"] // 0.5) * 0.5
        secilen = aday.groupby(dilim, group_keys=False).apply(
            lambda grup: grup.sample(
                n=max(1, round(len(grup) / len(aday) * HEDEF_ORNEK_SAYISI)),
                random_state=RASTGELE_TOHUM,
            )
        )
        print(f"Dilim-bazli dengeli ornekleme ile {len(secilen)} satir secildi.")

    secilen = secilen.drop(columns=["snr_ortalama"])
    secilen.to_csv(CIKTI_YOLU, index=False)
    print(f"\nYazildi: {CIKTI_YOLU} ({len(secilen)} satir)")
    print("\nBuyukluk dagilimi (secilen):")
    print(secilen["source_magnitude"].describe())
    print("\nMesafe dagilimi (secilen):")
    print(secilen["source_distance_km"].describe())


if __name__ == "__main__":
    main()
