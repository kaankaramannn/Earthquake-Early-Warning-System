from fastapi import APIRouter, HTTPException , Depends , Query
from sqlmodel import Session , select

from src.database import get_session
from src.quakes.models import Earthquake , EarthquakePublic

router = APIRouter(
    prefix="/earthquakes",
    tags=["Earthquakes"],
)

@router.get("/", response_model=list[EarthquakePublic], summary="Tüm deprem kayitlarini listele")
def get_earthquakes(
    *,
    session: Session = Depends(get_session),
    skip: int = 0,
    limit: int = Query(default=20, le=100),
    min_magnitude: float | None = Query(default=None),
):
    statement = select(Earthquake)
    if min_magnitude is not None:
        statement = statement.where(Earthquake.magnitude >= min_magnitude)
    statement = statement.offset(skip).limit(limit)
    return session.exec(statement).all()

@router.get("/{earthquake_id}", response_model=EarthquakePublic, summary="Tek deprem kaydi getir")
def get_earthquake(*, earthquake_id: int, session: Session = Depends(get_session)):
    db_eq = session.get(Earthquake, earthquake_id)
    if not db_eq:
        raise HTTPException(status_code=404, detail="Deprem kaydi bulunamadi")
    return db_eq
