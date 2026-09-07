from fastapi import APIRouter, HTTPException, Depends
from sqlmodel import Session, select
from math import radians, sin, cos, sqrt, atan2

from src.database import get_session
from src.users.models import User, UserLocation
from src.quakes.models import Earthquake
from src.notify.models import Notification
from src.auth.router import admin_gerekli
from src.notify.push import push_gonder

router = APIRouter(
    prefix="/notifications",
    tags=["Notifications"],
)

# Uzak bilgilendirme bandi: etki alani DISINDA kalip yine de haberdar edilecek kullanicilar.
BILGI_MIN_KM = 150
BILGI_MAX_KM = 550

#iki coğrafi nokta arasındaki mesafeyi km cinsinden hesaplar
def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371
    lat1_rad, lon1_rad = radians(lat1), radians(lon1)
    lat2_rad, lon2_rad = radians(lat2), radians(lon2)
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    a = sin(dlat / 2) ** 2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c

def depreme_uygun_kullanicilari_bul(session: Session, earthquake: Earthquake) -> list[User]:
    statement = select(User).where(
        User.pref_min_magnitude != None,
        User.pref_min_magnitude <= earthquake.magnitude,
    )
    adaylar = session.exec(statement).all()

    eslesen_kullanicilar = []
    for user in adaylar:
        if user.pref_latitude is None or user.pref_radius_km is None:
            continue
        mesafe = haversine_km(user.pref_latitude, user.pref_longitude, earthquake.latitude, earthquake.longitude)
        if mesafe <= user.pref_radius_km:
            eslesen_kullanicilar.append(user)

    return eslesen_kullanicilar

def ek_konum_mesafeleri(session: Session, hedef_lat: float, hedef_lon: float) -> list[tuple[User, UserLocation, float]]:
    """TUM kullanicilarin EK konumlarini (User.pref_* BIRINCIL konumundan bagimsiz,
    ayarlar_ekrani.dart -> 'Ek Konumlar' ile eklenen ev/isyeri gibi noktalar) tarar,
    her biri icin (kullanici, konum, mesafe_km) uclusu dondurur. Esik/yaricap
    kontrolu KASITLI OLARAK burada YAPILMAZ — cagiran, kendi esigine (magnitude
    filtresi olup olmamasi, bant araligi vb.) gore filtreler (bkz. cagri noktalari:
    dev/router.py create_earthquake, uzak_bilgilendirme_olustur,
    detect/router.py'deki 3 bildirim fonksiyonu)."""
    konumlar = session.exec(select(UserLocation)).all()
    sonuc = []
    for konum in konumlar:
        user = session.get(User, konum.user_id)
        if not user:
            continue  # yetim kayit (kullanici silinmis) — olmamali ama savunma
        mesafe = haversine_km(konum.latitude, konum.longitude, hedef_lat, hedef_lon)
        sonuc.append((user, konum, mesafe))
    return sonuc


def uzak_bilgilendirme_olustur(session: Session, deprem: Earthquake) -> int:
    """RESMI (Kandilli) deprem icin, etki alani DISINDA 150-550 km bandindaki kullanicilara
    bilgilendirme uretir (DB + varsa FCM push). Alarm degildir: pref_min_magnitude filtresi
    uygulanmaz; zaten normal uyari alan (mesafe <= pref_radius_km) kullaniciya cift gitmez.
    Crowd tespitleri bunu ASLA tetiklemez — yalnizca resmi veri girisinde cagrilir.
    """
    kullanicilar = session.exec(
        select(User).where(User.pref_latitude != None, User.pref_longitude != None)
    ).all()

    yer = deprem.location_name or "bilinmeyen konum"
    sayac = 0
    for user in kullanicilar:
        mesafe = haversine_km(user.pref_latitude, user.pref_longitude, deprem.latitude, deprem.longitude)
        if not (BILGI_MIN_KM <= mesafe <= BILGI_MAX_KM):
            continue
        if mesafe <= (user.pref_radius_km or 0):
            continue  # etki alaninin icinde -> zaten normal uyari aliyor
        mesaj = (f"BILGI: Yaklasik {mesafe:.0f} km uzaginizda, {yer} bolgesinde "
                 f"M{deprem.magnitude:.1f} buyuklugunde deprem meydana geldi.")
        session.add(Notification(
            earthquake_id=deprem.id,
            user_id=user.id,
            matched_reason=mesaj,
        ))
        sayac += 1
        push_gonder(user.fcm_token, "Deprem Bilgilendirmesi", mesaj)

    # Ek konumlar (Ev/Isyeri) icin AYNI bant mantigi, birincil konumdan bagimsiz.
    for user, konum, mesafe in ek_konum_mesafeleri(session, deprem.latitude, deprem.longitude):
        if not (BILGI_MIN_KM <= mesafe <= BILGI_MAX_KM):
            continue
        if mesafe <= konum.radius_km:
            continue  # bu ek konumun etki alaninda -> normal ek-konum uyarisi zaten gidiyor
        mesaj = (f"EK KONUM ({konum.etiket}) BILGI: Yaklasik {mesafe:.0f} km uzaginizda, {yer} "
                 f"bolgesinde M{deprem.magnitude:.1f} buyuklugunde deprem meydana geldi.")
        session.add(Notification(
            earthquake_id=deprem.id,
            user_id=user.id,
            matched_reason=mesaj,
        ))
        sayac += 1
        push_gonder(user.fcm_token, f"Deprem Bilgilendirmesi ({konum.etiket})", mesaj)

    session.commit()
    return sayac


@router.post("/eslestir/{earthquake_id}", summary="Deprem icin bildirim eslestirmesi yap")
def eslestir(
    *,
    earthquake_id: int,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    earthquake = session.get(Earthquake, earthquake_id)
    if not earthquake:
        raise HTTPException(status_code=404, detail="Deprem bulunamadi")
    eslesenler = depreme_uygun_kullanicilari_bul(session,earthquake)
    bildirimler = []
    for user in eslesenler:
        bildirim = Notification(
        earthquake_id=earthquake.id,
        user_id=user.id,
        matched_reason=f"büyüklük {earthquake.magnitude} >= {user.pref_min_magnitude}, mesafe eşik içinde",
        )
        session.add(bildirim)
        bildirimler.append(bildirim)

    session.commit()
    return {"eslesen_kullanici_sayisi": len(bildirimler)}
