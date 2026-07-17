# -*- coding: utf-8 -*-
"""
Migración ÚNICA: importa las calibraciones del ERP legado (esystemtic_erp.
calibraciones, MariaDB) + certificados PDF históricos al módulo de
calibraciones de E-zyro (calibracion_evento = historial/versiones,
calibracion = snapshot vigente, mismo modelo que usa el router).

Mapeo ERP id_equipo → equipo E-zyro verificado por NÚMERO DE SERIE leído
dentro de cada certificado PDF (no por nombre).

Idempotente por (equipo_id, numero_certificado): si el evento ya existe, se
salta. Cada evento sube su PDF a Cloudinary en carpeta_calibracion() y se
registra CALIBRACION_IMPORT en audit_log.

Uso:
  .venv\\Scripts\\python -m migrations.migrate_calibraciones_erp "C:\\ruta\\pdfs"
"""
from __future__ import annotations

import base64
import sys
import uuid
from datetime import date, datetime
from pathlib import Path

from app.db.database import SessionLocal
# Modelos referenciados por las FK de Equipo/Calibracion: deben estar en el
# metadata para que SQLAlchemy resuelva las tablas al hacer flush.
from app.models import (  # noqa: F401
    empresa, proyecto, cliente, ubicacion, zona, area, marca,
    modelo_equipo, almacen, categoria_material,
)
from app.models import tipo_equipo as _tipo_equipo  # noqa: F401
from app.models import categoria_equipo as _cat_eq  # noqa: F401
from app.models.calibracion import Calibracion, CalibracionEvento
from app.models.equipo import Equipo
from app.services.audit_service import registrar_evento
from app.services.cloudinary_service import subir_archivo_base64
from app.services.cloudinary_paths import carpeta_calibracion

EMPRESA_ID = "dbfed7ef-9768-4dd0-86fc-917c6f4b1aea"  # Esystemtic S.A.C.

# Equipos E-zyro (uuid) verificados por serie:
MEG_002      = "8ce469b8-aa29-4544-a8b4-c56183cbb882"  # MEGOMETRO 1000 · 18075400363
MEG_001      = "210b51e0-28b2-4a09-9ffc-c4ab779ecf05"  # MEGOMETRO 1000 NUEVO · 13105400132
PINZA_41130  = "51590fec-c6ef-4e38-8fa3-3b2527e4a52f"  # PINZA FLUKE · 41130648WS
PINZA_41411  = "a0304fdb-d74d-45a5-9ec4-569134b706e9"  # PINZA FLUKE · 41411026WS
PINZA_4699   = "7a5b21fb-854d-4b93-946d-a21054f952ac"  # PINZA FLUKE · 46995215SV
PINZA_KYO    = "649cb026-1dc5-49fe-af63-5d2d26ea44a3"  # PINZA KYORITSU · 8224265
CAM_FLUKE    = "501b0199-892f-47c5-8659-55fb023ec688"  # CAM TERMOGRAFICA FLUKE · Ti520-18041183
CAM_GUIDE    = "4d829736-a4a9-4bc4-9bfe-6c747df9abed"  # CAM TERMOGRAFICA GUIDE · 5200312000193A
TEL_001      = "02a8e9e3-4ca4-4471-89b9-c995131bc61b"  # TELUROMETRO · W8176876
TEL_002      = "b3f15c90-ad55-4126-9578-3a9894edf2d9"  # TELUROMETRO NUEVO · E8300035
MULTI_FLUKE  = "e009734d-ad9e-4364-a93a-fd16faab4e6a"  # MULTIMETRO FLUKE (por nombre; ver nota)
DETECTOR_AT  = "e23aa7a9-9357-4dc9-9a81-ccd013ede08c"  # DETECTOR ALTA TENSIÓN · 2010620
TORQUIMETRO  = "42fad54a-2fda-4a23-9a36-59ce14c2fa7b"  # TORQUIMETRO 1/4 TOOLTECH · E26-0505
GUANTES_004  = "c58b1d74-4539-491a-9e71-1d55fd4ee293"  # GUANTES · 80514391/80515982
GUANTES_SOF  = "cd040983-0f19-4345-b765-cb65c79f89a9"  # GUANTES SOFAMEL · E26-0885
MANTA_0883   = "dfd16756-be6a-457d-98e9-2765506e2ebb"  # MANTA SALISBURY · E26-0883
MANTA_0884   = "82565acf-6919-41a0-8a85-fc0be49b47a1"  # MANTA SALISBURY · E26-0884
MANTA_63001  = "95c145ad-00db-4576-bf33-44553ac30677"  # MANTA AMARILLA · 26063001
MANTA_63002  = "52b6e1ba-ff3e-4536-9142-41bf98f65f78"  # MANTA AMARILLA · 26063002
MANTA_CLASE2 = None  # serie 26063003 — no existe en inventario: se crea abajo

