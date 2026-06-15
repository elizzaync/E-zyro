-- Migración MANUAL (2026-06-15): tabla movimiento_equipo (bitácora por unidad).
-- Manual (no create_all) porque las FKs referencian PKs uuid nativas en prod.
-- Las FK (empresa_id, equipo_id, responsable_id) van en uuid; referencia_id es
-- varchar (puede apuntar a distintas tablas, sin FK).

CREATE TABLE IF NOT EXISTS movimiento_equipo (
    id              uuid PRIMARY KEY,
    empresa_id      uuid NOT NULL REFERENCES empresa(id),
    equipo_id       uuid NOT NULL REFERENCES equipo(id),
    tipo            varchar(20) NOT NULL,
    detalle         varchar(255),
    referencia_id   varchar(36),
    referencia_tipo varchar(30),
    responsable_id  uuid REFERENCES empleado(id),
    fecha           timestamp without time zone NOT NULL DEFAULT now(),
    created_at      timestamp without time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mov_equipo ON movimiento_equipo (equipo_id, fecha DESC);
