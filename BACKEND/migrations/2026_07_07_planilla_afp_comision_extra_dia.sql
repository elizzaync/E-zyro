-- Migración MANUAL (2026-07-07): motor de cálculo legal de Planilla — FIX 1
-- (comisión AFP por esquema flujo/saldo) y FIX 3 (gate de pago de sobretiempo
-- sin trámite). FIX 2 (horas extra por día) no requiere cambio de esquema:
-- se calcula en caliente en resumen_horas_periodo/InsumoEmpleado, no persiste.
--
-- Agrega:
--   1) empleado_planilla_config.tipo_comision_afp ('saldo'|'flujo', default
--      'saldo' — esquema legal por defecto de todo afiliado SPP post-2013;
--      la comisión de flujo, cuando aplica, SÍ se descuenta de la planilla).
--   2) empresa.pagar_horas_extra_sin_tramite (bool, default FALSE — decisión
--      de negocio con riesgo legal: solo se paga sobretiempo respaldado por
--      un trámite de Permanencia Extra aprobado; ver
--      planilla_calculo_service.calcular_boleta_empleado).
--
-- Backfill: ambas columnas se agregan con DEFAULT NOT NULL — Postgres >= 11
-- escribe el default a TODAS las filas existentes de una sola vez (no
-- requiere UPDATE aparte). Afecta a TODAS las empresas (pagar_horas_extra_sin_tramite)
-- y a TODOS los empleados con configuración previsional ya guardada
-- (tipo_comision_afp) — ninguno pierde datos, ambos caen al comportamiento
-- más conservador/legal por defecto.
--
-- Aplicar con script .py + psycopg2 usando DATABASE_URL del .env (nunca la
-- connection string inline), igual que 2026_07_06_planilla_config_legal.sql.

BEGIN;

ALTER TABLE empleado_planilla_config
    ADD COLUMN IF NOT EXISTS tipo_comision_afp VARCHAR(10) NOT NULL DEFAULT 'saldo';

ALTER TABLE empresa
    ADD COLUMN IF NOT EXISTS pagar_horas_extra_sin_tramite BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_epc_tipo_comision_afp') THEN
        ALTER TABLE empleado_planilla_config
            ADD CONSTRAINT chk_epc_tipo_comision_afp
            CHECK (tipo_comision_afp IN ('flujo','saldo'));
    END IF;
END $$;

COMMIT;
