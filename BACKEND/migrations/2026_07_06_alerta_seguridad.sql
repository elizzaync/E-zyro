-- Fase 2 — Alertas del monitoreo de seguridad (reglas sobre audit_log).
CREATE TABLE IF NOT EXISTS alerta_seguridad (
    id             VARCHAR(36) PRIMARY KEY,
    -- fuerza_bruta | denegados_repetidos | descarga_masiva | logins_fallidos_usuario
    tipo           VARCHAR(30),
    severidad      VARCHAR(10),                              -- baja|media|alta
    titulo         VARCHAR(200),
    detalle        JSONB,
    ip             VARCHAR(45),
    -- Sin FK a usuario (uuid nativo + rastro que sobrevive a borrados)
    usuario_id     VARCHAR(36),
    fecha          TIMESTAMP DEFAULT now(),
    estado         VARCHAR(10) DEFAULT 'abierta',            -- abierta|revisada
    revisada_por   VARCHAR(36),
    fecha_revision TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_alerta_seguridad_estado_fecha ON alerta_seguridad (estado, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_alerta_seguridad_tipo_fecha   ON alerta_seguridad (tipo, fecha DESC);

COMMENT ON TABLE alerta_seguridad IS 'Alertas generadas por el monitoreo de seguridad (job cada 5 min sobre audit_log). Notifican al rol Soporte.';
