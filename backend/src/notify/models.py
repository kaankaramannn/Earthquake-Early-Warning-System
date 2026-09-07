from typing import Optional
from sqlmodel import SQLModel, Field
from datetime import datetime

class Notification(SQLModel, table=True):
    __tablename__ = "notifications"

    id: Optional[int] = Field(default=None, primary_key=True)
    earthquake_id: Optional[int] = Field(default=None, foreign_key="earthquakes.id")
    detection_event_id: Optional[int] = Field(default=None, foreign_key="detection_events.id")
    user_id: int = Field(foreign_key="users.id")
    matched_reason: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

class NotificationPublic(SQLModel):
    id: int
    earthquake_id: Optional[int]
    detection_event_id: Optional[int]
    user_id: int
    matched_reason: str
    created_at: datetime
