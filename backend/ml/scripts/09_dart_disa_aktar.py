"""Asama 7.6 - Mobil entegrasyon: kucuk bir Random Forest'i (15 agac, derinlik 5 - tam
modelin ~%92'sini koruyor, TFLite gerekmeden dogrudan Dart'a yazilabilecek boyutta)
egitip, HER agacin karar mantigini elle if/else Dart koduna cevirir.

Neden TFLite YOK: 100 agacli/derinlik 8 tam model Dart'a cevrilirse binlerce satir
cikar. 15 agac x en fazla 2^5=32 yaprak = yonetilebilir boyutta duz Dart kodu -
plan'in 7.6 hedefi ("Random Forest -> export_text -> basit if/else Dart") tam bu.

Dogrulama: uretilen Dart mantiginin PYTHON tarafinda birebir SIMULASYONU yapilip,
gercek scikit-learn modelinin tahminleriyle SATIR SATIR karsilastirilir - "kodu
Dart'a yazdim, umarim dogrudur" degil, "ayni girdilerle ayni cikti" garantisi.

Calistirma: proje kokunden (deprem/) `python ml/scripts/09_dart_disa_aktar.py`
"""
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report

sys.path.insert(0, "ml/scripts")
from importlib import import_module

mod = import_module("08_model_egit")

OZELLIK_SUTUNLARI = mod.OZELLIK_SUTUNLARI  # ['sta_lta_orani','log_enerji','sifir_gecis_orani','bant_enerji_orani']
MOBIL_N_AGAC = 15
MOBIL_DERINLIK = 5
RASTGELE_TOHUM = 42


def _agac_dart_kodu_uret(agac, agac_no: int) -> str:
    """Bir DecisionTreeClassifier'in ic yapisini (tree_) gezip, esdeger bir Dart
    fonksiyonu ureten REKURSIF fonksiyon. sklearn agac dugumlerini indeks numarasiyla
    (children_left/right, feature, threshold) temsil eder - biz bunlari if/else'e ceviriyoruz."""
    tree = agac.tree_
    satirlar = [f"double _agac{agac_no}(List<double> f) {{"]

    def _dugumu_yaz(dugum_no: int, girinti: str) -> list[str]:
        if tree.children_left[dugum_no] == tree.children_right[dugum_no]:  # yaprak
            # Bu yapraktaki sinif dagilimindan pozitif (1) olasiligini dondur.
            deger = tree.value[dugum_no][0]
            pozitif_olasilik = deger[1] / deger.sum()
            return [f"{girinti}return {pozitif_olasilik:.6f};"]

        ozellik_no = tree.feature[dugum_no]
        esik = tree.threshold[dugum_no]
        ozellik_adi = OZELLIK_SUTUNLARI[ozellik_no]
        satirlar_ic = [f"{girinti}// {ozellik_adi} <= {esik:.6f} ?"]
        satirlar_ic.append(f"{girinti}if (f[{ozellik_no}] <= {esik:.6f}) {{")
        satirlar_ic += _dugumu_yaz(tree.children_left[dugum_no], girinti + "  ")
        satirlar_ic.append(f"{girinti}}} else {{")
        satirlar_ic += _dugumu_yaz(tree.children_right[dugum_no], girinti + "  ")
        satirlar_ic.append(f"{girinti}}}")
        return satirlar_ic

    satirlar += _dugumu_yaz(0, "  ")
    satirlar.append("}")
    return "\n".join(satirlar)


