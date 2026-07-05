-- Módulo Backups (Gestión de TIC): auditoría de cada corrida de backup.
CREATE TABLE IF NOT EXISTS backup_job (
    id            VARCHAR(36) PRIMARY KEY,
    tipo          VARCHAR(10) NOT NULL,                       -- auto | manual
    nivel         VARCHAR(25) NOT NULL,                       -- bd_horario | bd_diario | archivos_incremental | archivos_full | reconciliacion
    -- Sin FK: usuario.id es uuid nativo y esta tabla es de auditoría pura
    -- (el rastro debe sobrevivir incluso si el usuario se elimina).
    disparado_por VARCHAR(36),                                -- usuario.id | NULL = sistema
    fecha_inicio  TIMESTAMP   NOT NULL DEFAULT now(),
    fecha_fin     TIMESTAMP,
    estado        VARCHAR(12) NOT NULL DEFAULT 'pendiente',   -- pendiente|en_proceso|completado|fallido
    contenido     VARCHAR(60) NOT NULL,                       -- csv: bd,pdfs,cloudinary
    tamano_bytes  BIGINT,
    ubicacion     TEXT,
    hash_sha256   VARCHAR(64),
    error_detalle TEXT,
    retencion     VARCHAR(10),                                -- horario|diario|semanal|mensual
    expira_en     DATE
);

CREATE INDEX IF NOT EXISTS idx_backup_job_estado_fecha ON backup_job (estado, fecha_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_backup_job_expira ON backup_job (expira_en) WHERE expira_en IS NOT NULL;

COMMENT ON TABLE backup_job IS 'Auditoría de backups del sistema (BD + archivos Cloudinary). El artefacto vive en BACKUP_DIR; la copia fría la descarga Soporte.';
