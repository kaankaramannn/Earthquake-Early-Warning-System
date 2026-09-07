"""Asama 7.3 - Fuzyon: STEAD+CSN+AFAD'daki gercek deprem dalga formlarini, UCI HAR'daki
GERCEK telefon ivmeolcer gurultusunun (durgun/masadaki telefon) uzerine bindirir.

Neden boyle: elimizde henuz kendi telefonumuzla topladigimiz gercek gurultu verisi YOK
(bkz. plan notu) - UCI HAR, gercek Samsung Galaxy S II telefonlarindan toplanmis, halka
acik bir alternatif. Ayni mantik MyShake'in kendi ANN'ini egitirken izledigi yontem:
gercek deprem dalga formunu, gercek (ama farkli kaynaktan) sensor gurultusunun uzerine
ekleyerek "telefon durgunken bu deprem olsaydi ne gorurdu" sentezi uretmek.

Birim/olcek notu (GUNCELLEME - ilk versiyondan sonra DUZELTILDI): baslangicta deprem
dalga formlari MUTLAK bir m/s^2 hedef araligina (0.05-3.0) olcekleniyordu. Bu, UCI HAR'in
"durgun" (SITTING/STANDING/LAYING) gurultusunun GERCEK genligiyle (medyan ~1.0 m/s^2,
bazi izlerde 7+ m/s^2 - cunku telefon BEL/CEPTE, gercekten hareketsiz bir masa uzerinde
degil) ciddi CAKISIYORDU - model %24 yanlis-pozitif verdi (bkz. 08_model_egit.py ilk
calistirma sonucu). Duzeltme: deprem artik MUTLAK bir degere degil, EKLENECEGI gurultu
parcasinin KENDI RMS seviyesinin bir KATINA (3-20x arasi rastgele - zayif P-dalgasindan
guclu sarsintiya) olcekleniyor. Bu hem fiziksel olarak daha dogru (bir sismik sinyal
"ortam gurultusune gore" anlamlidir, mutlak degil - STA/LTA'nin TEMEL mantigi budur)
hem de her gurultu parcasinin kendi seviyesine gore SISTEMATIK bir cakisma riskini ortadan
kaldirir.

UCI HAR penceresi notu: her pencere 128 ornek (2.56 sn @ 50Hz), ardisik pencereler %50
ORTUSUYOR. Ayni (subject, activity) bloğundaki ardisik pencerelerin ilk YARISINI (64 ornek)
sirayla birlestirerek surekli bir gurultu parcasi elde ediyoruz (ortusme nedeniyle tam
kayipsiz degil ama gurultu KARAKTERI icin yeterli).

Cikti: ml/data/egitim_verisi.npz - hem POZITIF (fuzyonlanmis deprem+gurultu, label=1)
hem NEGATIF (ham gurultu - durgun VE yurume/kosma, label=0) ornekleri, HEPSI 50Hz'e
esitlenmis, ayni (T,3) formatinda.

Calistirma: proje kokunden (deprem/) `python ml/scripts/06_fuzyon.py`
"""
import random

import numpy as np
from scipy.signal import resample_poly

HEDEF_HZ = 50
RMS_ORAN_ARALIGI = (3.0, 20.0)  # depremin RMS'i, eklendigi gurultunun RMS'inin KATI olarak
RASTGELE_TOHUM = 42

UCI_HAR_KOK = "ml/raw_data/uci_har/UCI HAR Dataset/train"
G_TO_MS2 = 9.80665

# UCI HAR aktivite kodlari (activity_labels.txt'den)
DURGUN_KODLARI = {4, 5, 6}  # SITTING, STANDING, LAYING -> "masada durgun" karsiligi
HAREKETLI_KODLARI = {1, 2, 3}  # WALKING, WALKING_UPSTAIRS, WALKING_DOWNSTAIRS


def _pozitif_ornekleri_yukle() -> list[dict]:
    """STEAD/CSN/AFAD'dan tum dalga formlarini, kaynak etiketiyle birlikte tek listede toplar."""
    ornekler = []

    stead = np.load("ml/data/stead_dalgaformlari.npz", allow_pickle=True)
    for dalga in stead["dalgalar"]:
        ornekler.append({"dalga": dalga, "hz": 100.0, "kaynak": "stead"})

    csn = np.load("ml/data/csn_dalgaformlari.npz", allow_pickle=True)
    for dalga, hz in zip(csn["dalgalar"], csn["ornekleme_hizi"]):
        ornekler.append({"dalga": dalga, "hz": float(hz), "kaynak": "csn"})

    afad = np.load("ml/data/afad_dalgaformlari.npz", allow_pickle=True)
    for dalga, hz in zip(afad["dalgalar"], afad["ornekleme_hizi"]):
        ornekler.append({"dalga": dalga, "hz": float(hz), "kaynak": "afad"})

    print(f"Pozitif havuz: {len(ornekler)} dalga formu (STEAD+CSN+AFAD)")
    return ornekler


