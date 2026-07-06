-- Fase 3 — Archivo centralizado de documentos generados (con deduplicación).
-- `identidad` es la identidad lógica del documento = public_id determinístico
-- en Cloudinary ("e-zyro/{empresa_id}/archivo/{modulo}/{slug}"): mismo reporte
-- + mismos parámetros → misma fila (re-descarga cuenta, hash igual no re-sube;
-- hash distinto sobrescribe el MISMO public_id y sube version).
CREATE TABLE IF NOT EXISTS documento_archivo (
    id                  VARCHAR(36)  PRIMARY KEY,
    nombre              VARCHAR(200) NOT NULL,
    tipo                VARCHAR(20),                          -- pdf|excel|csv|export|otro
    modulo_origen       VARCHAR(50),
    entidad_tipo        VARCHAR(60),
    entidad_id          VARCHAR(64),
    identidad           VARCHAR(300) NOT NULL UNIQUE,
    -- Sin FK a usuario (uuid nativo + el archivo sobrevive a borrados)
    generado_por        VARCHAR(36),
    empresa_id          VARCHAR(36),
    fecha_creacion      TIMESTAMP DEFAULT now(),
    fecha_actualizacion TIMESTAMP,
    tamano_bytes        BIGINT,
    hash_sha256         VARCHAR(64),
    cloudinary_public_id VARCHAR(300),
    cloudinary_url      TEXT,
    version             INT DEFAULT 1,
    descargas           INT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_documento_archivo_modulo_fecha ON documento_archivo (modulo_origen, fecha_creacion DESC);
CREATE INDEX IF NOT EXISTS idx_documento_archivo_tipo         ON documento_archivo (tipo);

COMMENT ON TABLE documento_archivo IS 'Archivo centralizado de documentos generados (PDF/Excel/CSV). Deduplicación por identidad + hash SHA-256; el binario vive en Cloudinary (raw).';
