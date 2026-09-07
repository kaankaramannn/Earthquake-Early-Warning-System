import os

from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import OAuth2PasswordRequestForm , OAuth2PasswordBearer
from sqlmodel import Session, select
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
from src.database import get_session
from src.users.models import User, UserCreate, UserPublic
from src.auth.schemas import Token

router = APIRouter(
    prefix="/auth",
    tags=["Auth"],)

load_dotenv()
# JWT imzalama anahtari .env'den okunur (bkz. .env.example) — kod icinde sabit
# yazilmiyor ki repo public olunca kimse gecerli token sahteleyemesin. .env
# yoksa (ilk kurulum) sadece LOKAL gelistirme icin bariz bir varsayilana duser,
# uyari basar.
SECRET_KEY = os.environ.get("SECRET_KEY")
if not SECRET_KEY:
    SECRET_KEY = "dev-only-insecure-default-degistirin"
    print(
        "[UYARI] SECRET_KEY ortam degiskeni ayarlanmamis — .env dosyasi olustur "
        "(bkz. .env.example). Bu varsayilan SADECE lokal gelistirme icindir, "
        "production'da ASLA kullanilmamali."
    )
ALGORITHM = "HS256"
TOKEN_SURESI_DAKIKA = 60 * 24 * 7  # 1 hafta (mobil oturum konforu; eski deger 30 dk)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

def sifreyi_hashle(sifre: str) -> str:
    return pwd_context.hash(sifre)

def sifreyi_dogrula(sifre: str , hashed: str) -> bool:
    return pwd_context.verify(sifre, hashed)

def token_olustur(data: dict) -> str:
    kopya = data.copy()
    bitis = datetime.utcnow() + timedelta(minutes = TOKEN_SURESI_DAKIKA)
    kopya.update ({"exp": bitis})
    return jwt.encode(kopya,SECRET_KEY, algorithm = ALGORITHM)

def aktif_kullanici(
    token: str = Depends(oauth2_scheme),
    session: Session = Depends(get_session),
) -> User:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if not username:
            raise HTTPException(status_code=401, detail="Geçersiz token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Token doğrulanamadi")

    statement = select(User).where(User.username == username)
    user = session.exec(statement).first()
    if not user:
        raise HTTPException(status_code=401, detail="Kullanici bulunamadi")
    return user
def admin_gerekli(user:User = Depends(aktif_kullanici)) ->User:
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Yetkisiz Kullanici")
    return user

# Endpoints
@router.post("/register/", response_model=UserPublic, summary="Kayit ol")
def register(user: UserCreate, session: Session = Depends(get_session)):
    statement = select(User).where(User.email == user.email)
    existing = session.exec(statement).first()
    if existing:
        raise HTTPException(status_code=409, detail="Bu email zaten kayitli")

    kullanici_sayisi = len(session.exec(select(User)).all())
    rol = "admin" if kullanici_sayisi == 0 else "user"

    db_user = User(
        **user.model_dump(exclude={"password"}),
        hashed_password=sifreyi_hashle(user.password),
        role=rol,
    )
    session.add(db_user)
    session.commit()
    session.refresh(db_user)
    return db_user

@router.post("/login/", response_model=Token, summary="Giris yap")
def login(
    form: OAuth2PasswordRequestForm = Depends(),
    session: Session = Depends(get_session),
):
    statement = select(User).where(User.username == form.username)
    user = session.exec(statement).first()
    if not user or not sifreyi_dogrula(form.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Kullanici adi veya sifre hatali")
    token = token_olustur({"sub": user.username})
    return Token(access_token=token, token_type="bearer")
