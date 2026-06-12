-- Índices de apoyo para los filtros de la pantalla de Auditoría móvil.
-- MANUAL: correr con  railway run -s Postgres-SjrN psql "$DATABASE_PUBLIC_URL" -f este_archivo.sql
-- (o vía script .py). Base.metadata.create_all NO crea índices nuevos sobre tablas existentes.
--
-- Ya existen en producción:
--   idx_auditoria_empresa_fecha (empresa_id, fecha DESC)  -- cubre la consulta por defecto
--   idx_auditoria_tabla         (tabla_afectada, fecha DESC)
--   idx_auditoria_datos_nuevos  GIN (datos_nuevos)
--
-- Estos complementan el filtrado por actor y por tipo de acción sin escanear toda la tabla.

CREATE INDEX IF NOT EXISTS idx_auditoria_empresa_usuario_fecha
    ON public.auditoria USING btree (empresa_id, usuario_id, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_auditoria_empresa_accion_fecha
    ON public.auditoria USING btree (empresa_id, accion, fecha DESC);
