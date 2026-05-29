-- Fase 0 — Catálogos base (Ubicación, Zona, Área) + permisos RBAC del módulo 'catalogos'
-- Idempotente. Espejo de lo que aplican _pre_create_migrations() y _run_migrations() en main.py.

-- ── Tablas (FK uuid a empresa) ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ubicacion (
    id          uuid PRIMARY KEY,
    empresa_id  uuid NOT NULL REFERENCES empresa(id),
    nombre      VARCHAR(150) NOT NULL,
    region      VARCHAR(100),
    created_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS zona (
    id           uuid PRIMARY KEY,
    empresa_id   uuid NOT NULL REFERENCES empresa(id),
    ubicacion_id uuid REFERENCES ubicacion(id),
    nombre       VARCHAR(150) NOT NULL,
    tipo         VARCHAR(50),
    created_at   TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS area (
    id          uuid PRIMARY KEY,
    empresa_id  uuid NOT NULL REFERENCES empresa(id),
    nombre      VARCHAR(150) NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT now()
);

-- ── Índices únicos (case-insensitive por empresa) ────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_ubicacion_empresa_nombre
    ON ubicacion (empresa_id, lower(nombre));
CREATE UNIQUE INDEX IF NOT EXISTS uq_zona_empresa_ubic_nombre
    ON zona (empresa_id, coalesce(ubicacion_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(nombre));
CREATE UNIQUE INDEX IF NOT EXISTS uq_area_empresa_nombre
    ON area (empresa_id, lower(nombre));

-- ── Permisos RBAC del módulo 'catalogos' (catálogo global, (modulo,accion) único) ──
INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'catalogos', 'ver',      'Catálogos base: ver'),
    (uuid_generate_v4(), 'catalogos', 'crear',    'Catálogos base: crear'),
    (uuid_generate_v4(), 'catalogos', 'editar',   'Catálogos base: editar'),
    (uuid_generate_v4(), 'catalogos', 'eliminar', 'Catálogos base: eliminar')
ON CONFLICT (modulo, accion) DO NOTHING;
