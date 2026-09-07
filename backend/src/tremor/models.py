from typing import Optional
from datetime import datetime
from sqlmodel import SQLModel, Field


class TremorReportBase(SQLModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    intensity: float = Field(ge=0, le=10)


class TremorReport(TremorReportBase, table=True):
    __tablename__ = "tremor_reports"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id")
    detection_event_id: Optional[int] = Field(default=None, foreign_key="detection_events.id")
    reported_at: datetime = Field(default_factory=datetime.utcnow)


class TremorReportCreate(TremorReportBase):
    pass


class TremorReportPublic(TremorReportBase):
    id: int
    user_id: int
    detection_event_id: Optional[int]
    reported_at: datetime
