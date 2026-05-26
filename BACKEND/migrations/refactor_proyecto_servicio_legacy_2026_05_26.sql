-- ============================================================
-- Migración: refactor de proyecto_detalle ↔ proyecto_servicio
-- Fecha: 2026-05-26
-- Motivo: alinear el esquema con los datos legacy (tabla `servicios`):
--   * alcance, tipo_documento_cliente, nro_documento, nro_conformidad,
--     acta_url y zona_ejecucion eran por-servicio en el legacy.
--   * responsable_id pasa a apuntar a usuario(id) para mapear id_usuario.
-- ============================================================

BEGIN;

-- 1) Añadir nuevas columnas en proyecto_servicio --------------------------
ALTER TABLE proyecto_servicio
    ADD COLUMN IF NOT EXISTS zona_ejecucion         VARCHAR(255),
    ADD COLUMN IF NOT EXISTS alcance                TEXT,
    ADD COLUMN IF NOT EXISTS tipo_documento_cliente VARCHAR(20),
    ADD COLUMN IF NOT EXISTS nro_documento          VARCHAR(100),
    ADD COLUMN IF NOT EXISTS nro_conformidad        VARCHAR(100) DEFAULT 'En Espera',
    ADD COLUMN IF NOT EXISTS acta_url               VARCHAR(500),
    ADD COLUMN IF NOT EXISTS public_id_cloudinary   VARCHAR(255);

ALTER TABLE proyecto_servicio
    DROP CONSTRAINT IF EXISTS chk_ps_tipo_doc;
ALTER TABLE proyecto_servicio
    ADD CONSTRAINT chk_ps_tipo_doc
        CHECK (tipo_documento_cliente IS NULL OR tipo_documento_cliente IN ('OC','PROF','SIN_OC'));

-- 2) Copiar datos heredados desde proyecto_detalle al primer servicio ----
--    (solo si hay un único servicio, para no duplicar el alcance maestro)
UPDATE proyecto_servicio ps
SET
    zona_ejecucion         = COALESCE(ps.zona_ejecucion, pd.zona_ejecucion),
    alcance                = COALESCE(ps.alcance, pd.alcance),
    tipo_documento_cliente = COALESCE(ps.tipo_documento_cliente, pd.tipo_documento_cliente),
    nro_documento          = COALESCE(ps.nro_documento, pd.nro_documento),
    nro_conformidad        = COALESCE(ps.nro_conformidad, pd.nro_conformidad),
    acta_url               = COALESCE(ps.acta_url, pd.acta_url),
    public_id_cloudinary   = COALESCE(ps.public_id_cloudinary, pd.public_id_cloudinary)
FROM proyecto_detalle pd
WHERE pd.proyecto_id = ps.proyecto_id
  AND ps.orden = 1;

-- 3) Quitar columnas que ya no viven a nivel proyecto --------------------
ALTER TABLE proyecto_detalle
    DROP COLUMN IF EXISTS zona_ejecucion,
    DROP COLUMN IF EXISTS alcance,
    DROP COLUMN IF EXISTS tipo_documento_cliente,
    DROP COLUMN IF EXISTS nro_documento,
    DROP COLUMN IF EXISTS nro_conformidad,
    DROP COLUMN IF EXISTS acta_url,
    DROP COLUMN IF EXISTS public_id_cloudinary;

-- 4) FK responsable_id → usuario(id) (mapeo legacy id_usuario) -----------
ALTER TABLE proyecto_servicio
    DROP CONSTRAINT IF EXISTS fk_ps_responsable;
ALTER TABLE proyecto_servicio
    ADD CONSTRAINT fk_ps_responsable
        FOREIGN KEY (responsable_id) REFERENCES usuario(id);

-- 5) Índices para los nuevos campos críticos -----------------------------
CREATE INDEX IF NOT EXISTS idx_proyecto_servicio_doc
    ON proyecto_servicio(empresa_id, tipo_documento_cliente, nro_documento);
CREATE INDEX IF NOT EXISTS idx_proyecto_servicio_resp
    ON proyecto_servicio(responsable_id);

COMMIT;