D = date.fromisoformat

# (prefijo_archivo | None, equipo, nro_certificado, fecha_realizada,
#  fecha_proxima, laboratorio, created_at_erp | None, nota_extra | None)
EVENTOS = [
    # ── Históricos 2023 (certificados UNI/otros hallados en el servidor) ──
    ("0066-2023 PINZA AMPERIMETRICA KYORITSU-E-SYSTEM PERU S.pdf", PINZA_KYO,
     "0066-2023", D("2023-03-22"), D("2024-03-21"), "UNI", None, None),
    ("0068-2023 PINZA AMPERIMETRICA FLUKE-e-system tic.pdf", PINZA_41411,
     "0068-2023", D("2023-03-22"), D("2024-03-21"), "UNI", None, None),
    ("0072-2023", TEL_002, "0072-2023", D("2023-03-27"), D("2024-03-26"), "UNI", None, None),
    ("0073-2023", PINZA_41130, "0073-2023", D("2023-03-27"), D("2024-03-26"), "UNI", None, None),
    ("231658", CAM_GUIDE, "231658", D("2023-04-13"), D("2024-04-13"), None, None,
     "Certificado externo sin laboratorio identificado en el registro del ERP."),
    ("0140-2023", MEG_001, "0140-2023", D("2023-09-12"), D("2024-09-11"), "UNI", None, None),
    # ── Históricos 2024 ──
    ("0052-2024", CAM_FLUKE, "0052-2024", D("2024-03-15"), D("2025-03-14"), "UNI", None, None),
    ("0054-2024", MEG_002, "0054-2024", D("2024-03-19"), D("2025-03-18"), "UNI", None, None),
    ("0055-2024", PINZA_4699, "0055-2024", D("2024-03-19"), D("2025-03-18"), "UNI", None, None),
    ("0074-2024", PINZA_41411, "0074-2024", D("2024-04-04"), D("2025-04-03"), "UNI", None, None),
    ("0080-2024", CAM_GUIDE, "0080-2024", D("2024-04-05"), D("2025-04-04"), "UNI", None, None),
    ("0094-2024", TEL_001, "0094-2024", D("2024-04-24"), D("2025-04-23"), "UNI", None, None),
    ("0095-2024", TEL_002, "0095-2024", D("2024-04-24"), D("2025-04-23"), "UNI", None, None),
    ("0096-2024", MULTI_FLUKE, "0096-2024", D("2024-04-25"), D("2025-04-24"), "UNI", None, None),
    ("EE-A-2946-2024", MEG_001, "EE-A-2946-2024", D("2024-09-14"), D("2025-09-14"), "INACAL", None, None),
    # ── Vigentes (tabla calibraciones del ERP) ──
    ("0097-2025", MULTI_FLUKE, "0097-2025", D("2025-05-09"), D("2026-05-08"), "UNI", "2024-04-23", None),
    ("EE-A-3481-2025", PINZA_4699, "EE-A-3481-2025", D("2025-10-21"), D("2026-10-21"), "INACAL", "2024-04-12", None),
    ("EE-A-3482-2025", TEL_002, "EE-A-3482-2025", D("2025-10-21"), D("2026-10-21"), "INACAL", "2024-02-05", None),
    ("EE-A-0146-2026-PINZA MULTIMETRICA.PDF", PINZA_KYO,
     "EE-A-0146-2026", D("2026-01-13"), D("2027-01-13"), "INACAL", "2024-04-11", None),
    ("EE-A-0147-2026", MEG_001, "EE-A-0147-2026", D("2026-01-13"), D("2027-01-13"), "INACAL", "2024-02-05", None),
    ("EE-A-1587-2026", MEG_002, "EE-A-1587-2026", D("2026-04-13"), D("2027-04-13"), "INACAL", "2024-02-05", None),
    ("EVD-1128-2026", DETECTOR_AT, "EVD-1128-2026", D("2026-04-13"), D("2027-04-13"), "INACAL", "2026-04-27", None),
    ("EF-0221-2026", TORQUIMETRO, "EF-0221-2026", D("2026-04-13"), D("2027-04-13"), "INACAL", "2026-04-27", None),
    ("EE-A-2025-2026", PINZA_41130, "EE-A-2025-2026", D("2026-05-07"), D("2027-05-06"), "INACAL", "2024-02-05", None),
    ("EE-A-2026-2026", PINZA_41411, "EE-A-2026-2026", D("2026-05-07"), D("2027-05-06"), "INACAL", "2024-02-05", None),
    ("ET-0446-2026", CAM_GUIDE, "ET-0446-2026", D("2026-05-07"), D("2027-05-06"), "INACAL", "2024-02-05", None),
    ("0070-2026", CAM_FLUKE, "0070-2026", D("2026-05-12"), D("2027-05-11"), "UNI", "2024-02-05", None),
    ("0071-2026", TEL_001, "0071-2026", D("2026-05-12"), D("2027-05-11"), "UNI", "2024-02-05", None),
    ("EVD-1718-2026", GUANTES_004, "EVD-1718-2026", D("2026-05-22"), D("2027-05-21"), "INACAL", "2026-05-13", None),
    ("260248-1", MANTA_63001, "260248-1", D("2026-06-05"), D("2027-06-04"), "LOGYTEC", "2026-06-08", None),
    ("260248-2", MANTA_63002, "260248-2", D("2026-06-05"), D("2027-05-04"), "LOGYTEC", "2026-06-08", None),
    ("260260-1", "MANTA_CLASE2", "260260-1", D("2026-06-16"), D("2027-06-15"), "LOGYTEC", "2026-06-18", None),
    ("EVD-2039-2026", MANTA_0883, "EVD-2039-2026", D("2026-06-17"), D("2027-06-16"), "INACAL", "2026-06-18", None),
    # PDF EVD-2040 NO estaba en el backup del servidor: evento sin certificado.
    (None, MANTA_0884, "EVD-2040-2026", D("2026-06-17"), D("2027-06-16"), "INACAL", "2026-06-18",
     "Certificado PDF no hallado en el backup del servidor (uploads/calibraciones)."),
    ("EVD-2041-2026", GUANTES_SOF, "EVD-2041-2026", D("2026-06-17"), D("2027-06-16"), "INACAL", "2026-06-18", None),
]