def _hz_esitle(dalga: np.ndarray, kaynak_hz: float, hedef_hz: float = HEDEF_HZ) -> np.ndarray:
    """Rasyonel yeniden orneklem (polyphase) - kaynak_hz/hedef_hz tam sayi olmasa da calisir."""
    if abs(kaynak_hz - hedef_hz) < 0.01:
        return dalga
    # resample_poly tam sayi up/down orani ister - kucuk bir payda ile yaklastir.
    from fractions import Fraction
    oran = Fraction(hedef_hz / kaynak_hz).limit_denominator(1000)
    return resample_poly(dalga, oran.numerator, oran.denominator, axis=0)


def _gurultu_rms(gurultu: np.ndarray) -> float:
    """3 eksenin net (sqrt(x^2+y^2+z^2)) buyuklugunun RMS'i - gurultunun 'tipik seviyesi'."""
    net = np.sqrt((gurultu ** 2).sum(axis=1))
    return float(np.sqrt(np.mean(net ** 2)))


def _pozitifi_gurultuye_gore_olcekle(dalga: np.ndarray, gurultu_rms: float, rng: random.Random) -> np.ndarray:
    """Depremi MUTLAK bir m/s^2 degerine degil, eklenecegi gurultunun KENDI RMS seviyesinin
    rastgele bir katina (RMS_ORAN_ARALIGI) olcekler - bkz. modul-basi aciklama."""
    tepe = np.abs(dalga).max()
    if tepe < 1e-9 or gurultu_rms < 1e-9:
        return dalga
    hedef_rms_orani = rng.uniform(*RMS_ORAN_ARALIGI)
    dalga_rms = float(np.sqrt(np.mean(np.sqrt((dalga ** 2).sum(axis=1)) ** 2)))
    if dalga_rms < 1e-9:
        return dalga
    olcek = (gurultu_rms * hedef_rms_orani) / dalga_rms
    return dalga * olcek


def _uci_har_gurultu_parcalarini_olustur(aktivite_kodlari: set[int]) -> list[np.ndarray]:
    """Ayni (subject, activity) bloğundaki ardisik pencereleri birlestirip SUREKLI, GERCEK
    telefon gurultusu parcalari uretir - hepsi zaten 50Hz (UCI HAR'in kendi hizi)."""
    x = np.loadtxt(f"{UCI_HAR_KOK}/Inertial Signals/total_acc_x_train.txt")
    y = np.loadtxt(f"{UCI_HAR_KOK}/Inertial Signals/total_acc_y_train.txt")
    z = np.loadtxt(f"{UCI_HAR_KOK}/Inertial Signals/total_acc_z_train.txt")
    subject = np.loadtxt(f"{UCI_HAR_KOK}/subject_train.txt", dtype=int)
    aktivite = np.loadtxt(f"{UCI_HAR_KOK}/y_train.txt", dtype=int)

    # g -> m/s^2
    x, y, z = x * G_TO_MS2, y * G_TO_MS2, z * G_TO_MS2

    # KRITIK: UCI HAR'in 'total_acc'i YERCEKIMINI de icerir (README: "total acceleration" =
    # govde + yercekimi) - bu ~9.8 m/s^2'lik SABIT bilesen, ustune bindirdigimiz depremin
    # (0.05-3.0 m/s^2) etkisini GOLGELER (ilk calistirmada tepe genlikler pozitif/negatif
    # orneklerde AYNI cikinca fark edildi - bkz. dogrulama). Uretim kodumuzdaki
    # (sarsinti_servisi.dart) yuksek-geciren filtrenin yaptigi gibi, HER PENCERENIN KENDI
    # ortalamasini (yavas degisen yercekimi+egim bileseni) cikararak sadece "sinyal" kismini
    # birakiyoruz - fuzyon ve negatif sinif ICIN AYNI islem uygulanmali (tutarlilik).
    for pencere_dizisi in (x, y, z):
        pencere_dizisi -= pencere_dizisi.mean(axis=1, keepdims=True)

    parcalar = []
    i = 0
    n = len(subject)
    while i < n:
        j = i
        while j + 1 < n and subject[j + 1] == subject[i] and aktivite[j + 1] == aktivite[i]:
            j += 1
        if aktivite[i] in aktivite_kodlari:
            # [i, j] araligindaki ardisik pencerelerin ilk YARISINI (64 ornek) sirayla al.
            yarim = x.shape[1] // 2
            parca_x = np.concatenate([x[k, :yarim] for k in range(i, j + 1)])
            parca_y = np.concatenate([y[k, :yarim] for k in range(i, j + 1)])
            parca_z = np.concatenate([z[k, :yarim] for k in range(i, j + 1)])
            parcalar.append(np.stack([parca_x, parca_y, parca_z], axis=-1).astype(np.float32))
        i = j + 1

    return parcalar


