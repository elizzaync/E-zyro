-- Fase 2 — EPP (catálogo + entregas + ingresos) + permisos RBAC 'epp'. Idempotente.

CREATE TABLE IF NOT EXISTS epp (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    nombre VARCHAR(200) NOT NULL, descripcion VARCHAR(500),
    marca_id uuid REFERENCES marca(id), unidad_id uuid REFERENCES unidad_medida(id),
    zona_id uuid REFERENCES zona(id),
    stock_actual INTEGER NOT NULL DEFAULT 0, stock_min INTEGER NOT NULL DEFAULT 0,
    precio NUMERIC(12,2), imagen_url TEXT, activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT now(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS epp_entrega (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    empleado_id uuid NOT NULL REFERENCES empleado(id), fecha DATE NOT NULL DEFAULT current_date,
    registrado_por_id uuid REFERENCES empleado(id), firma_url TEXT, pdf_url TEXT,
    observacion VARCHAR(500), estado VARCHAR(20) NOT NULL DEFAULT 'registrada',
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_epp_entrega_estado CHECK (estado IN ('registrada','anulada'))
);
CREATE TABLE IF NOT EXISTS epp_entrega_detalle (
    id uuid PRIMARY KEY, entrega_id uuid NOT NULL REFERENCES epp_entrega(id),
    epp_id uuid NOT NULL REFERENCES epp(id), cantidad INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS epp_ingreso (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    personal_compro_id uuid REFERENCES empleado(id), proveedor_id uuid REFERENCES proveedor(id),
    fecha_compra DATE NOT NULL DEFAULT current_date, registrado_por_id uuid REFERENCES empleado(id),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS epp_ingreso_detalle (
    id uuid PRIMARY KEY, ingreso_id uuid NOT NULL REFERENCES epp_ingreso(id),
    epp_id uuid NOT NULL REFERENCES epp(id), cantidad INTEGER NOT NULL DEFAULT 1,
    precio_unitario NUMERIC(12,2)
);
CREATE INDEX IF NOT EXISTS ix_epp_empresa ON epp (empresa_id);
CREATE INDEX IF NOT EXISTS ix_epp_entrega_empresa ON epp_entrega (empresa_id, empleado_id);
CREATE INDEX IF NOT EXISTS ix_epp_entrega_det ON epp_entrega_detalle (entrega_id);
CREATE INDEX IF NOT EXISTS ix_epp_ingreso_det ON epp_ingreso_detalle (ingreso_id);

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'epp', 'ver', 'EPP: ver'),
    (uuid_generate_v4(), 'epp', 'crear', 'EPP: crear'),
    (uuid_generate_v4(), 'epp', 'editar', 'EPP: editar'),
    (uuid_generate_v4(), 'epp', 'entregar', 'EPP: entregar'),
    (uuid_generate_v4(), 'epp', 'ingresar', 'EPP: ingresar'),
    (uuid_generate_v4(), 'epp', 'eliminar', 'EPP: eliminar')
ON CONFLICT (modulo, accion) DO NOTHING;
