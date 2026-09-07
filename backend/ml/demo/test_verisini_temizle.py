"""canli_demo.ps1'in olusturdugu test tremor_reports satirlarini temizler."""
import sqlite3

con = sqlite3.connect("data/earthquake.db")
silinen = con.execute("DELETE FROM tremor_reports").rowcount
con.commit()
con.close()
print(f"Silindi: {silinen} satir.")
