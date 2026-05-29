-- Fase 5 — Inspección ITSE (inspección + tableros + ítems) + permisos RBAC. Idempotente.

CREATE TABLE IF NOT EXISTS inspeccion_itse (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    cliente_id uuid REFERENCES cliente(id), ubicacion_id uuid REFERENCES ubicacion(id),
    zona_id uuid REFERENCES zona(id), modo VARCHAR(20) NOT NULL DEFAULT 'tablero',
    fecha DATE NOT NULL DEFAULT current_date, estado VARCHAR(20) NOT NULL DEFAULT 'borrador',
    pdf_url TEXT, observaciones TEXT, registrado_por_id uuid,
    created_at TIMESTAMP NOT NULL DEFAULT now(), updated_at TIMESTAMP,
    CONSTRAINT chk_itse_modo CHECK (modo IN ('tablero','zona')),
    CONSTRAINT chk_itse_estado CHECK (estado IN ('borrador','en_proceso','finalizada','anulada'))
);
CREATE TABLE IF NOT EXISTS inspeccion_tablero (
    id uuid PRIMARY KEY, inspeccion_id uuid NOT NULL REFERENCES inspeccion_itse(id),
    nombre VARCHAR(200) NOT NULL, ambiente VARCHAR(200), descripcion VARCHAR(500),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS inspeccion_item (
    id uuid PRIMARY KEY, inspeccion_id uuid NOT NULL REFERENCES inspeccion_itse(id),
    tablero_id uuid REFERENCES inspeccion_tablero(id),
    descripcion VARCHAR(500) NOT NULL, resultado VARCHAR(20) NOT NULL DEFAULT 'conforme',
    observacion VARCHAR(500), created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_itse_item_resultado CHECK (resultado IN ('conforme','observado','no_conforme'))
);
CREATE INDEX IF NOT EXISTS ix_itse_empresa ON inspeccion_itse (empresa_id, estado);
CREATE INDEX IF NOT EXISTS ix_itse_tablero ON inspeccion_tablero (inspeccion_id);
CREATE INDEX IF NOT EXISTS ix_itse_item ON inspeccion_item (inspeccion_id);

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'itse', 'ver', 'ITSE: ver'),
    (uuid_generate_v4(), 'itse', 'crear', 'ITSE: crear'),
    (uuid_generate_v4(), 'itse', 'editar', 'ITSE: editar'),
    (uuid_generate_v4(), 'itse', 'finalizar', 'ITSE: finalizar'),
    (uuid_generate_v4(), 'itse', 'eliminar', 'ITSE: eliminar')
ON CONFLICT (modulo, accion) DO NOTHING;
