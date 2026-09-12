from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings


database_url = settings.database_url
if database_url.startswith("postgresql://"):
    database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)
if database_url.startswith("sqlite"):
    connect_args = {"check_same_thread": False}
else:
    connect_args = {
        "connect_timeout": settings.database_connect_timeout,
        "sslmode": settings.database_ssl_mode,
    }
    if settings.database_ssl_root_cert:
        connect_args["sslrootcert"] = str(settings.database_ssl_root_cert)
engine_options = {
    "connect_args": connect_args,
    "pool_pre_ping": True,
}
if not database_url.startswith("sqlite"):
    engine_options.update({
        "pool_size": settings.database_pool_size,
        "max_overflow": settings.database_max_overflow,
        "pool_timeout": settings.database_pool_timeout,
        "pool_recycle": settings.database_pool_recycle,
    })
engine = create_engine(database_url, **engine_options)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