def _buscar_pdf(base: Path, prefijo: str) -> Path | None:
    cands = sorted(p for p in base.iterdir() if p.name.startswith(prefijo.split(".pdf")[0].split(".PDF")[0]))
    exactos = [p for p in cands if p.name == prefijo]
    return (exactos or cands or [None])[0]


def _crear_manta_clase2(db) -> str:
    """La manta clase 2 (serie 26063003) tiene certificado pero no existe en el
    inventario: se crea copiando la ficha de la manta amarilla 26063001."""
    existe = db.query(Equipo).filter(
        Equipo.empresa_id == EMPRESA_ID, Equipo.numero_serie == "26063003"
    ).first()
    if existe:
        return str(existe.id)
    ref = db.query(Equipo).filter(Equipo.id == MANTA_63001).first()
    nueva = Equipo(
        id=str(uuid.uuid4()),
        empresa_id=EMPRESA_ID,
        nombre="MANTA DIELECTRICA SALISBURY CLASE 2",
        numero_serie="26063003",
        clase=ref.clase if ref else "herramienta",
        estado="operativo",
        cantidad=1,
        tipo_equipo_id=(ref.tipo_equipo_id if ref else None),
        almacen_id=(ref.almacen_id if ref else None),
        tipo_asignacion=(ref.tipo_asignacion if ref else None),
        created_at=datetime(2026, 6, 18),
    )
    db.add(nueva)
    db.flush()
    print(f"  + equipo creado: MANTA DIELECTRICA SALISBURY CLASE 2 (26063003) → {nueva.id}")
    return str(nueva.id)