def _dart_dosyasini_uret(orman: RandomForestClassifier) -> str:
    agac_fonksiyonlari = [_agac_dart_kodu_uret(agac, i) for i, agac in enumerate(orman.estimators_)]
    toplama_satirlari = "\n".join(f"  toplam += _agac{i}(f);" for i in range(len(orman.estimators_)))

    baslik = f'''/// ANN ikinci katman onayi (Asama 7.6) - OTOMATIK URETILDI, elle DUZENLEMEYIN.
/// Kaynak: ml/scripts/09_dart_disa_aktar.py -> RandomForestClassifier({MOBIL_N_AGAC} agac,
/// derinlik {MOBIL_DERINLIK}) -> {len(orman.estimators_)} agacin if/else karsiligi.
///
/// Ozellik sirasi (f listesi): {OZELLIK_SUTUNLARI}
/// _sarsintiKontrolEt (Aşama 3) "supheli" dedikten SONRA cagrilacak ikinci onay katmani.
library;

/// {len(orman.estimators_)} agacin pozitif-sinif olasiliklarinin ORTALAMASINI dondurur
/// (0.0-1.0 arasi) - RandomForestClassifier.predict_proba ile AYNI mantik.
double ikinciKatmanOlasilik(List<double> f) {{
  double toplam = 0.0;
{toplama_satirlari}
  return toplam / {len(orman.estimators_)};
}}

/// 0.5 esigiyle ikili karar (RandomForestClassifier.predict ile AYNI esik).
bool ikinciKatmanOnayVer(List<double> f) => ikinciKatmanOlasilik(f) >= 0.5;

'''
    return baslik + "\n\n".join(agac_fonksiyonlari) + "\n"


def _dart_mantigini_python_ile_simule_et(orman: RandomForestClassifier, X: pd.DataFrame) -> np.ndarray:
    """Uretilen Dart kodunun YAPACAGI hesabi (agac-basi pozitif olasilik ortalamasi ->
    0.5 esigi) PYTHON tarafinda tekrar hesaplar - Dart'a gecmeden ONCE mantigin gercek
    sklearn tahminleriyle BIREBIR ayni oldugunu dogrulamak icin."""
    olasiliklar = np.zeros(len(X))
    for agac in orman.estimators_:
        yaprak_indeksleri = agac.apply(X.values)
        deger = agac.tree_.value[yaprak_indeksleri][:, 0, :]
        olasiliklar += deger[:, 1] / deger.sum(axis=1)
    olasiliklar /= len(orman.estimators_)
    return (olasiliklar >= 0.5).astype(int)


def main() -> None:
    df = pd.read_csv("ml/data/ozellikler.csv")
    egitim_idx, test_idx = mod._dalga_bazli_ayir(df, mod.TEST_ORANI, RASTGELE_TOHUM)
    egitim_df, test_df = df.loc[egitim_idx], df.loc[test_idx]
    X_egitim, y_egitim = egitim_df[OZELLIK_SUTUNLARI], egitim_df["etiket"]
    X_test, y_test = test_df[OZELLIK_SUTUNLARI], test_df["etiket"]

    print(f"Mobil model egitiliyor: {MOBIL_N_AGAC} agac, derinlik {MOBIL_DERINLIK}...")
    orman = RandomForestClassifier(
        n_estimators=MOBIL_N_AGAC, max_depth=MOBIL_DERINLIK,
        class_weight="balanced", random_state=RASTGELE_TOHUM, n_jobs=-1,
    )
    orman.fit(X_egitim, y_egitim)

    sklearn_tahmin = orman.predict(X_test)
    print("\n=== Mobil model (sklearn) test performansi ===")
    print(classification_report(y_test, sklearn_tahmin, target_names=["negatif (0)", "pozitif (1)"]))

    print("Dart kodu uretiliyor...")
    dart_kodu = _dart_dosyasini_uret(orman)
    cikti_yolu = "ml/model_dart/ikinci_katman.dart"
    import os
    os.makedirs("ml/model_dart", exist_ok=True)
    with open(cikti_yolu, "w", encoding="utf-8") as f:
        f.write(dart_kodu)
    print(f"Yazildi: {cikti_yolu} ({len(dart_kodu.splitlines())} satir)")

    print("\n=== DOGRULAMA: uretilen mantik, gercek sklearn tahminiyle BIREBIR ayni mi? ===")
    simule_tahmin = _dart_mantigini_python_ile_simule_et(orman, X_test)
    ayni_mi = np.array_equal(sklearn_tahmin, simule_tahmin)
    print(f"  sklearn.predict() == simule edilen Dart mantigi: {ayni_mi}")
    if not ayni_mi:
        farkli_sayisi = (sklearn_tahmin != simule_tahmin).sum()
        print(f"  UYARI: {farkli_sayisi}/{len(sklearn_tahmin)} tahmin FARKLI - bir hata var!")
    else:
        print(f"  OK: {len(sklearn_tahmin)} test ornegi icin TAM eslesme.")


if __name__ == "__main__":
    main()
