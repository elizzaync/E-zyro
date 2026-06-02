"""
Migración de datos: texto libre geográfico  →  FKs de catálogo (ubicacion/zona/area).

Idempotente y seguro de re-ejecutar:
- Sólo rellena columnas *_id que están en NULL.
- get-or-create por nombre (case-insensitive) evita duplicados.
- Conserva las columnas de texto legacy (no las borra).

Estrategia:
- El texto legacy (`proyecto_servicio.zona_ejecucion`, `equipo.ubicacion`) se
  interpreta como NOMBRE DE ZONA, colgada de una ubicación por defecto
  ("Sin ubicación asignada") por empresa. Así el mismo texto en servicio y en
  equipo cae en la MISMA zona → el filtro geográfico por FK reproduce el match
  por texto anterior.
- `equipo_intervenido.area_descripcion` se interpreta como ÁREA bajo la zona del
  propio equipo intervenido.
- La geografía la posee el servicio; el nivel proyecto se deriva en consulta
  (no hay tabla de mapeo proyecto↔ubicación que rellenar).

Uso (desde BACKEND/, con el .env que tiene DATABASE_URL):
    python migrations/migrate_geo_catalogo.py
"""
import os
import uuid
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()
url = os.getenv("DATABASE_URL")
if not url:
    raise SystemExit("DATABASE_URL no configurada (.env)")
if url.startswith("postgres://"):
    url = url.replace("postgres://", "postgresql://", 1)
eng = create_engine(url)

UBIC_DEFAULT = "Sin ubicación asignada"


def main():
    creados = {"ubicacion": 0, "zona": 0, "area": 0}
    seteados = {"servicio": 0, "equipo": 0, "ei_area": 0}

    with eng.begin() as c:
        # Caches: (empresa_id, lower(nombre)) -> ubicacion_id ; etc.
        ubic_cache: dict[tuple, str] = {}
        zona_cache: dict[tuple, str] = {}
        area_cache: dict[tuple, str] = {}

        def get_or_create_ubicacion(empresa_id: str, nombre: str) -> str:
            key = (empresa_id, nombre.lower())
            if key in ubic_cache:
                return ubic_cache[key]
            row = c.execute(text(
                "SELECT id FROM ubicacion WHERE empresa_id=:e AND lower(nombre)=lower(:n)"
            ), {"e": empresa_id, "n": nombre}).fetchone()
            if row:
                ubic_cache[key] = str(row[0])
                return ubic_cache[key]
            new_id = str(uuid.uuid4())
            c.execute(text(
                "INSERT INTO ubicacion (id, empresa_id, nombre) VALUES (:i,:e,:n)"
            ), {"i": new_id, "e": empresa_id, "n": nombre})
            creados["ubicacion"] += 1
            ubic_cache[key] = new_id
            return new_id

        def get_or_create_zona(empresa_id: str, ubicacion_id: str, nombre: str) -> str:
            key = (empresa_id, ubicacion_id, nombre.lower())
            if key in zona_cache:
                return zona_cache[key]
            row = c.execute(text(
                "SELECT id FROM zona WHERE empresa_id=:e AND ubicacion_id=:u AND lower(nombre)=lower(:n)"
            ), {"e": empresa_id, "u": ubicacion_id, "n": nombre}).fetchone()
            if row:
                zona_cache[key] = str(row[0])
                return zona_cache[key]
            new_id = str(uuid.uuid4())
            c.execute(text(
                "INSERT INTO zona (id, empresa_id, ubicacion_id, nombre) VALUES (:i,:e,:u,:n)"
            ), {"i": new_id, "e": empresa_id, "u": ubicacion_id, "n": nombre})
            creados["zona"] += 1
            zona_cache[key] = new_id
            return new_id

        def get_or_create_area(empresa_id: str, ubicacion_id: str, zona_id: str, nombre: str) -> str:
            key = (empresa_id, zona_id, nombre.lower())
            if key in area_cache:
                return area_cache[key]
            row = c.execute(text(
                "SELECT id FROM area WHERE empresa_id=:e AND zona_id=:z AND lower(nombre)=lower(:n)"
            ), {"e": empresa_id, "z": zona_id, "n": nombre}).fetchone()
            if row:
                area_cache[key] = str(row[0])
                return area_cache[key]
            new_id = str(uuid.uuid4())
            c.execute(text(
                "INSERT INTO area (id, empresa_id, ubicacion_id, zona_id, nombre) VALUES (:i,:e,:u,:z,:n)"
            ), {"i": new_id, "e": empresa_id, "u": ubicacion_id, "z": zona_id, "n": nombre})
            creados["area"] += 1
            area_cache[key] = new_id
            return new_id

        # ── 1) proyecto_servicio.zona_ejecucion → ubicacion default + zona ──────
        filas = c.execute(text("""
            SELECT id, empresa_id, zona_ejecucion
            FROM proyecto_servicio
            WHERE zona_id IS NULL
              AND zona_ejecucion IS NOT NULL AND btrim(zona_ejecucion) <> ''
        """)).fetchall()
        for sid, empresa_id, zona_txt in filas:
            empresa_id = str(empresa_id)
            uid = get_or_create_ubicacion(empresa_id, UBIC_DEFAULT)
            zid = get_or_create_zona(empresa_id, uid, zona_txt.strip())
            c.execute(text(
                "UPDATE proyecto_servicio SET ubicacion_id=:u, zona_id=:z WHERE id=:i"
            ), {"u": uid, "z": zid, "i": str(sid)})
            seteados["servicio"] += 1

        # ── 2) equipo.ubicacion → ubicacion default + zona ──────────────────────
        filas = c.execute(text("""
            SELECT id, empresa_id, ubicacion
            FROM equipo
            WHERE zona_id IS NULL
              AND ubicacion IS NOT NULL AND btrim(ubicacion) <> ''
        """)).fetchall()
        for eid, empresa_id, ubic_txt in filas:
            empresa_id = str(empresa_id)
            uid = get_or_create_ubicacion(empresa_id, UBIC_DEFAULT)
            zid = get_or_create_zona(empresa_id, uid, ubic_txt.strip())
            c.execute(text(
                "UPDATE equipo SET ubicacion_id=:u, zona_id=:z WHERE id=:i"
            ), {"u": uid, "z": zid, "i": str(eid)})
            seteados["equipo"] += 1

        # ── 3) equipo_intervenido.area_descripcion → area bajo su zona ──────────
        filas = c.execute(text("""
            SELECT id, empresa_id, ubicacion_id, zona_id, area_descripcion
            FROM equipo_intervenido
            WHERE area_id IS NULL
              AND zona_id IS NOT NULL
              AND area_descripcion IS NOT NULL AND btrim(area_descripcion) <> ''
        """)).fetchall()
        for eiid, empresa_id, uid, zid, area_txt in filas:
            aid = get_or_create_area(str(empresa_id), str(uid) if uid else None, str(zid), area_txt.strip())
            c.execute(text(
                "UPDATE equipo_intervenido SET area_id=:a WHERE id=:i"
            ), {"a": aid, "i": str(eiid)})
            seteados["ei_area"] += 1

    print("Catálogo creado:", creados)
    print("Registros enlazados:", seteados)


if __name__ == "__main__":
    main()
