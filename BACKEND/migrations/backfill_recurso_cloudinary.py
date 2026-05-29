"""
Backfill idempotente: re-indexa en `recurso_cloudinary` los assets ya subidos a
Cloudinary que viven en columnas (url + public_id) de otras tablas.

- NO mueve ni re-sube nada en la nube; solo crea filas de índice para que la
  Galería Global muestre lo histórico.
- Idempotente: salta los public_id ya indexados (NOT EXISTS).
- Solo cubre tablas con `empresa_id` directo y par (url, public_id). `foto_asistencia`
  no tiene empresa_id directo → se omite (resolver vía join en una mejora futura).

Uso (one-shot manual, NO corre en el lifespan):
    DATABASE_URL=postgresql://... python migrations/backfill_recurso_cloudinary.py
"""
import os
import sys
import psycopg2

# (tabla, columna_url, columna_public_id, entidad_tipo, recurso_tipo, columna_id)
MAP = [
    ("adjunto_mensaje",        "url_cloudinary",     "public_id_cloudinary", "mensaje",              "raw",    "id"),
    ("comunicado_proyecto",    "adjunto_url",        "adjunto_public_id",    "comunicado",           "raw",    "id"),
    ("contrato",               "documento_url",      "public_id_cloudinary", "contrato",             "pdf",    "id"),
    ("contrato_comercial",     "documento_url",      "public_id_cloudinary", "contrato_comercial",   "pdf",    "id"),
    ("documento_laboral",      "url_archivo",        "public_id_cloudinary", "documento_laboral",    "pdf",    "id"),
    ("evidencia_mantenimiento","url_cloudinary",     "public_id_cloudinary", "mantenimiento",        "imagen", "id"),
    ("evidencia_procedimiento","url_cloudinary",     "public_id_cloudinary", "evidencia_procedimiento","imagen","id"),
    ("firma_digital",          "url_cloudinary",     "public_id_cloudinary", "firma",                "imagen", "id"),
    ("foto_biometrica",        "url_cloudinary",     "public_id_cloudinary", "biometrico",           "imagen", "id"),
    ("historial_firma",        "url_cloudinary",     "public_id_cloudinary", "firma",                "imagen", "id"),
    ("informe_tecnico",        "url_archivo",        "public_id_cloudinary", "informe",              "pdf",    "id"),
    ("movimiento_caja",        "comprobante_url",    "public_id_cloudinary", "caja",                 "imagen", "id"),
    ("proyecto_detalle",       "acta_url",           "public_id_cloudinary", "proyecto",             "pdf",    "proyecto_id"),
    ("proyecto_servicio",      "acta_url",           "public_id_cloudinary", "servicio",             "pdf",    "id"),
    ("requerimiento_entrega",  "firma_receptor_url", "firma_public_id",      "requerimiento_entrega","imagen", "id"),
    ("solicitud_laboral",      "url_pdf",            "public_id_pdf",        "solicitud_laboral",    "pdf",    "id"),
    ("version_plano",          "url_cloudinary",     "public_id_cloudinary", "plano",                "imagen", "id"),
]


def backfill(dsn: str) -> None:
    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    cur = conn.cursor()
    total = 0
    for tabla, url_col, pid_col, etipo, rtipo, id_col in MAP:
        sql = f"""
            INSERT INTO recurso_cloudinary
                (id, empresa_id, public_id, secure_url, folder, recurso_tipo, entidad_tipo, entidad_id, created_at)
            SELECT uuid_generate_v4(), t.empresa_id, t.{pid_col}, t.{url_col}, NULL, %s, %s, t.{id_col}, now()
            FROM {tabla} t
            WHERE t.{url_col} IS NOT NULL AND t.{pid_col} IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM recurso_cloudinary rc WHERE rc.public_id = t.{pid_col}
              )
        """
        try:
            cur.execute(sql, (rtipo, etipo))
            n = cur.rowcount
            total += max(n, 0)
            print(f"  {tabla:28} -> +{n} indexados (entidad_tipo='{etipo}')")
        except Exception as e:
            print(f"  {tabla:28} -> ERROR: {e}")
    print(f"TOTAL_INDEXADO = {total}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    dsn = os.getenv("DATABASE_URL")
    if not dsn:
        print("Falta DATABASE_URL en el entorno.", file=sys.stderr)
        sys.exit(1)
    backfill(dsn)
