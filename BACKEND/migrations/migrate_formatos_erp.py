"""
Migración ÚNICA: importa la biblioteca de formatos del ERP legado
(esystemtic_erp.formatos, MariaDB) al módulo /formatos de E-zyro.

Origen de datos:
  - Metadatos: dump `formatos.sql` del ERP (14 filas; se excluye la fila de
    prueba id=15). Fechas originales conservadas.
  - PDFs: extraídos de `archive (4).zip` → .../uploads/formatos/.

Comportamiento:
  - Idempotente por nombre: si ya existe un formato activo con el mismo
    nombre en la empresa, se salta.
  - Sube cada PDF a Cloudinary (e-zyro/formatos/<empresa_id>) y crea
    formato_documento + formato_documento_version v1 con origen='erp_legacy'.
  - Registra evento FORMATO_IMPORT en audit_log por cada formato migrado.

Uso:
  .venv\\Scripts\\python -m migrations.migrate_formatos_erp "C:\\ruta\\a\\los\\pdfs"
"""
from __future__ import annotations

import base64
import sys
import uuid
from datetime import datetime
from pathlib import Path

from app.db.database import SessionLocal
from app.models.formato_documento import FormatoDocumento, FormatoDocumentoVersion
from app.services.audit_service import registrar_evento
from app.services.cloudinary_service import subir_archivo_base64

EMPRESA_ID = "dbfed7ef-9768-4dd0-86fc-917c6f4b1aea"  # Esystemtic S.A.C.

# (nombre, tipo_formato, archivo, created_at, updated_at_erp)
# updated_at_erp solo documenta en la nota que el ERP registró una
# actualización; el archivo disponible es el último que quedó en el servidor.
FORMATOS = [
    ("ATS", "SST", "Formato ATS v1-22.10.24 .pdf", "2025-03-13", None),
    ("ASISTENCIA", "Operaciones",
     "20240523_Lista_Asistencia__Inicio_Proyecto_05.09.2024 - campo -.pdf",
     "2025-03-13", "2025-03-13"),
    ("PETAR", "SST", "3_ FOR_PETAR_V1_15.01.2025.pdf", "2025-03-13", None),
    ("CHECK LIST DE ANDAMIO", "SST", "formato_6a0f48ebe2bd74.18552192.pdf",
     "2025-03-13", "2025-03-13"),
    ("CHECK LIST ARNES", "SST", "formato_6a0f49355d4e73.30387474.pdf",
     "2025-03-13", "2026-05-21"),
    ("INSPECCION DE ESCALERA", "SST", "formato_6a0f4bd3b5d450.12722026.pdf",
     "2025-03-13", None),
    ("TARJETAS DE ANDAMIOS-ROJO", "SST", "TARJETAS DE ANDAMIOS-ROJO.pdf",
     "2025-03-13", None),
    ("TARJETA ANDAMIOS-VERDE", "SST", "TARJETAS DE ANDAMIOS-VERDE.pdf",
     "2025-03-13", None),
    ("LISTA HERRAMIENTAS VACIA PDF", "Operaciones",
     "3-LISTA DE HERRAMIENTAS  VACIA 3-08.pdf", "2025-03-13", None),
    ("PLANTILLA PROCEDIMIENTO TABLEROS", "Operaciones",
     "4-5Manual de procedimientos  R Mtto Tableros Electricos10.02.22.pdf",
     "2025-03-13", None),
    ("SCRT VIGENTE", "SST", "formato_6a29bbd8cf8722.42728156.pdf",
     "2025-03-13", "2026-06-10"),
    ("CHECK LIST HERRAMIENTAS MANUALES V.02", "SST",
     "formato_6a0f4ad4ef9f48.34484125.pdf", "2026-05-21", None),
    # El ERP decía "CHECL LIST..." (typo evidente): se corrige al importar.
    ("CHECK LIST HERRAMIENTAS ELECTRICAS", "SST",
     "formato_6a0f4b14591948.50680950.pdf", "2026-05-21", None),
]


def main(carpeta_pdfs: str) -> None:
    base = Path(carpeta_pdfs)
    if not base.is_dir():
        print(f"ERROR: no existe la carpeta {base}")
        sys.exit(1)

    db = SessionLocal()
    migrados = saltados = errores = 0
    try:
        for nombre, tipo, archivo, created, updated_erp in FORMATOS:
            existe = db.query(FormatoDocumento).filter(
                FormatoDocumento.empresa_id == EMPRESA_ID,
                FormatoDocumento.activo.is_(True),
                FormatoDocumento.nombre.ilike(nombre),
            ).first()
            if existe:
                print(f"  = ya existe, salto: {nombre}")
                saltados += 1
                continue

            ruta = base / archivo
            if not ruta.is_file():
                print(f"  ! PDF no encontrado, salto: {archivo}")
                errores += 1
                continue

            raw = ruta.read_bytes()
            b64 = base64.b64encode(raw).decode()
            res = subir_archivo_base64(
                b64, f"e-zyro/formatos/{EMPRESA_ID}", str(uuid.uuid4()), extension="pdf"
            )

            nota = "Migrado del ERP legado (esystemtic_erp.formatos)."
            if updated_erp:
                nota += f" El ERP registró una actualización el {updated_erp}."

            created_dt = datetime.fromisoformat(created)
            f = FormatoDocumento(
                id=str(uuid.uuid4()), empresa_id=EMPRESA_ID,
                nombre=nombre, tipo_formato=tipo, version_actual=1,
                created_at=created_dt,
            )
            v = FormatoDocumentoVersion(
                id=str(uuid.uuid4()), formato_id=f.id, numero_version=1,
                archivo_url=res.get("secure_url", ""),
                archivo_public_id=res.get("public_id"),
                nombre_archivo=archivo, tamano_bytes=len(raw),
                nota=nota, origen="erp_legacy",
                subido_por_nombre="Migración ERP",
                created_at=created_dt,
            )
            db.add(f)
            db.add(v)
            db.flush()
            registrar_evento(
                accion="FORMATO_IMPORT", empresa_id=EMPRESA_ID,
                usuario_nombre="Migración ERP",
                entidad="formato_documento", entidad_id=f.id,
                detalle={"nombre": nombre, "archivo": archivo,
                         "origen": "erp_legacy", "created_at_erp": created},
                db=db,
            )
            print(f"  + migrado: {nombre}  ({len(raw)//1024} KB)")
            migrados += 1
    finally:
        db.close()

    print(f"\nResumen: {migrados} migrados, {saltados} ya existían, {errores} con error.")
    if errores:
        sys.exit(2)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python -m migrations.migrate_formatos_erp <carpeta_con_pdfs>")
        sys.exit(1)
    main(sys.argv[1])
