-- Refinamiento — Informes de servicio (pre-informe / informe final) + permisos. Idempotente.

CREATE TABLE IF NOT EXISTS informe_servicio (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    servicio_id uuid NOT NULL REFERENCES proyecto_servicio(id),
    tipo VARCHAR(10) NOT NULL DEFAULT 'pre', titulo VARCHAR(200),
    url TEXT, public_id VARCHAR(300), generado_por_id uuid,
    fecha DATE NOT NULL DEFAULT current_date, created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_informe_servicio_tipo CHECK (tipo IN ('pre','final'))
);
CREATE INDEX IF NOT EXISTS ix_informe_servicio ON informe_servicio (empresa_id, servicio_id, tipo);

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'informe_servicio', 'ver', 'Informe de servicio: ver'),
    (uuid_generate_v4(), 'informe_servicio', 'generar', 'Informe de servicio: generar')
ON CONFLICT (modulo, accion) DO NOTHING;