def _gurultu_parcasi_uzunlugu_esitle(parca: np.ndarray, hedef_uzunluk: int, rng: random.Random) -> np.ndarray:
    """Gurultu parcasi hedeften KISAYSA rastgele bir baslangictan dongusel tekrarlanir
    (hafif periyotluluk kabul edilebilir bir basitlestirme - prototip kapsaminda);
    UZUNSA rastgele bir kesit alinir."""
    mevcut = parca.shape[0]
    if mevcut >= hedef_uzunluk:
        baslangic = rng.randint(0, mevcut - hedef_uzunluk)
        return parca[baslangic:baslangic + hedef_uzunluk]
    tekrar = int(np.ceil(hedef_uzunluk / mevcut))
    genisletilmis = np.tile(parca, (tekrar, 1))
    baslangic = rng.randint(0, genisletilmis.shape[0] - hedef_uzunluk)
    return genisletilmis[baslangic:baslangic + hedef_uzunluk]


def main() -> None:
    rng = random.Random(RASTGELE_TOHUM)

    pozitif_havuzu = _pozitif_ornekleri_yukle()
    print("UCI HAR durgun (SITTING/STANDING/LAYING) gurultu parcalari olusturuluyor...")
    durgun_parcalari = _uci_har_gurultu_parcalarini_olustur(DURGUN_KODLARI)
    print(f"  {len(durgun_parcalari)} surekli parca (ortalama {np.mean([len(p) for p in durgun_parcalari]):.0f} ornek)")
    print("UCI HAR hareketli (WALKING variants) gurultu parcalari olusturuluyor...")
    hareketli_parcalari = _uci_har_gurultu_parcalarini_olustur(HAREKETLI_KODLARI)
    print(f"  {len(hareketli_parcalari)} surekli parca")

    print("\nFuzyon: pozitif orneklere gurultu ekleniyor...")
    dalgalar, etiketler, kaynaklar = [], [], []
    for i, ornek in enumerate(pozitif_havuzu):
        dalga_50hz = _hz_esitle(ornek["dalga"], ornek["hz"])

        # ONCE gurultuyu sec (depremin uzunluguna gore kirp/tekrarla), SONRA depremi bu
        # gurultunun KENDI RMS seviyesine gore olcekle - sira onemli, RMS_ORAN_ARALIGI'nin
        # anlamli olmasi icin deprem, ekleneceği GERCEK gurultuyu bilerek olceklenmeli.
        gurultu_parcasi = rng.choice(durgun_parcalari)
        gurultu = _gurultu_parcasi_uzunlugu_esitle(gurultu_parcasi, dalga_50hz.shape[0], rng)
        gurultu_rms = _gurultu_rms(gurultu)

        dalga_olcekli = _pozitifi_gurultuye_gore_olcekle(dalga_50hz, gurultu_rms, rng)
        fuzyonlanmis = (dalga_olcekli + gurultu).astype(np.float32)
        dalgalar.append(fuzyonlanmis)
        etiketler.append(1)
        kaynaklar.append(ornek["kaynak"])

        if (i + 1) % 500 == 0:
            print(f"  {i + 1}/{len(pozitif_havuzu)} fuzyonlandi...")

    print(f"Toplam pozitif (fuzyonlanmis) ornek: {len(dalgalar)}")

    print("\nNegatif ornekler ekleniyor (ham gurultu, fuzyonsuz)...")
    for etiket_adi, havuz in [("durgun", durgun_parcalari), ("hareketli", hareketli_parcalari)]:
        for parca in havuz:
            dalgalar.append(parca.astype(np.float32))
            etiketler.append(0)
            kaynaklar.append(f"uci_har_{etiket_adi}")
    print(f"Toplam negatif ornek: {len(durgun_parcalari) + len(hareketli_parcalari)}")

    dalgalar_obj = np.empty(len(dalgalar), dtype=object)
    for i, d in enumerate(dalgalar):
        dalgalar_obj[i] = d

    np.savez_compressed(
        "ml/data/egitim_verisi.npz",
        dalgalar=dalgalar_obj,
        etiket=np.array(etiketler, dtype=np.int8),
        kaynak=np.array(kaynaklar),
        ornekleme_hizi=HEDEF_HZ,
    )
    print(f"\nYazildi: ml/data/egitim_verisi.npz (toplam {len(dalgalar)} ornek)")
    print(f"  pozitif (deprem+gurultu): {sum(1 for e in etiketler if e == 1)}")
    print(f"  negatif (sadece gurultu): {sum(1 for e in etiketler if e == 0)}")


if __name__ == "__main__":
    main()
