"""
Migración one-off: tabla `planos`/`carpetas_planos` del ERP legacy
(esystemtic_erp, MySQL/MariaDB) → módulo Nube de Planos de e-zyro
(Plano + VersionPlano + CarpetaDocumental, PostgreSQL).

Decisiones tomadas con el usuario (2026-07-08, ver conversación):
  - TODOS los planos se cargan bajo el tenant TALMA S.A. (empresa_id fijo),
    el otro tenant (Esystemtic S.A.C.) no participa de esta migración.
  - Sin vínculo a proyecto/proyecto_servicio: el dump legacy solo trae
    `id_servicio` (int), y no tenemos la tabla `servicios` legacy para
    resolverlo a un proyecto_servicio real — se importa como documento
    "tipo Drive" (Plano.proyecto_id = NULL), organizado en carpetas
    anidadas por año → área, igual que el usuario puede hacerlo a mano
    desde la UI (carpeta_documental ya soporta padre_id recursivo).
  - subido_por = usuario "Hernan Jesus Quispe Gutierrez" (empleado de
    Esystemtic, cruzado a propósito con el tenant TALMA — decisión
    explícita del usuario, no un bug).
  - `fecha` de cada VersionPlano preserva el `created_at` ORIGINAL del
    registro legacy (no la fecha de la migración) — son documentos
    históricos, no nuevos.
  - Deduplicado a mano contra el dump SQL: de las 22 filas de `planos`
    legacy, varias son duplicados exactos (mismo nombre+ruta+codigo) o
    tienen `ruta` NULL (sin archivo) — quedan 15 filas únicas con archivo
    real verificado en disco.

Reusa el flujo REAL de la app (mismos modelos SQLAlchemy y el mismo
`cloudinary_service.subir_archivo_base64` que usa `POST /planos`), no SQL
crudo — así el resultado es indistinguible de si alguien hubiera subido
cada plano a mano desde la UI.

Uso:
    cd BACKEND
    python migrations/migrate_legacy_planos_talma.py --dry-run
    python migrations/migrate_legacy_planos_talma.py
"""
from __future__ import annotations

import argparse
import base64
import logging
import sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # para que `import app.*` resuelva

# IMPORTANTE: configurar logging ANTES de cualquier import de `app.*` —
# `app.core.config_cloudinary` emite un logging.warning() al importarse, y
# esa primera llamada auto-inicializa el root logger (nivel WARNING por
# defecto) si nadie lo hizo antes; un basicConfig() posterior sería un no-op
# y las líneas log.info() de este script nunca se verían.
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("migrate_planos_talma")

from dotenv import load_dotenv
load_dotenv()

from app.db.database import SessionLocal
# Registran sus Table en Base.metadata para que SQLAlchemy resuelva las FK de
# string ("proyecto.id", "usuario.id", "empresa.id") al hacer flush() —
# CarpetaDocumental/Plano/VersionPlano las referencian pero no las importan.
import app.models.proyecto  # noqa: F401
import app.models.usuario  # noqa: F401
import app.models.empresa  # noqa: F401
from app.models.plano import Plano, VersionPlano
from app.models.carpeta_documental import CarpetaDocumental
from app.services.cloudinary_service import subir_archivo_base64
from app.services.cloudinary_paths import carpeta_planos

EMPRESA_ID = "04f308e6-e08e-49af-a030-8e52d0eb3f79"      # TALMA S.A.
SUBIDO_POR = "abc6a124-5a01-4e5c-aca4-dcf884c5f7b9"      # Hernan Jesus Quispe Gutierrez

PLANOS_DIR = Path(r"C:\Users\harol\Downloads\archive (3)\web\almacen.esystemtic.com\public_html\erp-system\src\storage\uploads\planos")

RAIZ_CARPETA = "Planos ERP Antiguo (migrados)"

# (carpeta_padre_lógica) -> (año|None, nombre de sub-carpeta). año=None significa
# "hija directa de RAIZ_CARPETA" (sin agrupar por año) — usado para los archivos
# sin metadata en el dump legacy (ver EXTRAS más abajo).
CARPETAS = {
    "2024/Patio de Maniobras": ("2024", "Patio de Maniobras"),
    "2024/Almacenes":          ("2024", "Almacenes"),
    "2025/Zona A":             ("2025", "Zona A"),
    "2025/Lurin":              ("2025", "Lurin"),
    "2026/Rampa":              ("2026", "Rampa"),
    "Sin Clasificar":          (None, "Sin Clasificar"),
}

