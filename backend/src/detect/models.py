from typing import Optional
from enum import Enum
from datetime import datetime
from sqlmodel import SQLModel, Field


class DetectionStatus(str, Enum):
    pending = "pending"
    confirmed = "confirmed"
    false_positive = "false_positive"


class DetectionEvent(SQLModel, table=True):
    __tablename__ = "detection_events"

    id: Optional[int] = Field(default=None, primary_key=True)
    center_lat: float = Field(ge=-90, le=90)
    center_lon: float = Field(ge=-180, le=180)
    estimated_magnitude: Optional[float] = Field(default=None, ge=0, le=10)
    report_count: int = Field(default=0)
    status: DetectionStatus = Field(default=DetectionStatus.pending)
    matched_earthquake_id: Optional[int] = Field(default=None, foreign_key="earthquakes.id")
    created_at: datetime = Field(default_factory=datetime.utcnow)


class DetectionEventPublic(SQLModel):
    id: int
    center_lat: float
    center_lon: float
    estimated_magnitude: Optional[float]
    report_count: int
    status: DetectionStatus
    matched_earthquake_id: Optional[int]
    created_at: datetime
    # "Hissettim mi?" ozeti (Asama 6) — DetectionEvent tablosunda KOLON olarak yok,
    # FeltReport'lardan HER ISTEKTE hesaplanip buraya doldurulur (bkz. src/detect/router.py).
    oy_sayisi: int = 0
    ortalama_siddet: Optional[float] = None


class FeltReportBase(SQLModel):
    hissetti_mi: bool
    siddet: int = Field(ge=1, le=5)


class FeltReport(FeltReportBase, table=True):
    """'Hissettim mi?' topluluk geri bildirimi (Asama 6) — USGS'in 'Did You Feel It'
    ozelliginin bizim olcegimizdeki hali. Bir DetectionEvent'e (crowd tespiti) baglanir;
    kullanici basina TEK kayit tutulur (tekrar gonderirse GUNCELLENIR, cift oy olmaz —
    bkz. src/detect/router.py'deki endpoint)."""
    __tablename__ = "felt_reports"

    id: Optional[int] = Field(default=None, primary_key=True)
    detection_event_id: int = Field(foreign_key="detection_events.id")
    user_id: int = Field(foreign_key="users.id")
    created_at: datetime = Field(default_factory=datetime.utcnow)


class FeltReportCreate(FeltReportBase):
    pass


class FeltReportPublic(FeltReportBase):
    id: int
    detection_event_id: int
    created_at: datetime


class PreliminaryAlert(SQLModel, table=True):
    """Mesafe bazli erken uyari (Asama 5) icin HAFIF bir kayit — DetectionEvent'in
    AKSINE TremorReport'lari sahiplenmez (detection_event_id'lerine dokunmaz), sadece
    'bu bolgede az once bir on uyari gonderdik mi' sorusuna cevap vermek icin var.
    """
    __tablename__ = "preliminary_alerts"

    id: Optional[int] = Field(default=None, primary_key=True)
    center_lat: float = Field(ge=-90, le=90)
    center_lon: float = Field(ge=-180, le=180)
    report_count: int = Field(default=0)
    created_at: datetime = Field(default_factory=datetime.utcnow)
