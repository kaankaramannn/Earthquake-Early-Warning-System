"""Asama 7.5 - Model egitimi: 07_ozellik_cikar.py'nin urettigi 4 ozellikle (sta_lta_orani,
log_enerji, sifir_gecis_orani, bant_enerji_orani) bir RandomForestClassifier egitir.

KRITIK tasarim karari - egitim/test ayrimi DALGA BAZLI: aynı dalga formunun pencereleri
(ornegin bir depremin 30 farkli 1sn'lik penceresi) YUKSEK oranda birbirine benzer -
bunlarin bir kismi train'de bir kismi test'te olursa, model "bu dalga formunu ezberledi"
diye YANLIS bir basari gorunumu verir (veri sizintisi). Bunun yerine dalga_no'ya gore
GRUP bazli ayrim yapiyoruz: bir dalganin TUM pencereleri ayni tarafta (train VEYA test).

Sinif dengesizligi (~4:1, pozitif:negatif) icin veri COGALTMA/AZALTMA yerine
class_weight='balanced' kullaniliyor - Random Forest'in kendi agirlik mekanizmasi.

DURUST SINIR (rapor edilecek): "elde rastgele hareket" (masaya vurma, dusurme gibi
ani-ama-deprem-olmayan sarsintilar) icin GERCEK bir negatif veri kaynagimiz YOK (plan
notu) - şu an sadece "durgun" ve "yurume/kosma" negatifleri var. Bu, modelin ani darbe
senaryosundaki gercek performansi HAKKINDA HICBIR SEY SOYLEMEZ - ayri bir once test/
veri toplama gerektirir.

Calistirma: proje kokunden (deprem/) `python ml/scripts/08_model_egit.py`
"""
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
import joblib

OZELLIK_SUTUNLARI = ["sta_lta_orani", "log_enerji", "sifir_gecis_orani", "bant_enerji_orani"]
TEST_ORANI = 0.2
RASTGELE_TOHUM = 42


def _dalga_bazli_ayir(df: pd.DataFrame, test_orani: float, tohum: int) -> tuple[np.ndarray, np.ndarray]:
    """Her (kaynak, dalga_no) ciftini TEK bir grup sayar (farkli kaynaklarda ayni
    dalga_no numarasi tekrar edebilir - bkz. 07_ozellik_cikar.py) ve gruplari, HER
    etiket icin ORANTILI olacak sekilde train/test'e boler (stratified group split)."""
    rng = np.random.RandomState(tohum)
    df = df.copy()
    df["grup"] = df["kaynak"] + "_" + df["dalga_no"].astype(str)

    egitim_indeksleri, test_indeksleri = [], []
    for etiket in df["etiket"].unique():
        alt_df = df[df["etiket"] == etiket]
        gruplar = alt_df["grup"].unique()
        rng.shuffle(gruplar)
        kesme = max(1, int(len(gruplar) * (1 - test_orani)))
        egitim_gruplari, test_gruplari = set(gruplar[:kesme]), set(gruplar[kesme:])
        egitim_indeksleri.extend(alt_df[alt_df["grup"].isin(egitim_gruplari)].index)
        test_indeksleri.extend(alt_df[alt_df["grup"].isin(test_gruplari)].index)

    return np.array(egitim_indeksleri), np.array(test_indeksleri)


def main() -> None:
    df = pd.read_csv("ml/data/ozellikler.csv")
    print(f"Toplam pencere: {len(df)}")

    egitim_idx, test_idx = _dalga_bazli_ayir(df, TEST_ORANI, RASTGELE_TOHUM)
    egitim_df, test_df = df.loc[egitim_idx], df.loc[test_idx]
    print(f"Egitim: {len(egitim_df)} pencere, Test: {len(test_df)} pencere")
    print(f"  (dalga bazli ayrim - AYNI dalganin pencereleri HER IKI tarafta OLAMAZ)")

    X_egitim, y_egitim = egitim_df[OZELLIK_SUTUNLARI], egitim_df["etiket"]
    X_test, y_test = test_df[OZELLIK_SUTUNLARI], test_df["etiket"]

    model = RandomForestClassifier(
        n_estimators=100,
        max_depth=8,
        class_weight="balanced",
        random_state=RASTGELE_TOHUM,
        n_jobs=-1,
    )
    model.fit(X_egitim, y_egitim)

    tahminler = model.predict(X_test)
    print("\n=== Genel degerlendirme (test kumesi) ===")
    print(classification_report(y_test, tahminler, target_names=["negatif (0)", "pozitif (1)"]))
    print("Karisiklik matrisi (satir=gercek, sutun=tahmin):")
    print(confusion_matrix(y_test, tahminler))

    print("\n=== Ozellik onemleri ===")
    for isim, onem in sorted(zip(OZELLIK_SUTUNLARI, model.feature_importances_), key=lambda x: -x[1]):
        print(f"  {isim}: {onem:.3f}")

    # En kritik pratik soru: "yurume/kosma" gibi GUCLU ama deprem-olmayan bir hareket
    # ne kadar yanlis-pozitif uretiyor? (masaya vurma/dusurme icin veri YOK, bu bosluk
    # rapor ediliyor, olculmuyor)
    print("\n=== Negatif kaynaklara gore yanlis-pozitif orani (test kumesi) ===")
    test_df = test_df.copy()
    test_df["tahmin"] = tahminler
    for kaynak in test_df[test_df["etiket"] == 0]["kaynak"].unique():
        alt = test_df[(test_df["etiket"] == 0) & (test_df["kaynak"] == kaynak)]
        yanlis_pozitif_orani = (alt["tahmin"] == 1).mean()
        print(f"  {kaynak}: {len(alt)} pencere, yanlis-pozitif orani = {yanlis_pozitif_orani:.1%}")

    joblib.dump(model, "ml/data/model.joblib")
    print("\nYazildi: ml/data/model.joblib")


if __name__ == "__main__":
    main()
