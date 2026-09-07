from sqlmodel import SQLModel, Session, create_engine

from src.config import DATA_DIR

sqlite_file_name = DATA_DIR / "earthquake.db"
sqlite_url = f"sqlite:///{sqlite_file_name}"

connect_args = {"check_same_thread": False}

# echo=False: SQL loglari kapali (sunum/temiz konsol). Gelistirirken True yapilabilir.
engine = create_engine(sqlite_url, echo=False, connect_args=connect_args)


def create_db_and_tables():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session
