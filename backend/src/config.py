"""Proje genelinde kullanilan ortak yollar.

BASE_DIR: `deprem/` proje kokunu gosterir (bu dosya src/config.py oldugu icin
iki ust klasor). database.py, push.py gibi cwd-bagimli yol kullanan dosyalar
artik buradan turetilen mutlak yollari kullanir — hangi dizinden calistirilirsa
calistirilsin (uvicorn, pytest, farkli bir script) ayni dosyalara isaret eder.
"""
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
