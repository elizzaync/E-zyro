-- Fase 1 — Audit log de EVENTOS HTTP/seguridad (login, descargas, denegados…).
-- Los cambios de datos CRUD ya los cubre el listener ORM sobre `auditoria`;
-- esta tabla registra eventos que el ORM no ve (auth, descargas, 403, rate limit).
CREATE TABLE IF NOT EXISTS audit_log (
    id             VARCHAR(36) PRIMARY KEY,
    fecha          TIMESTAMP    NOT NULL DEFAULT now(),
    -- Sin FK a usuario: usuario.id es uuid nativo (FK varchar→uuid falla) y el
    -- rastro de auditoría debe sobrevivir aunque el usuario se elimine.
    usuario_id     VARCHAR(36),
    usuario_nombre VARCHAR(150),
    rol            VARCHAR(50),
    empresa_id     VARCHAR(36),
    -- LOGIN | LOGIN_FALLIDO | LOGOUT | DOWNLOAD | EXPORT | PERMISSION_DENIED
    -- | RATE_LIMITED | BACKUP | SECURITY | VIEW_SENSITIVE
    accion         VARCHAR(30)  NOT NULL,
    entidad        VARCHAR(60),
    entidad_id     VARCHAR(64),
    metodo_http    VARCHAR(8),
    ruta           VARCHAR(300),
    ip             VARCHAR(45),
    user_agent     VARCHAR(255),
    resultado      VARCHAR(10)  NOT NULL DEFAULT 'exito',   -- exito|fallo|denegado
    detalle        JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_log_fecha          ON audit_log (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_accion_fecha   ON audit_log (accion, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_usuario_fecha  ON audit_log (usuario_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_ip_fecha       ON audit_log (ip, fecha DESC);

COMMENT ON TABLE audit_log IS 'Eventos HTTP/seguridad (Gestión de TIC). Los CRUD viven en auditoria (listener ORM); aquí van login, descargas, permisos denegados, rate limit, backups y alertas.';
