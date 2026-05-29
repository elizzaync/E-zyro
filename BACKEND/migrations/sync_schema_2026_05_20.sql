-- ============================================================
-- MIGRACIÓN DE SINCRONIZACIÓN - 2026-05-20
-- Aplica todas las columnas y tablas nuevas que existen en los
-- modelos Python pero NO estaban en el esquema original bd.txt.
-- Es idempotente: usa IF NOT EXISTS / IF EXISTS en cada paso.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. sesion_usuario — columna fecha_cierre
-- ──────────────────────────────────────────────────────────────
ALTER TABLE sesion_usuario
    ADD COLUMN IF NOT EXISTS fecha_cierre TIMESTAMP;

-- ──────────────────────────────────────────────────────────────
-- 2. solicitud_laboral — url y public_id del PDF
-- ──────────────────────────────────────────────────────────────
ALTER TABLE solicitud_laboral
    ADD COLUMN IF NOT EXISTS url_pdf       VARCHAR(500),
    ADD COLUMN IF NOT EXISTS public_id_pdf VARCHAR(255);

-- ──────────────────────────────────────────────────────────────
-- 3. registro_asistencia — uuid_cliente para idempotencia offline
-- ──────────────────────────────────────────────────────────────
ALTER TABLE registro_asistencia
    ADD COLUMN IF NOT EXISTS uuid_cliente VARCHAR(36);

-- Unique constraint (por si no existe aún)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_asistencia_empresa_uuid_cliente'
    ) THEN
        ALTER TABLE registro_asistencia
            ADD CONSTRAINT uq_asistencia_empresa_uuid_cliente
            UNIQUE (empresa_id, uuid_cliente);
    END IF;
END$$;

-- ──────────────────────────────────────────────────────────────
-- 4. mensaje_chat — sala por servicio y mensajes directos
-- ──────────────────────────────────────────────────────────────
ALTER TABLE mensaje_chat
    ADD COLUMN IF NOT EXISTS proyecto_servicio_id UUID,
    ADD COLUMN IF NOT EXISTS destinatario_id      UUID;

-- FKs opcionales (no bloquean si ya existen)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_mc_ps'
    ) THEN
        ALTER TABLE mensaje_chat
            ADD CONSTRAINT fk_mc_ps
            FOREIGN KEY (proyecto_servicio_id) REFERENCES proyecto_servicio(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_mc_destinatario'
    ) THEN
        ALTER TABLE mensaje_chat
            ADD CONSTRAINT fk_mc_destinatario
            FOREIGN KEY (destinatario_id) REFERENCES usuario(id);
    END IF;
END$$;

-- ──────────────────────────────────────────────────────────────
-- 5. requerimiento — observacion_logistico + estado 'borrador'
-- ──────────────────────────────────────────────────────────────
ALTER TABLE requerimiento
    ADD COLUMN IF NOT EXISTS observacion_logistico VARCHAR(500);

-- Ampliar el CHECK de estado al set completo del modelo híbrido
-- (incluye 'borrador', 'comprando' y 'listo')
ALTER TABLE requerimiento DROP CONSTRAINT IF EXISTS chk_req_estado;
ALTER TABLE requerimiento
    ADD CONSTRAINT chk_req_estado
    CHECK (estado IN ('borrador','pendiente','comprando','listo','aprobado','rechazado','entregado','anulado'));

-- ──────────────────────────────────────────────────────────────
-- 6. requerimiento_detalle — material_id nullable + campos nuevos
-- ──────────────────────────────────────────────────────────────
ALTER TABLE requerimiento_detalle
    ALTER COLUMN material_id DROP NOT NULL;

ALTER TABLE requerimiento_detalle
    ADD COLUMN IF NOT EXISTS nombre_libre     VARCHAR(255),
    ADD COLUMN IF NOT EXISTS unidad_libre     VARCHAR(50),
    ADD COLUMN IF NOT EXISTS especificacion   VARCHAR(500),
    ADD COLUMN IF NOT EXISTS agregado_por_id  VARCHAR(36);

-- ──────────────────────────────────────────────────────────────
-- 7. NUEVAS TABLAS: comunicado_proyecto + comunicado_leido
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comunicado_proyecto (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id        UUID         NOT NULL,
    proyecto_id       UUID         NOT NULL,
    autor_id          UUID,
    titulo            VARCHAR(200) NOT NULL,
    mensaje           TEXT         NOT NULL,
    adjunto_url       VARCHAR(500),
    adjunto_public_id VARCHAR(255),
    created_at        TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_com_empresa  FOREIGN KEY (empresa_id)  REFERENCES empresa(id),
    CONSTRAINT fk_com_proyecto FOREIGN KEY (proyecto_id) REFERENCES proyecto(id),
    CONSTRAINT fk_com_autor    FOREIGN KEY (autor_id)    REFERENCES empleado(id)
);

CREATE TABLE IF NOT EXISTS comunicado_leido (
    comunicado_id UUID      NOT NULL,
    empleado_id   UUID      NOT NULL,
    leido_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comunicado_id, empleado_id),
    CONSTRAINT fk_cl_comunicado FOREIGN KEY (comunicado_id) REFERENCES comunicado_proyecto(id) ON DELETE CASCADE,
    CONSTRAINT fk_cl_empleado   FOREIGN KEY (empleado_id)   REFERENCES empleado(id)
);

-- ──────────────────────────────────────────────────────────────
-- 8. Índices nuevos
-- ──────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_requerimiento_ps
    ON requerimiento(proyecto_servicio_id);

CREATE INDEX IF NOT EXISTS idx_requerimiento_detalle_req
    ON requerimiento_detalle(requerimiento_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_asistencia_uuid_cliente
    ON registro_asistencia(empresa_id, uuid_cliente)
    WHERE uuid_cliente IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mensaje_chat_ps
    ON mensaje_chat(proyecto_servicio_id, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_comunicado_proyecto
    ON comunicado_proyecto(proyecto_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comunicado_leido_emp
    ON comunicado_leido(empleado_id);

COMMIT;
