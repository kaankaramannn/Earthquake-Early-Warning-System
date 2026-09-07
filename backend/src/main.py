from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.database import create_db_and_tables
from src.auth.router import router as auth_router
from src.users.router import router as users_router
from src.users.location_router import router as user_locations_router
from src.admin.router import router as admin_router
from src.quakes.router import router as quakes_router
from src.notify.router import router as notify_router
from src.dev.router import router as dev_router
from src.tremor.router import router as tremor_router
from src.detect.router import router as detect_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield

app = FastAPI(
    title="Deprem Bildirim API",
    description="Bu API, deprem bildirimlerini yönetmek için kullanilir.",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS: mobil/web istemcilerin (farkli origin'lerden) API'ye erisebilmesi icin.
# Gelistirme asamasinda tum origin'lere acik; production'da daraltilir.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


#router bağlantısı


app.include_router(auth_router)
app.include_router(users_router)
app.include_router(user_locations_router)
app.include_router(admin_router)
app.include_router(quakes_router)
app.include_router(notify_router)
app.include_router(dev_router)
app.include_router(tremor_router)
app.include_router(detect_router)
