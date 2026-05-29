-- Fase 4 — Correctivos + Observaciones (descargos) + permisos RBAC. Idempotente.

CREATE TABLE IF NOT EXISTS servicio_correctivo (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    servicio_id uuid NOT NULL REFERENCES proyecto_servicio(id),
    codigo VARCHAR(30), alcance VARCHAR(500), fecha_inicio DATE, fecha_fin DATE,
    estado VARCHAR(20) NOT NULL DEFAULT 'registrado', informe_url TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(), updated_at TIMESTAMP,
    CONSTRAINT chk_correctivo_estado CHECK (estado IN
        ('registrado','en_proceso','en_revision','aprobado','desaprobado','finalizado','anulado'))
);
CREATE TABLE IF NOT EXISTS servicio_observacion (
    id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES empresa(id),
    servicio_id uuid NOT NULL REFERENCES proyecto_servicio(id),
    correctivo_id uuid REFERENCES servicio_correctivo(id),
    observaciones TEXT, recomendaciones TEXT,
    fecha_descargo DATE NOT NULL DEFAULT current_date, registrado_por_id uuid,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_correctivo_empresa_serv ON servicio_correctivo (empresa_id, servicio_id, estado);
CREATE INDEX IF NOT EXISTS ix_observacion_empresa_serv ON servicio_observacion (empresa_id, servicio_id);

INSERT INTO permiso (id, modulo, accion, descripcion) VALUES
    (uuid_generate_v4(), 'correctivo', 'ver', 'Correctivo: ver'),
    (uuid_generate_v4(), 'correctivo', 'crear', 'Correctivo: crear'),
    (uuid_generate_v4(), 'correctivo', 'editar', 'Correctivo: editar'),
    (uuid_generate_v4(), 'correctivo', 'aprobar', 'Correctivo: aprobar/transicionar'),
    (uuid_generate_v4(), 'correctivo', 'finalizar', 'Correctivo: finalizar'),
    (uuid_generate_v4(), 'observacion', 'ver', 'Observación: ver'),
    (uuid_generate_v4(), 'observacion', 'crear', 'Observación: crear'),
    (uuid_generate_v4(), 'observacion', 'editar', 'Observación: editar'),
    (uuid_generate_v4(), 'observacion', 'eliminar', 'Observación: eliminar')
ON CONFLICT (modulo, accion) DO NOTHING;