# id_plano legacy (solo para trazabilidad en logs) + metadata + archivo.
PLANOS: list[dict] = [
    dict(id_legacy=1, nombre="LUMINARIAS PATIO DE MANIOBRAS", codigo="IE-01",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - PATIO DE MANIOBRAS",
         estado="Aprobado", created_at="2024-10-22", carpeta="2024/Patio de Maniobras",
         file="IE 01 LUMINARIAS PATIO DE MANIOBRAS 28_06.pdf"),
    dict(id_legacy=2, nombre="TOMACORRIENTES PATIO DE MANIOBRAS", codigo="IE-02",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - PATIO DE MANIOBRAS",
         estado="Aprobado", created_at="2024-10-22", carpeta="2024/Patio de Maniobras",
         file="IE 02 TOMACORRIENTES PATIO DE MANIOBRAS.pdf"),
    dict(id_legacy=3, nombre="INSTALACIONES HVAC PATIO DE MANIOBRAS", codigo="IE-03",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - PATIO DE MANIOBRAS",
         estado="Aprobado", created_at="2024-11-05", carpeta="2024/Patio de Maniobras",
         file="IE 03 INSTALACIONES HVAC PATIO DE MANIOBRAS.pdf"),
    dict(id_legacy=4, nombre="DIAGRAMAS UNIFILARES PATIO DE MANIOBRAS", codigo="IE-04",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - PATIO DE MANIOBRAS",
         estado="Aprobado", created_at="2024-11-05", carpeta="2024/Patio de Maniobras",
         file="IE 04 DIAGRAMAS UNIFILARES PATIO DE MANIOBRAS.pdf"),
    dict(id_legacy=5, nombre="DIRECTORIOS PATIO DE MANIOBRAS", codigo="IE-05",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - PATIO DE MANIOBRAS",
         estado="Aprobado", created_at="2024-11-05", carpeta="2024/Patio de Maniobras",
         file="IE 05 DIRECTORIOS PATIO DE MANIOBRAS.pdf"),
    dict(id_legacy=6, nombre="LUMINARIAS ALMACENES", codigo="IE-01",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - ALMACENES",
         estado="Pendiente", created_at="2024-11-05", carpeta="2024/Almacenes",
         file="IE 01 ALMACEN LCC LUMINARIAS.pdf"),
    dict(id_legacy=7, nombre="TOMACORRIENTES ALMACENES", codigo="IE-02",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - ALMACENES",
         estado="Pendiente", created_at="2024-11-05", carpeta="2024/Almacenes",
         file="IE 02 ALMACENES LCC TOMACORRIENTES.pdf"),
    dict(id_legacy=8, nombre="INSTALACIONES HVAC ALMACENES", codigo="IE-03",
         ubicacion="CALLAO - LIMA", area="LIMA CARGO - ALMACENES",
         estado="Aprobado", created_at="2024-11-05", carpeta="2024/Almacenes",
         file="IE 03 ALMACENES LCC HVAC.pdf"),
    dict(id_legacy=10, nombre="IE 12 DIAGRAMAS UNIFILARES Y CUADRO DE CARGAS ZONA A", codigo="IE 12",
         ubicacion="LIMA METROPOLITANA", area="xxxxxxxxx",
         estado="Pendiente", created_at="2026-02-11", carpeta="2025/Zona A",
         file="IE 12 DIAGRAMAS UNIFILARES Y CUADRO DE CARGAS ZONA A.pdf"),
    dict(id_legacy=13, nombre="F-2352-E0010-000000-101_Rev.2_DIAGRAMAS UNIFILARES", codigo="F-2352-E0010-000000-101",
         ubicacion="CALLAO - LIMA", area="RAMPA",
         estado="Pendiente", created_at="2026-03-02", carpeta="2026/Rampa",
         file=r"1\2026\F-2352-E0010-000000-101_69a99efc6ce4e_F-2352-E0010-000000-101_Rev.2_DIAGRAMASUNIFILARES.pdf"),
    dict(id_legacy=15, nombre="F-2352-E0010-000000-102_Rev.2_RECORRIDO DE BANDEJA EXISTENTE", codigo="F-2352-E0010-000000-102",
         ubicacion="CALLAO - LIMA", area="RAMPA",
         estado="Pendiente", created_at="2026-03-02", carpeta="2026/Rampa",
         file=r"1\2026\F-2352-E0010-000000-102_69a99f2048c0f_F-2352-E0010-000000-102_Rev.2_RECORRIDODEBANDEJAEXISTENTE.pdf"),
    dict(id_legacy=19, nombre="IE 01 CUADRO DE CARGAS DE POTENCIA CONTRATADA", codigo="IE 01",
         ubicacion="LIMA METROPOLITANA", area="Lurin",
         estado="Aprobado", created_at="2026-03-16", carpeta="2025/Lurin",
         file=r"6\2025\IE01_69b8251a039f1_IE01CUADRODECARGASDEPOTENCIACONTRATADA.pdf"),
    dict(id_legacy=20, nombre="IE 02 ESQUEMA DE MONTANTE ELECTRICA", codigo="IE 02",
         ubicacion="LIMA METROPOLITANA", area="Lurin",
         estado="Aprobado", created_at="2026-03-16", carpeta="2025/Lurin",
         file=r"2025\plano_69b82563111480.62696490.pdf"),
    dict(id_legacy=21, nombre="IE 03 PLANO DE UBICACIÓN DE TABLEROS ELECTRICOS PRIMER NIVEL", codigo="IE 03",
         ubicacion="LIMA METROPOLITANA", area="Lurin",
         estado="Aprobado", created_at="2026-03-16", carpeta="2025/Lurin",
         file=r"2025\plano_69b825b1bbf750.01521142.pdf"),
    dict(id_legacy=22, nombre="IE 04 PLANO DE UBICACIÓN DE TABLEROS ELECTRICOS SEGUNDO NIVEL", codigo="IE 04",
         ubicacion="LIMA METROPOLITANA", area="Lurin",
         estado="Aprobado", created_at="2026-03-16", carpeta="2025/Lurin",
         file=r"2025\plano_69b8264a01f6c2.15147685.pdf"),
]

