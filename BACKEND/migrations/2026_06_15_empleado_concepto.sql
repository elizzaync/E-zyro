-- Migración MANUAL (2026-06-15): tabla empleado_concepto.
--
-- Por qué manual: en producción los IDs son `uuid` nativos. Una tabla nueva con
-- FKs a PKs uuid NO la puede crear Base.metadata.create_all (SQLAlchemy emite
-- VARCHAR(36) y Postgres rechaza la FK varchar↔uuid). Se crea aquí con tipos
-- uuid; luego create_all la ve existente y la omite (checkfirst).
--
-- Aplicar en BD viva:
--   railway run -s Postgres-SjrN psql $DATABASE_PUBLIC_URL -f este_archivo.sql
-- (o vía script .py con psycopg2 usando DATABASE_PUBLIC_URL).

CREATE TABLE IF NOT EXISTS empleado_concepto (
    id          uuid PRIMARY KEY,
    empresa_id  uuid NOT NULL REFERENCES empresa(id),
    empleado_id uuid NOT NULL REFERENCES empleado(id),
    concepto_id uuid NOT NULL REFERENCES concepto_remunerativo(id),
    monto       NUMERIC(14,2) NOT NULL,
    created_at  TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP WITHOUT TIME ZONE,
    CONSTRAINT uq_empleado_concepto UNIQUE (empleado_id, concepto_id)
);
