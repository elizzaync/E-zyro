from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from pathlib import Path
from dotenv import load_dotenv

# Carga explícita del .env desde la raíz de BACKEND (en Railway la variable
# venía inyectada por el entorno; en local vive en el .env).
_env_path = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=_env_path)

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

if not SQLALCHEMY_DATABASE_URL:
    raise RuntimeError("DATABASE_URL no configurada. Verifica las variables de entorno.")

if SQLALCHEMY_DATABASE_URL.startswith("postgres://"):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,        # detecta conexiones caídas antes de usarlas
    pool_recycle=1800,         # recicla conexiones cada 30 min
    connect_args={"connect_timeout": 10},
    # Desactiva el batch INSERT...RETURNING de SQLAlchemy 2.0 (`insertmanyvalues`).
    # Muchos modelos declaran String(36) sobre columnas `uuid` nativas; al insertar
    # 2+ filas en un flush, psycopg2 devuelve uuid.UUID en el RETURNING pero el
    # parámetro fue str, y el sentinel (str, UUID) no matchea (UUID, UUID) →
    # "Can't match sentinel values". Sin este batch, el ORM cae al camino clásico
    # (insert fila a fila) y el desajuste de tipos deja de romper. Costo de
    # rendimiento despreciable a esta escala; correctitud garantizada en todo modelo.
    use_insertmanyvalues=False,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()
# Dependencia para inyectar la BD en las rutas
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()