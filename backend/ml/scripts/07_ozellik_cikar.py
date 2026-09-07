"""Asama 7.4 - Ozellik cikarimi: 06_fuzyon.py'nin urettigi 2335 dalga formunu (her biri
degisken uzunlukta, 50Hz, (T,3)) 1 saniyelik %50 ortusmeli pencerelere bolup, HER PENCERE
icin 4 ozellik hesaplar. Ham dalga formu uzerinde egitim yapmak (CNN gibi) az veriyle
calismaz - bu yuzden Aşama 3'teki (sarsinti_servisi.dart) canli algoritmanin mantigina
YAKIN, ELLE cikarilmis ozellikler kullaniyoruz (Random Forest icin uygun boyut/olcek).

Onemli tasarim karari: bir dalga formunun TUM pencereleri, o dalga formunun ETIKETINI
(0=gurultu, 1=deprem+gurultu fuzyonu) miras alir - standart pencere-bazli siniflandirma
yaklasimi (dalga formu ic ice HOMOJEN kabul edilir).

Ozellikler (her pencere icin):
  1. sta_lta_orani: pencerenin enerjisi / dalga formunun TUMUNUN ortalama enerjisi
     (canli STA/LTA'nin offline karsiligi - "bu an, ortalamaya gore ne kadar supheli")
  2. log_enerji: pencere icindeki net ivme enerjisinin (ortalama kare) logaritmasi
  3. sifir_gecis_orani: dusey (Z) eksende isaret degisim sayisi / pencere uzunlugu
     (deprem GENIS BANTLI/duzensizdir, yurume gibi RITMIK hareketlerden bunu ayirir)
  4. bant_enerji_orani: 1-10 Hz bandindaki FFT enerjisinin TOPLAM enerjiye orani
     (Aşama 3'un "sismik acidan anlamli frekans bandi" secimiyle AYNI mantik)

Etiketleme DUZELTMESI (ilk calistirmada bulundu): bir depremin TUM izini (60 sn, sakin
oncesi/sonrasi dahil) "pozitif" saymak sinyali zayiflatiyordu (STA/LTA orani pozitif/
negatifte NEREDEYSE AYNI cikiyordu - bkz. dogrulama). Duzeltme: HER pozitif dalga
formunda, o izin KENDI pencere-enerjisi medyaninin 2 KATINI gecen pencereler (gercek
sarsintinin oldugu kisim) pozitif sayilir; digerleri (sakin oncesi/sonrasi) veri setinden
CIKARILIR - ne pozitif ne negatif (belirsiz/karisik sinyal, egitime KATILMAZ). Negatif
(gurultu) izlerin TUMU zaten baştan sona gurultu oldugu icin bu filtre onlara UYGULANMAZ.

Cikti: ml/data/ozellikler.csv - her satir bir PENCERE (ornek), sutunlar 4 ozellik +
etiket + kaynak (hangi dalga formundan geldigi, egitim/test ayrimini SIZDIRMADAN
yapmak icin - bkz. 08_model_egit.py).

Calistirma: proje kokunden (deprem/) `python ml/scripts/07_ozellik_cikar.py`
"""
import numpy as np
import pandas as pd

HZ = 50
PENCERE_SN = 1.0
PENCERE_ORNEK = int(PENCERE_SN * HZ)  # 50 ornek
ADIM_ORNEK = PENCERE_ORNEK // 2  # %50 ortusme -> 25 ornek
BANT_ALT_HZ, BANT_UST_HZ = 1.0, 10.0
POZITIF_ESIK_KATSAYISI = 2.0  # pencere enerjisi, izin KENDI medyaninin bu katini gecmeli


def _pencerelere_ayir(uzunluk: int) -> list[tuple[int, int]]:
    """Bir dalga formunun uzunluguna gore (baslangic, bitis) pencere indeks ciftlerini
    dondurur. Cok kisa dalga formlari (< 1 pencere) atlanir."""
    pencereler = []
    baslangic = 0
    while baslangic + PENCERE_ORNEK <= uzunluk:
        pencereler.append((baslangic, baslangic + PENCERE_ORNEK))
        baslangic += ADIM_ORNEK
    return pencereler


