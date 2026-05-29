-- Fase 1 — Galería Global: índice recurso_cloudinary + permisos RBAC 'galeria'
-- Idempotente. Espejo de _pre_create_migrations() y _run_migrations() en main.py.

CREATE TABLE IF NOT EXISTS recurso_cloudinary (
    id            uuid PRIMARY KEY,
    empresa_id    uuid NOT NULL REFERENCES empresa(id),
    public_id     VARCHAR(300) NOT NULL,
    secure_url    TEXT NOT NULL,
    folder        VARCHAR(300),
    recurso_tipo  VARCHAR(20) NOT NULL DEFAULT 'imagen',
    entidad_tipo  VARCHAR(40) NOT NULL,
    entidad_id    uuid,
    descripcion   VARCHAR(300),
    bytes         INTEGER,
    formato       VARCHAR(10),
    creado_por_id uuid,
    created_at    TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_recurso_tipo CHECK (recurso_tipo IN ('imagen','pdf','raw','video'))
);

CREATE INDEX IF NOT EXISTS ix_recurso_empresa_entidad
    ON recurso_cloudinary (empresa_id, entidad_tipo, entidad_id);
CREATE INDEX IF NOT EXISTS ix_recurso_empresa_fecha
    ON recurso_cloudinary (empresa_id, created_at);

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'galeria', 'ver',      'Galería global: ver'),
    (uuid_generate_v4(), 'galeria', 'subir',    'Galería global: subir'),
    (uuid_generate_v4(), 'galeria', 'eliminar', 'Galería global: eliminar')
ON CONFLICT (modulo, accion) DO NOTHING;
