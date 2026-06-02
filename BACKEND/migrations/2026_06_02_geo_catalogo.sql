-- ============================================================================
-- Migración: Jerarquía geográfica ubicacion → zona → area por empresa y servicio
-- Fecha: 2026-06-02
-- Idempotente. Espejo de los bloques en app/main.py (_pre_create_migrations /
-- _run_migrations). Todas las FKs son uuid (las PK del sistema son uuid).
-- La geografía la "posee" el servicio (proyecto_servicio); el nivel proyecto se
-- deriva de sus servicios. Las columnas de texto legacy (equipo.ubicacion,
-- proyecto_servicio.zona_ejecucion, equipo_intervenido.area_descripcion) se
-- CONSERVAN como caché/respaldo.
-- ============================================================================

-- area: nivel físico bajo zona (NULL = área RR.HH.)
ALTER TABLE area
    ADD COLUMN IF NOT EXISTS ubicacion_id uuid REFERENCES ubicacion(id),
    ADD COLUMN IF NOT EXISTS zona_id      uuid REFERENCES zona(id);

-- El nombre de área puede repetirse entre zonas distintas
DROP INDEX IF EXISTS uq_area_empresa_nombre;
CREATE UNIQUE INDEX IF NOT EXISTS uq_area_empresa_zona_nombre
    ON area (empresa_id, coalesce(zona_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(nombre));

-- equipo (catálogo logística): FKs a la jerarquía
ALTER TABLE equipo
    ADD COLUMN IF NOT EXISTS ubicacion_id uuid REFERENCES ubicacion(id),
    ADD COLUMN IF NOT EXISTS zona_id      uuid REFERENCES zona(id),
    ADD COLUMN IF NOT EXISTS area_id      uuid REFERENCES area(id);

-- proyecto_servicio: FKs que sustituyen zona_ejecucion (texto)
ALTER TABLE proyecto_servicio
    ADD COLUMN IF NOT EXISTS ubicacion_id uuid REFERENCES ubicacion(id),
    ADD COLUMN IF NOT EXISTS zona_id      uuid REFERENCES zona(id);

-- equipo_intervenido: FK que sustituye area_descripcion (texto)
ALTER TABLE equipo_intervenido
    ADD COLUMN IF NOT EXISTS area_id uuid REFERENCES area(id);

-- Índices para filtros geográficos / dashboards
CREATE INDEX IF NOT EXISTS idx_area_zona_id                ON area(zona_id);
CREATE INDEX IF NOT EXISTS idx_equipo_zona_id              ON equipo(zona_id);
CREATE INDEX IF NOT EXISTS idx_equipo_ubicacion_id         ON equipo(ubicacion_id);
CREATE INDEX IF NOT EXISTS idx_proyecto_servicio_zona_id   ON proyecto_servicio(zona_id);
CREATE INDEX IF NOT EXISTS idx_proyecto_servicio_ubic_id   ON proyecto_servicio(ubicacion_id);
CREATE INDEX IF NOT EXISTS idx_equipo_intervenido_area_id  ON equipo_intervenido(area_id);
