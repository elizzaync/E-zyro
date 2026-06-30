-- Procedimientos estándar por tipo de servicio: convertir el vínculo
-- plantilla_procedimiento ↔ catalogo_servicio de "string libre tipo_trabajo,
-- case-sensitive" a una FK real, para que dejen de desincronizarse por typos
-- o diferencias de mayúsculas (causaban que crear_servicio quedara SIN
-- procedimientos instanciados, en silencio).
--
-- Tabla viva → ALTER manual (create_all no altera columnas existentes).
-- Tipo uuid nativo para empatar con la PK uuid de catalogo_servicio.
--
-- Correr con:  railway run -s Postgres-SjrN psql "$DATABASE_PUBLIC_URL" -f migrations/2026_06_30_plantilla_catalogo_id.sql

ALTER TABLE plantilla_procedimiento
    ADD COLUMN IF NOT EXISTS catalogo_servicio_id uuid
    REFERENCES catalogo_servicio(id);

CREATE INDEX IF NOT EXISTS ix_plantilla_procedimiento_catalogo
    ON plantilla_procedimiento (catalogo_servicio_id);

-- Backfill: enlaza las plantillas existentes con su catálogo por coincidencia
-- de tipo_trabajo (misma empresa, comparación insensible a mayúsculas/espacios).
-- Si hay más de un catálogo con el mismo tipo_trabajo en la empresa, se enlaza
-- con el primero (orden por created_at) — caso borde, revisar manualmente si
-- aplica en esta empresa.
UPDATE plantilla_procedimiento pp
SET catalogo_servicio_id = cs.id
FROM (
    SELECT DISTINCT ON (empresa_id, lower(trim(tipo_trabajo)))
        id, empresa_id, tipo_trabajo
    FROM catalogo_servicio
    WHERE activo = true
    ORDER BY empresa_id, lower(trim(tipo_trabajo)), created_at ASC
) cs
WHERE pp.catalogo_servicio_id IS NULL
  AND pp.empresa_id = cs.empresa_id
  AND lower(trim(pp.tipo_trabajo)) = lower(trim(cs.tipo_trabajo));
