"""Asama 7.2 - 01_stead_filtrele.py'de secilen trace_name'lere gore, 15 GB'lik
chunk2.hdf5'ten SADECE ilgili dalga formlarini okuyup kucuk, tasinabilir bir
.npz dosyasina yazar. Boylece 7.3 (fuzyon) ve 7.4 (ozellik cikarimi) adimlari
15 GB'lik dosyaya bir daha hic dokunmadan calisabilir.

Calistirma: proje kokunden (deprem/) `python ml/scripts/02_stead_dalgaformu_cikar.py`
"""
import h5py
import numpy as np
import pandas as pd

METADATA_YOLU = "ml/data/stead_secilen.csv"
HDF5_YOLU = "ml/raw_data/chunk2_extracted/chunk2.hdf5"
CIKTI_YOLU = "ml/data/stead_dalgaformlari.npz"


def main() -> None:
    metadata = pd.read_csv(METADATA_YOLU, low_memory=False)
    print(f"Okunacak ornek sayisi: {len(metadata)}")

    dalga_formlari = []
    basarisiz = []
    with h5py.File(HDF5_YOLU, "r") as f:
        veri_grubu = f["data"]
        for i, trace_name in enumerate(metadata["trace_name"]):
            try:
                dalga_formlari.append(np.array(veri_grubu[trace_name], dtype=np.float32))
            except KeyError:
                basarisiz.append(trace_name)
                continue
            if (i + 1) % 500 == 0:
                print(f"  {i + 1}/{len(metadata)} okundu...")

    if basarisiz:
        print(f"UYARI: {len(basarisiz)} trace_name HDF5'te bulunamadi, atlandi: {basarisiz[:5]}...")
        # basarisiz olanlari metadata'dan da cikar (dalga formu ile metadata satir SAYISI eslesmeli)
        metadata = metadata[~metadata["trace_name"].isin(basarisiz)].reset_index(drop=True)

    dalgalar = np.stack(dalga_formlari, axis=0)  # (N, 6000, 3)
    print(f"\nToplam okunan: {dalgalar.shape[0]} dalga formu, sekil: {dalgalar.shape}")

    np.savez_compressed(
        CIKTI_YOLU,
        dalgalar=dalgalar,
        trace_name=metadata["trace_name"].to_numpy(),
        magnitude=metadata["source_magnitude"].to_numpy(),
        distance_km=metadata["source_distance_km"].to_numpy(),
        p_arrival_sample=metadata["p_arrival_sample"].to_numpy(),
        s_arrival_sample=metadata["s_arrival_sample"].to_numpy(),
    )
    print(f"Yazildi: {CIKTI_YOLU}")


if __name__ == "__main__":
    main()
