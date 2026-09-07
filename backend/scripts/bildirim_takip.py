import argparse
import sys
import time

import requests

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

VARSAYILAN_URL = "http://127.0.0.1:8000"


def token_al(base_url: str, username: str, password: str) -> str:
    """Login olup JWT access token döndürür."""
    cevap = requests.post(
        f"{base_url}/auth/login/",
        data={"username": username, "password": password},
    )
    if cevap.status_code != 200:
        print(f"[HATA] Giriş başarisiz ({cevap.status_code}): {cevap.text}")
        sys.exit(1)
    return cevap.json()["access_token"]


def bildirimleri_getir(base_url: str, token: str) -> list[dict]:
    """Kullanicinin kendi bildirimlerini getirir."""
    cevap = requests.get(
        f"{base_url}/user/notifications/",
        headers={"Authorization": f"Bearer {token}"},
    )
    cevap.raise_for_status()
    return cevap.json()


def main() -> None:
    parser = argparse.ArgumentParser(description="Deprem bildirim polling test araci")
    parser.add_argument("--url", default=VARSAYILAN_URL, help="Backend adresi")
    parser.add_argument("--username", default="Toprak", help="Takip edilecek kullanici adi")
    parser.add_argument("--password", default="Toprak123", help="Kullanici parolasi")
    parser.add_argument("--interval", type=float, default=5.0, help="Sorgu araliği (saniye)")
    args = parser.parse_args()

    print(f"-> {args.url} adresine '{args.username}' olarak giriş yapiliyor...")
    token = token_al(args.url, args.username, args.password)
    print("-> Giriş başarili. Bildirimler izleniyor (durdurmak için Ctrl+C).\n")
    # Yeni bildirimleri 'created_at' (olusturma zamani) ile ayirt ediyoruz, 'id' ile degil.
    # Cunku simulasyon tabloyu temizleyip yeniden uretince SQLite id'leri sifirlar (1,2,3..);
    # id ile dedup edersek tekrar gelen id'leri 'eski' sanardik. created_at ise her bildirimde benzersiz.
    gorulen_zamanlar: set[str] = set()
    try:
        ilk = bildirimleri_getir(args.url, token)
        gorulen_zamanlar = {b["created_at"] for b in ilk}
        print(f"   (Başlangiçta {len(gorulen_zamanlar)} mevcut bildirim var, bunlar atlaniyor.)")
    except requests.RequestException as e:
        print(f"[UYARI] İlk sorgu başarisiz: {e}")

    try:
        while True:
            try:
                bildirimler = bildirimleri_getir(args.url, token)
            except requests.RequestException as e:
                print(f"[UYARI] Sorgu başarisiz, tekrar denenecek: {e}")
                time.sleep(args.interval)
                continue

            yeniler = [b for b in bildirimler if b["created_at"] not in gorulen_zamanlar]
            for b in yeniler:
                gorulen_zamanlar.add(b["created_at"])
                if b.get("earthquake_id") is not None:
                    kaynak = f"deprem #{b['earthquake_id']}"
                elif b.get("detection_event_id") is not None:
                    kaynak = f"tespit #{b['detection_event_id']}"
                else:
                    kaynak = "kaynak yok"
                print(
                    f">>> YENİ BİLDİRİM  (id={b['id']}) | {kaynak} | "
                    f"{b['matched_reason']} | {b['created_at']}"
                )

            if not yeniler:
                print(f"   ... yeni bildirim yok ({time.strftime('%H:%M:%S')})")

            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n-> İzleme durduruldu.")


if __name__ == "__main__":
    main()
