-- ============================================================
-- MIGRACION: Motor de Inspeccion de Equipos Intervenidos
-- Fecha:     2026-06-03
-- ============================================================

-- 1. Tabla equipo_intervenido
CREATE TABLE IF NOT EXISTS equipo_intervenido (
    id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_servicio_id UUID          NOT NULL REFERENCES proyecto_servicio(id),
    equipo_id            UUID          NOT NULL REFERENCES equipo(id),
    empresa_id           UUID          NOT NULL REFERENCES empresa(id),
    estado_intervencion  VARCHAR(20)   NOT NULL DEFAULT 'pendiente',
    observaciones        TEXT,
    created_at           TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP,
    CONSTRAINT uq_ei_servicio_equipo UNIQUE (proyecto_servicio_id, equipo_id)
);

-- 2. Tabla paso_intervencion
CREATE TABLE IF NOT EXISTS paso_intervencion (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    equipo_intervenido_id UUID         NOT NULL REFERENCES equipo_intervenido(id) ON DELETE CASCADE,
    empresa_id            UUID         NOT NULL REFERENCES empresa(id),
    nombre                VARCHAR(200) NOT NULL,
    descripcion           TEXT,
    orden                 INTEGER      NOT NULL DEFAULT 1,
    completado            BOOLEAN      NOT NULL DEFAULT FALSE,
    foto_url              VARCHAR(500),
    foto_public_id        VARCHAR(255),
    created_at            TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- 3. Indices
CREATE INDEX IF NOT EXISTS idx_ei_servicio ON equipo_intervenido(proyecto_servicio_id);
CREATE INDEX IF NOT EXISTS idx_ei_equipo   ON equipo_intervenido(equipo_id);
CREATE INDEX IF NOT EXISTS idx_pi_ei       ON paso_intervencion(equipo_intervenido_id);