def _recalcular_snapshot(db, equipo_id: str) -> None:
    ultimo = (db.query(CalibracionEvento)
                .filter(CalibracionEvento.empresa_id == EMPRESA_ID,
                        CalibracionEvento.equipo_id == equipo_id)
                .order_by(CalibracionEvento.fecha_realizada.desc(),
                          CalibracionEvento.created_at.desc())
                .first())
    snap = (db.query(Calibracion)
              .filter(Calibracion.empresa_id == EMPRESA_ID,
                      Calibracion.equipo_id == equipo_id)
              .first())
    if not snap:
        snap = Calibracion(id=str(uuid.uuid4()), empresa_id=EMPRESA_ID, equipo_id=equipo_id)
        db.add(snap)
    if ultimo:
        snap.fecha_ultima = ultimo.fecha_realizada
        snap.fecha_proxima = ultimo.fecha_proxima
        snap.empresa_responsable = ultimo.empresa_responsable
        snap.certificado_url = ultimo.certificado_url


def main(carpeta: str) -> None:
    base = Path(carpeta)
    if not base.is_dir():
        print(f"ERROR: no existe {base}")
        sys.exit(1)

    db = SessionLocal()
    migrados = saltados = sin_pdf = 0
    equipos_tocados: set[str] = set()
    try:
        manta2_id = _crear_manta_clase2(db)

        for prefijo, equipo_id, nro, f_real, f_prox, lab, created, nota in EVENTOS:
            if equipo_id == "MANTA_CLASE2":
                equipo_id = manta2_id

            ya = db.query(CalibracionEvento).filter(
                CalibracionEvento.empresa_id == EMPRESA_ID,
                CalibracionEvento.equipo_id == equipo_id,
                CalibracionEvento.numero_certificado == nro,
            ).first()
            if ya:
                print(f"  = ya existe, salto: {nro}")
                saltados += 1
                continue

            url = None
            if prefijo:
                pdf = _buscar_pdf(base, prefijo)
                if pdf is None:
                    print(f"  ! PDF no encontrado para {nro} (prefijo {prefijo!r})")
                    sin_pdf += 1
                else:
                    b64 = base64.b64encode(pdf.read_bytes()).decode()
                    res = subir_archivo_base64(
                        b64, carpeta_calibracion(EMPRESA_ID, equipo_id),
                        f"cert_migr_{uuid.uuid4().hex[:12]}", extension="pdf",
                    )
                    url = res.get("secure_url")
            else:
                sin_pdf += 1

            obs = "Migrado del ERP legado (esystemtic_erp.calibraciones)."
            if nota:
                obs += " " + nota

            ev = CalibracionEvento(
                id=str(uuid.uuid4()),
                empresa_id=EMPRESA_ID,
                equipo_id=equipo_id,
                fecha_realizada=f_real,
                periodicidad_meses=12,
                fecha_proxima=f_prox,
                empresa_responsable=lab,
                numero_certificado=nro,
                certificado_url=url,
                observacion=obs,
                created_at=(datetime.fromisoformat(created) if created
                            else datetime.combine(f_real, datetime.min.time())),
            )
            db.add(ev)
            db.flush()
            equipos_tocados.add(equipo_id)
            registrar_evento(
                accion="CALIBRACION_IMPORT", empresa_id=EMPRESA_ID,
                usuario_nombre="Migración ERP",
                entidad="calibracion_evento", entidad_id=ev.id,
                detalle={"numero_certificado": nro, "equipo_id": equipo_id,
                         "fecha_realizada": f_real.isoformat(),
                         "origen": "erp_legacy", "con_pdf": bool(url)},
                db=db,
            )
            print(f"  + {nro}  ({'con' if url else 'SIN'} PDF)")
            migrados += 1

        for eq in equipos_tocados:
            _recalcular_snapshot(db, eq)
        db.commit()
    finally:
        db.close()

    print(f"\nResumen: {migrados} eventos migrados, {saltados} ya existían, "
          f"{sin_pdf} sin PDF, {len(equipos_tocados)} equipos con snapshot recalculado.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python -m migrations.migrate_calibraciones_erp <carpeta_con_pdfs>")
        sys.exit(1)
    main(sys.argv[1])
