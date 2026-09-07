from typing import Optional
from datetime import datetime
from sqlmodel import SQLModel, Field
from pydantic import EmailStr

#Kullanici modeli

class UserBase(SQLModel):
    username: str = Field(min_length = 3, index = True, unique = True)
    email: EmailStr = Field(index = True, unique = True)

class User(UserBase, table = True):
    __tablename__ = "users"

    id: Optional[int] = Field(default = None, primary_key = True)
    hashed_password: str
    # FCM push adresi: mobil uygulama login sonrasi kaydeder (Faz 4).
    fcm_token: Optional[str] = Field(default=None)
    role: str = Field(default = "user")
    pref_latitude: Optional[float] = Field(default=None,ge=-90,le = 90)
    pref_longitude: Optional[float] = Field(default=None, ge= -180 , le= 180)
    pref_radius_km: Optional[float] = Field(default=None, ge=0, le=1000)
    pref_min_magnitude: Optional[float] = Field(default=None, ge=0, le=10)


class UserCreate(UserBase):
    password:str =Field(min_length = 6)

class UserPublic(UserBase):
    id: int
    role:str
    pref_latitude: Optional[float] = None
    pref_longitude: Optional[float] = None
    pref_radius_km: Optional[float] = None
    pref_min_magnitude: Optional[float] = None

class FcmTokenUpdate(SQLModel):
    fcm_token: str

class UserPreferencesUpdate(SQLModel):
    pref_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    pref_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    pref_radius_km: Optional[float] = Field(default=None, ge=0, le=1000)
    pref_min_magnitude: Optional[float] = Field(default=None, ge=0, le=10)


# Kullanicinin BIRINCIL konumunun (User.pref_*) YANINDA ek takip noktalari
# (ör. "Ev", "Isyeri") — GPS/manuel birincil konumdan BAGIMSIZ olarak calisir,
# kendi yaricap/min-buyukluk esigine sahiptir. Bkz. notify/router.py'deki
# ek_konumlari_bildir() — depreme_uygun_kullanicilari_bul ile ayni haversine
# mantigini bu tablo icin de uygular.
class UserLocation(SQLModel, table=True):
    __tablename__ = "user_locations"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id")
    etiket: str = Field(max_length=50)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    radius_km: float = Field(default=100, ge=0, le=1000)
    min_magnitude: float = Field(default=3.0, ge=0, le=10)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserLocationCreate(SQLModel):
    etiket: str = Field(min_length=1, max_length=50)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    radius_km: float = Field(default=100, ge=0, le=1000)
    min_magnitude: float = Field(default=3.0, ge=0, le=10)


class UserLocationPublic(UserLocationCreate):
    id: int
