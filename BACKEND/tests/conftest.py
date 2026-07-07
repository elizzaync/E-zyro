"""Carga .env antes de recolectar tests: `app.db.database` exige DATABASE_URL
en el entorno con un RuntimeError al importarse (Railway la inyecta en
producción; en local solo existe en el .env del repo). Los tests que usan
SQLite en memoria (ver test_planilla_asistencia_service.py) igual necesitan
que ese import no truene, aunque nunca toquen el engine real de Postgres.
"""
from dotenv import load_dotenv

load_dotenv()