# EXTRA (2026-07-08, confirmado explícitamente con el usuario): único archivo
# suelto en la carpeta legacy sin fila en el dump SQL de `planos` — sin
# código/ubicación/fecha legada, va a "Sin Clasificar" con nota de que falta
# metadata. Los otros 2 archivos sueltos (F-2352-101/102) NO se suben: son
# copias byte-a-byte (MD5 idéntico, verificado) de id_legacy=13 y 15, ya
# migrados — el usuario confirmó dejarlos fuera para no duplicar contenido.
PLANOS_EXTRA: list[dict] = [
    dict(id_legacy="extra-tambomachay", nombre="IE 01 ILUMINACION TAMBOMACHAY 2DO NIVEL",
         codigo=None, ubicacion=None, area=None,
         estado="Sin metadata en el dump legacy", created_at=None, carpeta="Sin Clasificar",
         file="IE 01 ILUMINACION TAMBOMACHAY 2DO NIVEL.pdf"),
]
PLANOS = PLANOS + PLANOS_EXTRA

ESPECIALIDAD = "INSTALACIONES ELECTRICAS"


def _get_or_create_carpeta(db, nombre: str, padre_id: str | None) -> CarpetaDocumental:
    existente = db.query(CarpetaDocumental).filter(
        CarpetaDocumental.empresa_id == EMPRESA_ID,
        CarpetaDocumental.nombre == nombre,
        CarpetaDocumental.padre_id == padre_id,
    ).first()
    if existente:
        return existente
    c = CarpetaDocumental(empresa_id=EMPRESA_ID, nombre=nombre, padre_id=padre_id, created_at=datetime.utcnow())
    db.add(c)
    db.flush()
    log.info("  + carpeta creada: %s (padre=%s)", nombre, padre_id or "raíz")
    return c


def preparar_carpetas(db) -> dict[str, str]:
    """Crea (o reusa) la jerarquía de carpetas y devuelve {clave_logica: carpeta_id}.
    anio=None → la carpeta cuelga directo de RAIZ_CARPETA (sin agrupar por año)."""
    raiz = _get_or_create_carpeta(db, RAIZ_CARPETA, None)
    cache_anio: dict[str, CarpetaDocumental] = {}
    resultado: dict[str, str] = {}
    for clave, (anio, area) in CARPETAS.items():
        if anio is None:
            carpeta_area = _get_or_create_carpeta(db, area, raiz.id)
        else:
            if anio not in cache_anio:
                cache_anio[anio] = _get_or_create_carpeta(db, anio, raiz.id)
            carpeta_area = _get_or_create_carpeta(db, area, cache_anio[anio].id)
        resultado[clave] = carpeta_area.id
    return resultado


