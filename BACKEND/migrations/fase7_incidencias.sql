-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 7: Módulo de Incidencias de Equipos y Herramientas
-- Registra daños/fallos. La resolución impacta equipo.estado y equipo.cantidad.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS incidencia (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id           UUID NOT NULL REFERENCES empresa(id),
    equipo_id            UUID NOT NULL REFERENCES equipo(id),
    proyecto_servicio_id UUID REFERENCES proyecto_servicio(id),
    reportado_por_id     UUID REFERENCES empleado(id),
    resuelto_por_id      UUID REFERENCES empleado(id),

    -- Diferenciación equipo (nro serie) vs herramienta (cantidad)
    numero_serie         VARCHAR,          -- copiado del equipo al reportar
    cantidad_afectada    INTEGER NOT NULL DEFAULT 1,

    -- Descripción del problema
    tipo_falla           VARCHAR NOT NULL DEFAULT 'otro',
    -- 'no_enciende' | 'dano_fisico' | 'desgaste' | 'perdida' | 'otro'
    descripcion          TEXT NOT NULL,

    -- Estado de la incidencia
    estado               VARCHAR NOT NULL DEFAULT 'abierta',
    -- 'abierta' | 'en_reparacion' | 'solucionado' | 'dado_de_baja'
    resolucion_nota      TEXT,

    fecha_reporte        TIMESTAMP NOT NULL DEFAULT now(),
    fecha_resolucion     TIMESTAMP,
    created_at           TIMESTAMP NOT NULL DEFAULT now(),
    updated_at           TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_incidencia_empresa  ON incidencia(empresa_id);
CREATE INDEX IF NOT EXISTS idx_incidencia_equipo   ON incidencia(equipo_id);
CREATE INDEX IF NOT EXISTS idx_incidencia_servicio ON incidencia(proyecto_servicio_id);
CREATE INDEX IF NOT EXISTS idx_incidencia_estado   ON incidencia(estado);
