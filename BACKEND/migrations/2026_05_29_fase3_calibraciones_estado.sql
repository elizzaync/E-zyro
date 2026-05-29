-- Fase 3 — Calibraciones + estado operativo de equipos + permisos RBAC. Idempotente.

CREATE TABLE IF NOT EXISTS calibracion (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    equipo_id uuid NOT NULL REFERENCES equipo(id),
    fecha_ultima DATE, fecha_proxima DATE, empresa_responsable VARCHAR(200),
    certificado_url TEXT, observacion VARCHAR(500),
    created_at TIMESTAMP NOT NULL DEFAULT now(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS equipo_estado_mov (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    equipo_id uuid NOT NULL REFERENCES equipo(id),
    accion VARCHAR(20) NOT NULL, cantidad INTEGER NOT NULL DEFAULT 1,
    motivo VARCHAR(300), fecha DATE NOT NULL DEFAULT current_date,
    registrado_por_id uuid, created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_equipo_estado_accion CHECK (accion IN ('inoperativo','reactivar'))
);
CREATE INDEX IF NOT EXISTS ix_calibracion_empresa_eq ON calibracion (empresa_id, equipo_id, fecha_proxima);
CREATE INDEX IF NOT EXISTS ix_equipo_estado_mov_eq ON equipo_estado_mov (empresa_id, equipo_id);

-- Estado operativo en equipo
ALTER TABLE equipo ADD COLUMN IF NOT EXISTS cantidad_inoperativa INTEGER NOT NULL DEFAULT 0;
ALTER TABLE equipo ADD COLUMN IF NOT EXISTS estado_operativo VARCHAR(20) DEFAULT 'operativo';
ALTER TABLE equipo DROP CONSTRAINT IF EXISTS chk_equipo_estado_op;
ALTER TABLE equipo ADD CONSTRAINT chk_equipo_estado_op CHECK (estado_operativo IN ('operativo','parcial','inoperativo'));

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'calibracion', 'ver', 'Calibración: ver'),
    (uuid_generate_v4(), 'calibracion', 'crear', 'Calibración: crear'),
    (uuid_generate_v4(), 'calibracion', 'editar', 'Calibración: editar'),
    (uuid_generate_v4(), 'calibracion', 'eliminar', 'Calibración: eliminar'),
    (uuid_generate_v4(), 'equipo', 'marcar_inoperativo', 'Equipo: marcar inoperativo'),
    (uuid_generate_v4(), 'equipo', 'reactivar', 'Equipo: reactivar'),
    (uuid_generate_v4(), 'equipo', 'ver_estado', 'Equipo: ver estado')
ON CONFLICT (modulo, accion) DO NOTHING;
