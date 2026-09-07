from fastapi import APIRouter, HTTPException, Depends
from sqlmodel import Session, select

from src.database import get_session
from src.users.models import User, UserPublic
from src.auth.router import admin_gerekli

#router
router = APIRouter(
    prefix="/admin",
    tags=["Admin"],
)

#endpoint

@router.get("/users/", response_model=list[UserPublic], summary="Tüm kullanicilari listele")
def get_all_users(
    *,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    statement = select(User)
    return session.exec(statement).all()
