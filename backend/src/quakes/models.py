from typing import Optional
from sqlmodel import SQLModel, Field
from datetime import datetime

class EarthquakeBase(SQLModel):
    magnitude: float = Field(ge = 0 , le = 10)
    latitude: float = Field(ge = -90 , le = 90)
    longitude: float = Field(ge = -180 , le = 180)
    depth_km: float = Field(ge=0, le=700)
    occurred_at: datetime
    location_name: Optional[str] = None

class Earthquake(EarthquakeBase , table = True):
    __tablename__ = "earthquakes"
    id : Optional[int] = Field(default = None , primary_key= True)
    created_by: Optional[int] = Field(default=None, foreign_key="users.id")

class EarthquakeCreate(EarthquakeBase):
    pass

class EarthquakePublic(EarthquakeBase):
    id : int
    created_by : Optional[int]

class EarthquakeCreateResponse(EarthquakePublic):
    eslesen_kullanici_sayisi: int
