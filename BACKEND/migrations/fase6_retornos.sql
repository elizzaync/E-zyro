-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 6: Módulo de Retornos
-- Registra la devolución de materiales/equipos/herramientas al finalizar
-- un servicio. Flujo: técnico declara → logística inspecciona → completa.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS retorno (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id           UUID NOT NULL REFERENCES empresa(id),
    proyecto_servicio_id UUID REFERENCES proyecto_servicio(id),
    requerimiento_id     UUID REFERENCES requerimiento(id),
    estado               VARCHAR NOT NULL DEFAULT 'enviado',
    -- 'enviado' | 'inspeccion' | 'completado'
    iniciado_por_id      UUID REFERENCES empleado(id),
    inspeccionado_por_id UUID REFERENCES empleado(id),
    nota_tecnico         TEXT,
    nota_logistica       TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT now(),
    updated_at           TIMESTAMP,
    completado_en        TIMESTAMP
);

CREATE TABLE IF NOT EXISTS retorno_detalle (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    retorno_id          UUID NOT NULL REFERENCES retorno(id) ON DELETE CASCADE,
    material_id         UUID REFERENCES material(id),
    equipo_id           UUID REFERENCES equipo(id),
    nombre              VARCHAR NOT NULL,
    unidad              VARCHAR DEFAULT 'Unidades',
    tipo_item           VARCHAR NOT NULL DEFAULT 'material',
    cantidad_entregada  INTEGER NOT NULL DEFAULT 0,
    cantidad_retornada  INTEGER,
    cantidad_confirmada INTEGER,
    es_obligatorio      BOOLEAN NOT NULL DEFAULT false,
    estado_item         VARCHAR NOT NULL DEFAULT 'pendiente'
    -- 'pendiente' | 'confirmado' | 'faltante'
);

CREATE INDEX IF NOT EXISTS idx_retorno_empresa   ON retorno(empresa_id);
CREATE INDEX IF NOT EXISTS idx_retorno_servicio  ON retorno(proyecto_servicio_id);
CREATE INDEX IF NOT EXISTS idx_retorno_req       ON retorno(requerimiento_id);
CREATE INDEX IF NOT EXISTS idx_retorno_det       ON retorno_detalle(retorno_id);
