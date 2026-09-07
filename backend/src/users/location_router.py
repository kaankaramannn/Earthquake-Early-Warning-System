from fastapi import APIRouter, HTTPException, Depends
from sqlmodel import Session, select

from src.database import get_session
from src.users.models import User, UserLocation, UserLocationCreate, UserLocationPublic
from src.auth.router import aktif_kullanici

router = APIRouter(
    prefix="/user/locations",
    tags=["User Locations"],
)


@router.get("/", response_model=list[UserLocationPublic], summary="Ek konumlarimi listele")
def ek_konumlari_getir(
    *,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    statement = select(UserLocation).where(UserLocation.user_id == current_user.id)
    return session.exec(statement).all()


@router.post("/", response_model=UserLocationPublic, summary="Yeni ek konum ekle")
def ek_konum_ekle(
    *,
    konum: UserLocationCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    db_konum = UserLocation(**konum.model_dump(), user_id=current_user.id)
    session.add(db_konum)
    session.commit()
    session.refresh(db_konum)
    return db_konum


@router.delete("/{konum_id}/", summary="Ek konumu sil")
def ek_konum_sil(
    *,
    konum_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    db_konum = session.get(UserLocation, konum_id)
    # Baskasinin konumunu goremesin/silemesin diye 404 ile (403 degil) — kaydin
    # var olup olmadigi bilgisini disariya sizdirmiyoruz.
    if not db_konum or db_konum.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Konum bulunamadı")
    session.delete(db_konum)
    session.commit()
    return {"message": "Konum silindi"}
