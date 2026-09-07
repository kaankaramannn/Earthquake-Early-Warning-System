from fastapi import APIRouter, HTTPException, Depends
from sqlmodel import Session

from src.database import get_session
from src.quakes.models import Earthquake, EarthquakeCreate, EarthquakeCreateResponse
from src.users.models import User
from src.notify.models import Notification
from src.auth.router import admin_gerekli
from src.notify.router import (
    depreme_uygun_kullanicilari_bul,
    uzak_bilgilendirme_olustur,
    ek_konum_mesafeleri,
)
from src.notify.push import push_gonder
from src.detect.router import tespitleri_dogrula

router = APIRouter(
    prefix="/test",
    tags=["Test"],
)

@router.post("/earthquakes/", response_model=EarthquakeCreateResponse, summary="Yeni deprem kaydi ekle")
def create_earthquake(
    *,
    earthquake: EarthquakeCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(admin_gerekli),
):
    db_eq = Earthquake(**earthquake.model_dump(), created_by=current_user.id)
    session.add(db_eq)
    session.commit()
    session.refresh(db_eq)

    eslesenler = depreme_uygun_kullanicilari_bul(session, db_eq)
    bildirimler = []
    for user in eslesenler:
        bildirim = Notification(
            earthquake_id=db_eq.id,
            user_id=user.id,
            matched_reason=f"büyüklük {db_eq.magnitude} >= {user.pref_min_magnitude}, mesafe eşik içinde",
        )
        session.add(bildirim)
        bildirimler.append(bildirim)
        # NOT (duzeltme): bu push daha once hic gonderilmiyordu — sadece DB kaydi
        # olusuyordu, kullanici bildirimi ancak uygulamayi acip listeye bakinca
        # goruyordu. Ek konumlar push aliyorken birincil konumun almamasi tutarsiz
        # olurdu, bu yuzden burada da eklendi.
        push_gonder(user.fcm_token, "Kandilli: Deprem Bildirimi", bildirim.matched_reason)

    # Ek konumlar (Ev/Isyeri) — birincil konumdan BAGIMSIZ, kendi yaricap/esigine gore.
    for user, konum, mesafe in ek_konum_mesafeleri(session, db_eq.latitude, db_eq.longitude):
        if mesafe > konum.radius_km or konum.min_magnitude > db_eq.magnitude:
            continue
        yer = db_eq.location_name or "bilinmeyen konum"
        mesaj = (f"EK KONUM ({konum.etiket}): Kandilli M{db_eq.magnitude:.1f} deprem, "
                 f"{yer}, size {mesafe:.0f} km uzakta")
        session.add(Notification(earthquake_id=db_eq.id, user_id=user.id, matched_reason=mesaj))
        push_gonder(user.fcm_token, f"Deprem ({konum.etiket})", mesaj)

    session.commit()
    session.refresh(db_eq)

    # Otomatik doğrulama: yeni resmi deprem girilince, eşleşen bekleyen tespitler
    # anında 'confirmed' olur + ilgili kullanıcılara "Kandilli doğruladı" bildirimi gider.
    tespitleri_dogrula(session)
    session.refresh(db_eq)  # dogrulama commit'leri db_eq'i expire etti; cevap icin tazele
    # Uzak bilgilendirme: 150-550 km bandindaki kullanicilara "haberiniz olsun" (yalnizca resmi veri).
    uzak_bilgilendirme_olustur(session, db_eq)
    session.refresh(db_eq)

    return EarthquakeCreateResponse(**db_eq.model_dump(), eslesen_kullanici_sayisi=len(bildirimler))


@router.delete("/earthquakes/{earthquake_id}", summary="Deprem kaydini sil")
def delete_earthquake(
    *,
    earthquake_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(admin_gerekli),
):
    db_eq = session.get(Earthquake, earthquake_id)
    if not db_eq:
        raise HTTPException(status_code=404, detail="Deprem kaydi bulunamadı")
    session.delete(db_eq)
    session.commit()
    return {"message": "Deprem kaydi silindi"}