def migrar(dry_run: bool) -> None:
    faltantes = [p for p in PLANOS if not (PLANOS_DIR / p["file"]).is_file()]
    if faltantes:
        for p in faltantes:
            log.error("Archivo NO encontrado para id_legacy=%s: %s", p["id_legacy"], PLANOS_DIR / p["file"])
        raise SystemExit(f"{len(faltantes)} archivo(s) no encontrados — abortando antes de tocar la BD.")

    log.info("Empresa destino: TALMA S.A. (%s)", EMPRESA_ID)
    log.info("subido_por: Hernan Jesus Quispe Gutierrez (%s)", SUBIDO_POR)
    log.info("%d planos a migrar, verificados en disco.", len(PLANOS))

    if dry_run:
        for p in PLANOS:
            log.info("[DRY] id_legacy=%s → carpeta '%s' · nombre='%s' · archivo=%s",
                      p["id_legacy"], p["carpeta"], p["nombre"], p["file"])
        log.info("[DRY] Nada se escribió en la BD ni se subió a Cloudinary.")
        return

    db = SessionLocal()
    try:
        carpetas_por_clave = preparar_carpetas(db)
        db.commit()

        creados = omitidos = 0
        for p in PLANOS:
            ya_existe = db.query(Plano).filter(
                Plano.empresa_id == EMPRESA_ID,
                Plano.nombre == p["nombre"],
                Plano.carpeta_id == carpetas_por_clave[p["carpeta"]],
            ).first()
            if ya_existe:
                log.info("id_legacy=%s omitido (ya existe un plano '%s' en esa carpeta).", p["id_legacy"], p["nombre"])
                omitidos += 1
                continue

            ruta = PLANOS_DIR / p["file"]
            contenido = ruta.read_bytes()
            b64 = base64.b64encode(contenido).decode("ascii")

            if p["codigo"] is None:
                descripcion = f"Sin metadata en el dump legacy — estado: {p['estado']}"
            else:
                descripcion = f"Código: {p['codigo']} · Ubicación: {p['ubicacion']} · Área: {p['area']} · Estado legado: {p['estado']}"
            pl = Plano(
                empresa_id=EMPRESA_ID, nombre=p["nombre"][:200], disciplina=ESPECIALIDAD,
                descripcion=descripcion[:255],
                carpeta_id=carpetas_por_clave[p["carpeta"]], proyecto_id=None,
                created_at=datetime.utcnow(),
            )
            db.add(pl)
            db.flush()  # obtener pl.id

            res = subir_archivo_base64(
                b64, folder=carpeta_planos(EMPRESA_ID),
                public_id=f"{pl.id}-legacy{p['id_legacy']}", extension="pdf",
            )
            # Sin fecha legada disponible (EXTRA sin metadata): usa la fecha de hoy.
            fecha_original = date.fromisoformat(p["created_at"]) if p["created_at"] else date.today()
            v = VersionPlano(
                plano_id=pl.id, empresa_id=EMPRESA_ID, version="v1",
                url_cloudinary=res["secure_url"], public_id_cloudinary=res["public_id"],
                subido_por=SUBIDO_POR, fecha=fecha_original, es_version_activa=True,
                formato=res.get("format") or "pdf", bytes=res.get("bytes"),
                created_at=datetime.utcnow(),
            )
            db.add(v)
            db.commit()
            log.info("id_legacy=%s ✓ migrado → plano_id=%s (%s bytes)", p["id_legacy"], pl.id, res.get("bytes"))
            creados += 1

        log.info("Hecho. Planos creados: %d · omitidos (ya existían): %d.", creados, omitidos)
    except Exception:
        db.rollback()
        log.exception("Falló la migración — rollback de la transacción en curso.")
        raise
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Migra los planos legacy de TALMA a la Nube de Planos de e-zyro.")
    parser.add_argument("--dry-run", action="store_true", help="No escribe nada, solo reporta el plan.")
    args = parser.parse_args()
    migrar(dry_run=args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
