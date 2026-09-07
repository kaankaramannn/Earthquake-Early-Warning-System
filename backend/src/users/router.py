from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from src.database import get_session
from src.users.models import User, UserPublic, FcmTokenUpdate, UserPreferencesUpdate
from src.notify.models import Notification, NotificationPublic
from src.auth.router import aktif_kullanici

router = APIRouter(
    prefix="/user",
    tags=["User"],
)

@router.get("/me/", response_model=UserPublic, summary="Aktif kullanici bilgisi")
def beni_getir(user: User = Depends(aktif_kullanici)):
    return user

@router.patch("/fcm-token/", response_model=UserPublic, summary="FCM push token'imi kaydet")
def fcm_token_kaydet(
    *,
    veri: FcmTokenUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    # Mobil uygulama login sonrasi cihazin push adresini buraya yazar.
    # Ayni kullanici yeni cihazdan girerse token guncellenir (tek cihaz modeli).
    current_user.fcm_token = veri.fcm_token
    session.add(current_user)
    session.commit()
    session.refresh(current_user)
    return current_user


@router.get("/notifications/", response_model=list[NotificationPublic], summary="Kendi bildirimlerimi getir")
def get_my_notifications(
    *,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    statement = select(Notification).where(Notification.user_id == current_user.id)
    return session.exec(statement).all()


@router.patch("/preferences/", response_model=UserPublic, summary="Kendi tercihlerimi güncelle")
def update_preferences(
    *,
    preferences: UserPreferencesUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    preferences_data = preferences.model_dump(exclude_unset=True)
    current_user.sqlmodel_update(preferences_data)
    session.add(current_user)
    session.commit()
    session.refresh(current_user)
    return current_user
