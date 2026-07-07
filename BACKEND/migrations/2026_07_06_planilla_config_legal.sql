-- Migración MANUAL (2026-07-06): motor de cálculo legal de Planilla — Fase 1
-- (esquema + configuración; el motor de cálculo en sí es la Fase 2/4 aparte).
--
-- Agrega:
--   1) empresa: régimen LABORAL (micro/pequeña/general, Ley N.° 32353) y
--      esquema de pago de planilla (mensual/quincenal). Distinto de
--      empresa.regimen_tributario, que es el régimen SUNAT (tributario).
--   2) empleado_planilla_config: configuración previsional 1:1 opcional por
--      empleado (sistema de pensión ONP/AFP, entidad AFP, comisión
--      personalizada, asignación familiar). Tabla dedicada (no columnas en
--      `empleado`, que es transversal a legajo/asistencia/evaluaciones) —
--      fila ausente = valores por defecto en código (onp, sin AFP, sin
--      asignación familiar), no rompe empleados existentes.
--   3) planilla / boleta_pago: columnas informativas de CTS, Gratificación y
--      Vacaciones (provisión mensualizada). NO alimentan los asientos
--      contables (se pagan en su fecha legal real: CTS mayo/noviembre,
--      gratificación julio/diciembre) — ver planilla_calculo_service.py.
--
-- IDs en `uuid` nativo: confirmado en producción que empresa.id, empleado.id
-- y empleado_concepto.* ya son `uuid` (pese a que el ORM los declara
-- String(36)) — mismo patrón que la migración empleado_concepto.
--
-- Aplicar con script .py + psycopg2 usando DATABASE_URL del .env (nunca la
-- connection string inline).

BEGIN;

-- 1) Empresa: régimen laboral + esquema de pago
ALTER TABLE empresa
    ADD COLUMN IF NOT EXISTS regimen_laboral VARCHAR(20) NOT NULL DEFAULT 'micro';

ALTER TABLE empresa
    ADD COLUMN IF NOT EXISTS esquema_pago_planilla VARCHAR(20) NOT NULL DEFAULT 'quincenal';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_empresa_regimen_laboral') THEN
        ALTER TABLE empresa
            ADD CONSTRAINT chk_empresa_regimen_laboral
            CHECK (regimen_laboral IN ('micro','pequena','general'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_empresa_esquema_pago') THEN
        ALTER TABLE empresa
            ADD CONSTRAINT chk_empresa_esquema_pago
            CHECK (esquema_pago_planilla IN ('mensual','quincenal'));
    END IF;
END $$;

-- 2) Configuración previsional por empleado (1:1 opcional)
CREATE TABLE IF NOT EXISTS empleado_planilla_config (
    id                          uuid         PRIMARY KEY,
    empresa_id                  uuid         NOT NULL REFERENCES empresa(id),
    empleado_id                 uuid         NOT NULL REFERENCES empleado(id),
    sistema_pension             VARCHAR(10)  NOT NULL DEFAULT 'onp',
    entidad_afp                 VARCHAR(20),
    comision_afp_personalizada  NUMERIC(6,4),
    tiene_asignacion_familiar   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at                  TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMP WITHOUT TIME ZONE,
    CONSTRAINT uq_empleado_planilla_config UNIQUE (empleado_id),
    CONSTRAINT chk_epc_sistema_pension CHECK (sistema_pension IN ('onp','afp')),
    CONSTRAINT chk_epc_entidad_afp CHECK (entidad_afp IS NULL OR entidad_afp IN ('integra','prima','profuturo','habitat'))
);
CREATE INDEX IF NOT EXISTS idx_epc_empresa ON empleado_planilla_config(empresa_id);

-- 3) Columnas informativas de CTS/Gratificación/Vacaciones (no contabilizan)
ALTER TABLE boleta_pago ADD COLUMN IF NOT EXISTS total_cts           NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE boleta_pago ADD COLUMN IF NOT EXISTS total_gratificacion NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE boleta_pago ADD COLUMN IF NOT EXISTS total_vacaciones    NUMERIC(14,2) NOT NULL DEFAULT 0;

ALTER TABLE planilla ADD COLUMN IF NOT EXISTS total_cts           NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE planilla ADD COLUMN IF NOT EXISTS total_gratificacion NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE planilla ADD COLUMN IF NOT EXISTS total_vacaciones    NUMERIC(14,2) NOT NULL DEFAULT 0;

COMMENT ON TABLE empleado_planilla_config IS 'Configuración previsional por empleado (sistema de pensión, AFP, asignación familiar) — Fase 8 motor de cálculo legal de Planilla.';

COMMIT;