def _ozellikleri_hesapla(net: np.ndarray, z_ekseni: np.ndarray, tum_dalga_ortalama_enerji: float) -> dict:
    pencere_enerjisi = float(np.mean(net ** 2))
    sta_lta_orani = pencere_enerjisi / tum_dalga_ortalama_enerji if tum_dalga_ortalama_enerji > 1e-12 else 0.0
    log_enerji = float(np.log10(pencere_enerjisi + 1e-12))

    isaretler = np.sign(z_ekseni - z_ekseni.mean())
    isaret_degisimi = np.sum(np.abs(np.diff(isaretler)) > 0)
    sifir_gecis_orani = float(isaret_degisimi / len(z_ekseni))

    fft_genlik = np.abs(np.fft.rfft(net))
    frekanslar = np.fft.rfftfreq(len(net), d=1.0 / HZ)
    toplam_enerji = float(np.sum(fft_genlik ** 2)) + 1e-12
    bant_maskesi = (frekanslar >= BANT_ALT_HZ) & (frekanslar <= BANT_UST_HZ)
    bant_enerji_orani = float(np.sum(fft_genlik[bant_maskesi] ** 2) / toplam_enerji)

    return {
        "sta_lta_orani": sta_lta_orani,
        "log_enerji": log_enerji,
        "sifir_gecis_orani": sifir_gecis_orani,
        "bant_enerji_orani": bant_enerji_orani,
    }


def main() -> None:
    veri = np.load("ml/data/egitim_verisi.npz", allow_pickle=True)
    dalgalar, etiketler, kaynaklar = veri["dalgalar"], veri["etiket"], veri["kaynak"]
    print(f"Toplam dalga formu: {len(dalgalar)}")

    satirlar = []
    atlanan = 0
    for dalga_no, (dalga, etiket, kaynak) in enumerate(zip(dalgalar, etiketler, kaynaklar)):
        net = np.sqrt((dalga ** 2).sum(axis=1))
        z_ekseni = dalga[:, 2]
        pencereler = _pencerelere_ayir(len(net))
        if not pencereler:
            atlanan += 1
            continue

        tum_dalga_ortalama_enerji = float(np.mean(net ** 2))

        # Pozitif izlerde: SADECE gercek sarsintinin oldugu (yuksek enerjili) pencereleri
        # tut. Esik, o IZE OZGU medyanin katidir (mutlak bir sabit degil) - boylece hem
        # cok guclu hem cok zayif depremler icin GORECELI olarak dogru calisir.
        pencere_enerjileri = [float(np.mean(net[b:s] ** 2)) for b, s in pencereler]
        esik = None
        if etiket == 1:
            esik = np.median(pencere_enerjileri) * POZITIF_ESIK_KATSAYISI

        for pencere_no, ((baslangic, bitis), pencere_enerjisi) in enumerate(zip(pencereler, pencere_enerjileri)):
            if esik is not None and pencere_enerjisi < esik:
                continue  # sakin oncesi/sonrasi - belirsiz, egitime KATILMIYOR
            ozellikler = _ozellikleri_hesapla(net[baslangic:bitis], z_ekseni[baslangic:bitis], tum_dalga_ortalama_enerji)
            ozellikler.update({
                "etiket": int(etiket),
                "kaynak": str(kaynak),
                "dalga_no": dalga_no,  # AYNI dalgadan gelen pencereler train/test'e KARISMASIN
                "pencere_no": pencere_no,
            })
            satirlar.append(ozellikler)

        if (dalga_no + 1) % 500 == 0:
            print(f"  {dalga_no + 1}/{len(dalgalar)} dalga formu islendi...")

    if atlanan:
        print(f"UYARI: {atlanan} dalga formu 1 pencereden kisa oldugu icin atlandi")

    df = pd.DataFrame(satirlar)
    df.to_csv("ml/data/ozellikler.csv", index=False)
    print(f"\nYazildi: ml/data/ozellikler.csv ({len(df)} pencere/satir)")
    print(f"  pozitif pencere: {(df['etiket'] == 1).sum()}")
    print(f"  negatif pencere: {(df['etiket'] == 0).sum()}")
    print("\nOzellik istatistikleri (etikete gore ortalama):")
    print(df.groupby("etiket")[["sta_lta_orani", "log_enerji", "sifir_gecis_orani", "bant_enerji_orani"]].mean())


if __name__ == "__main__":
    main()
