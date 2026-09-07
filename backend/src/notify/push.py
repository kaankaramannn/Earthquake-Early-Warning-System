"""FCM push gönderimi (Faz 4).

Backend, bildirim (Notification) yazarken kullanıcının telefonuna gerçek
Android push'u da gönderir. Kimlik: firebase-service-account.json (GİZLİ dosya,
.gitignore'da). Push, DB kaydının YEDEĞİ değil TAMAMLAYICISIDIR: push başarısız
olsa bile Notification yazılmış olur (uygulama polling ile yine görür).
"""
import firebase_admin
from firebase_admin import credentials, messaging

from src.config import BASE_DIR

_ANAHTAR_DOSYASI = BASE_DIR / "firebase-service-account.json"
_app = None


def _uygulamayi_baslat():
    """firebase_admin'i ilk kullanımda BİR KEZ başlatır (lazy init)."""
    global _app
    if _app is None:
        _app = firebase_admin.initialize_app(
            credentials.Certificate(str(_ANAHTAR_DOSYASI))
        )
    return _app


def push_gonder(
    fcm_token: str | None,
    baslik: str,
    govde: str,
    data: dict[str, str] | None = None,
    sistem_bildirimi_olustur: bool = True,
) -> bool:
    """Tek cihaza push gönderir. Başarı durumunu döndürür; ASLA exception fırlatmaz
    (push ikincil iş — çağıranın akışını bozmamalı).

    `data`: FCM data payload (ör. {"type": "earthquake_alert", "magnitude": "6.1",
    "distance_km": "20"}) — Flutter tarafında PushDepremUyarisi.fromFcmData()
    (lib/notify/bildirim.dart) bu alanlari okuyup tam ekran EarthquakeAlertScreen'i
    tetikliyor. Sadece bildirim cubugu icin title/body yeterliyse data'yi bos birak.
    FCM data payload'i string->string bekler; sayisal degerleri str()'e cevirerek ver.

    `sistem_bildirimi_olustur=False`: `notification` blogu ATLANIR, mesaj SADECE
    data payload'i ile (data-only) gider. Kritik deprem alarmi icin kullanilir —
    mobil taraf (kritik_bildirim_servisi.dart) full-screen-intent bildirimini
    KENDISI olusturuyor; FCM'in otomatik gosterdigi bir `notification` bloğu da
    eklenirse kullanici AYNI alarm icin IKI bildirim gorur (biri sistemin, biri
    bizim). Diger (kritik olmayan) push'lar icin varsayilan True kalmali.
    """
    if not fcm_token:
        return False  # kullanicinin kayitli cihazi yok (mobil girisi yapmamis)
    try:
        _uygulamayi_baslat()
        mesaj = messaging.Message(
            notification=(
                messaging.Notification(title=baslik, body=govde)
                if sistem_bildirimi_olustur else None
            ),
            data=data,
            token=fcm_token,
        )
        messaging.send(mesaj)
        return True
    except Exception as hata:  # gecersiz token, ag hatasi vb. — sessiz gec, logla
        print(f"[PUSH] gonderilemedi: {hata}")
        return False
