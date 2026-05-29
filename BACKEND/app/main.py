from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from sqlalchemy import text
import logging
import time

logger = logging.getLogger(__name__)

from app.db.database import engine, Base
from app.db.rbac_seed import sembrar_permisos
from app.routers import auth, dashboard
from app.routers import permisos        as permisos_router
from app.routers import asistencia      as asistencia_router
from app.routers import proyectos       as proyectos_router
from app.routers import comunicados     as comunicados_router
from app.routers import operaciones     as operaciones_router
from app.routers import chat_ws         as chat_ws_router
from app.routers import notificaciones  as notificaciones_router
from app.routers import requerimientos  as requerimientos_router
from app.routers import auditoria       as auditoria_router
from app.routers import logistica       as logistica_router
from app.routers import seguridad       as seguridad_router
from app.routers import prestamo        as prestamo_router
from app.routers import catalogos       as catalogos_router
from app.routers import galeria         as galeria_router
from app.services.scheduler_service import iniciar_scheduler, detener_scheduler
from app.core.audit_context import AuditContextMiddleware
import app.core.audit_listener  # noqa: F401 — registra el listener al importar

# Importar todos los modelos para que Base los registre antes de create_all
from app.models import (  # noqa: F401
    # Core
    #corex
    empresa, plan_suscripcion, suscripcion,
    # Usuarios y roles
    usuario, rol, permiso, rol_permiso, usuario_rol, usuario_permiso,
    recuperacion_password, sesion_usuario, auditoria,
    # Clientes
    cliente, contrato_comercial, usuario_cliente,
    # Empleados
    empleado, contrato, documento_laboral, solicitud_laboral,
    turno, grupo_trabajo,
    categoria_habilidad, habilidad, empleado_habilidad,
    firma_digital, historial_firma, documento_firmado,
    foto_biometrica, dispositivo_push, notificacion,
    # Proyectos
    proyecto, proyecto_detalle, proyecto_miembro, proyecto_servicio,
    catalogo_servicio, fase, seguimiento_proyecto,
    proyecto_equipo, proyecto_grupo, mensaje_chat, programacion_campo,
    # Asistencia
    registro_asistencia, foto_asistencia, geolocalizacion_asistencia,
    # Operaciones / servicios
    procedimiento, evidencia_procedimiento,
    requerimiento, requerimiento_entrega,
    # Inventario: material.py contiene Stock; categoria_material.py y almacen.py son dependencias
    categoria_material, almacen, material, movimiento_inventario,
    unidad_medida, marca, modelo_equipo,
    # Catálogos base (Fase 0 — plan migración ERP)
    ubicacion, zona, area,
    # Galería global / índice de Cloudinary (Fase 1 — plan migración ERP)
    recurso_cloudinary,
    # Compras
    proveedor, orden_compra, recepcion_compra, ticket_compra,
    # Comunicados
    comunicado,
    # Equipos y mantenimiento
    tipo_equipo, equipo, plan_mantenimiento,
    orden_mantenimiento, evidencia_mantenimiento, informe_tecnico,
    paso_mantenimiento,
    # Préstamos de equipos/herramientas (HU-FASE5)
    prestamo,
    # Caja chica
    caja_chica,
    # Evaluación (contiene CriterioEvaluacion, Evaluacion, DetalleEvaluacion, CalificacionCliente)
    evaluacion,
    # Documentación
    carpeta_documental, plano, recordatorio,
)


def _pre_create_migrations():
    """
    Migraciones que DEBEN correr ANTES de Base.metadata.create_all.

    marca / modelo_equipo / unidad_medida llevan FK a empresa(id) que es `uuid`.
    Si SQLAlchemy las crea desde el modelo (String(36)) las haría VARCHAR(36) y
    al añadir luego `equipo.marca_id uuid REFERENCES marca(id)` Postgres rechaza
    el FK por tipos incompatibles. Por eso las creamos aquí con uuid explícito.
    """
    with engine.connect() as conn:
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS marca (
                id          uuid PRIMARY KEY,
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(120) NOT NULL,
                created_at  TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS modelo_equipo (
                id          uuid PRIMARY KEY,
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                marca_id    uuid NOT NULL REFERENCES marca(id),
                nombre      VARCHAR(120) NOT NULL,
                created_at  TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS unidad_medida (
                id          uuid PRIMARY KEY,
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(60) NOT NULL,
                abreviatura VARCHAR(15),
                created_at  TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_marca_empresa_nombre "
            "ON marca (empresa_id, lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_modelo_marca_nombre "
            "ON modelo_equipo (marca_id, lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_unidad_empresa_nombre "
            "ON unidad_medida (empresa_id, lower(nombre))"
        ))

        # ── Catálogos base (Fase 0 — plan migración ERP) ─────────────────────
        # ubicacion → zona (FK) → area. FKs uuid a empresa(id), por eso van aquí.
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS ubicacion (
                id          uuid PRIMARY KEY,
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(150) NOT NULL,
                region      VARCHAR(100),
                created_at  TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS zona (
                id           uuid PRIMARY KEY,
                empresa_id   uuid NOT NULL REFERENCES empresa(id),
                ubicacion_id uuid REFERENCES ubicacion(id),
                nombre       VARCHAR(150) NOT NULL,
                tipo         VARCHAR(50),
                created_at   TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS area (
                id          uuid PRIMARY KEY,
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(150) NOT NULL,
                created_at  TIMESTAMP NOT NULL DEFAULT now()
            )
        """))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_ubicacion_empresa_nombre "
            "ON ubicacion (empresa_id, lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_zona_empresa_ubic_nombre "
            "ON zona (empresa_id, coalesce(ubicacion_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_area_empresa_nombre "
            "ON area (empresa_id, lower(nombre))"
        ))

        # ── Galería global: índice de recursos Cloudinary (Fase 1) ───────────
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS recurso_cloudinary (
                id            uuid PRIMARY KEY,
                empresa_id    uuid NOT NULL REFERENCES empresa(id),
                public_id     VARCHAR(300) NOT NULL,
                secure_url    TEXT NOT NULL,
                folder        VARCHAR(300),
                recurso_tipo  VARCHAR(20) NOT NULL DEFAULT 'imagen',
                entidad_tipo  VARCHAR(40) NOT NULL,
                entidad_id    uuid,
                descripcion   VARCHAR(300),
                bytes         INTEGER,
                formato       VARCHAR(10),
                creado_por_id uuid,
                created_at    TIMESTAMP NOT NULL DEFAULT now(),
                CONSTRAINT chk_recurso_tipo CHECK (recurso_tipo IN ('imagen','pdf','raw','video'))
            )
        """))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_recurso_empresa_entidad "
            "ON recurso_cloudinary (empresa_id, entidad_tipo, entidad_id)"
        ))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_recurso_empresa_fecha "
            "ON recurso_cloudinary (empresa_id, created_at)"
        ))
        # ticket_compra referencia empresa(id) que es uuid — mismo patrón que marca/unidad_medida
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS ticket_compra (
                id                     uuid           PRIMARY KEY,
                empresa_id             uuid           NOT NULL REFERENCES empresa(id),
                requerimiento_id       uuid           REFERENCES requerimiento(id),
                codigo                 VARCHAR(20)    NOT NULL,
                estado                 VARCHAR(20)    NOT NULL DEFAULT 'pendiente',
                proyecto_id            uuid,
                proyecto_servicio_id   uuid,
                proyecto_nombre        VARCHAR(300),
                servicio_nombre        VARCHAR(300),
                solicitante_nombre     VARCHAR(200),
                modo_unificado         BOOLEAN,
                proveedor_unico_id     uuid,
                proveedor_unico_nombre VARCHAR(200),
                canal_unico            VARCHAR(200),
                total_estimado         NUMERIC(12,2),
                total_real             NUMERIC(12,2),
                responsable_id         uuid,
                nota                   TEXT,
                motivo_cancelacion     TEXT,
                created_at             TIMESTAMP      NOT NULL DEFAULT now(),
                updated_at             TIMESTAMP
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS ticket_compra_item (
                id                       uuid         PRIMARY KEY,
                ticket_id                uuid         NOT NULL REFERENCES ticket_compra(id),
                requerimiento_detalle_id uuid,
                material_id              uuid,
                nombre                   VARCHAR(300) NOT NULL,
                cantidad                 INTEGER      NOT NULL DEFAULT 1,
                unidad                   VARCHAR(50),
                cantidad_comprada        INTEGER,
                precio_unitario          NUMERIC(12,2),
                total_item               NUMERIC(12,2),
                proveedor_id             uuid,
                proveedor_nombre         VARCHAR(200),
                canal_personalizado      VARCHAR(200),
                factura                  VARCHAR(100),
                estado_item              VARCHAR(20)  NOT NULL DEFAULT 'pendiente',
                nota                     TEXT
            )
        """))

        # ── HU-FASE5: Préstamos de equipos/herramientas ──────────────────────
        # Mismo patrón que ticket_compra: FKs a empresa/proyecto_servicio/
        # empleado/equipo son uuid. Si SQLAlchemy crea las tablas desde el
        # modelo (String(36) → VARCHAR(36)) Postgres rechaza los FKs por tipo
        # incompatible. Por eso las creamos aquí con uuid explícito antes de
        # Base.metadata.create_all.
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS prestamo (
                id                    uuid          PRIMARY KEY,
                empresa_id            uuid          NOT NULL REFERENCES empresa(id),
                proyecto_servicio_id  uuid          NOT NULL REFERENCES proyecto_servicio(id),
                solicitante_id        uuid          NOT NULL REFERENCES empleado(id),
                estado                VARCHAR(20)   NOT NULL DEFAULT 'solicitado',
                observacion           TEXT,
                observacion_logistico TEXT,
                entregado_por_id      uuid          REFERENCES empleado(id),
                devuelto_por_id       uuid          REFERENCES empleado(id),
                confirmado_por_id     uuid          REFERENCES empleado(id),
                fecha_solicitud       TIMESTAMP     NOT NULL DEFAULT now(),
                fecha_entrega         TIMESTAMP,
                fecha_devolucion      TIMESTAMP,
                fecha_confirmacion    TIMESTAMP,
                created_at            TIMESTAMP     NOT NULL DEFAULT now(),
                updated_at            TIMESTAMP
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS prestamo_item (
                id                  uuid          PRIMARY KEY,
                prestamo_id         uuid          NOT NULL REFERENCES prestamo(id),
                equipo_id           uuid          NOT NULL REFERENCES equipo(id),
                cantidad_solicitada INTEGER       NOT NULL DEFAULT 1,
                cantidad_entregada  INTEGER,
                cantidad_devuelta   INTEGER,
                cantidad_perdida    INTEGER       NOT NULL DEFAULT 0,
                observacion         TEXT
            )
        """))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_prestamo_empresa_estado "
            "ON prestamo (empresa_id, estado)"
        ))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_prestamo_servicio "
            "ON prestamo (proyecto_servicio_id)"
        ))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_prestamo_item_prestamo "
            "ON prestamo_item (prestamo_id)"
        ))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_prestamo_item_equipo "
            "ON prestamo_item (equipo_id)"
        ))

        conn.commit()


def _run_migrations():
    """Aplica migraciones incrementales de forma segura (IF NOT EXISTS)."""
    with engine.connect() as conn:
        # ── RBAC seed: permisos del módulo de catálogos (Fase 0) ─────────────
        sembrar_permisos(conn, "catalogos", ["ver", "crear", "editar", "eliminar"],
                         descripcion_base="Catálogos base:")
        # ── RBAC seed: permisos de la galería global (Fase 1) ────────────────
        sembrar_permisos(conn, "galeria", ["ver", "subir", "eliminar"],
                         descripcion_base="Galería global:")
        conn.commit()

        conn.execute(text(
            "ALTER TABLE solicitud_laboral "
            "ADD COLUMN IF NOT EXISTS url_pdf VARCHAR(500)"
        ))
        conn.execute(text(
            "ALTER TABLE solicitud_laboral "
            "ADD COLUMN IF NOT EXISTS public_id_pdf VARCHAR(255)"
        ))
        conn.execute(text(
            "ALTER TABLE mensaje_chat "
            "ADD COLUMN IF NOT EXISTS destinatario_id UUID "
            "REFERENCES usuario(id)"
        ))
        conn.execute(text(
            "ALTER TABLE auditoria "
            "ADD COLUMN IF NOT EXISTS empresa_id VARCHAR(36)"
        ))
        # ── HU-MANT: tabla paso_mantenimiento (checklist técnico por equipo) ──
        # NOTA: los IDs en este esquema son `uuid` (vienen del backup original).
        # Las FKs DEBEN ser uuid para no romper. SQLAlchemy mapea el campo Python
        # `String(36)` <-> postgres `uuid` de forma transparente.
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS paso_mantenimiento (
                id          uuid PRIMARY KEY,
                equipo_id   uuid NOT NULL REFERENCES equipo(id),
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(200) NOT NULL,
                descripcion TEXT,
                orden       INTEGER NOT NULL DEFAULT 1,
                estado      VARCHAR(20) NOT NULL DEFAULT 'pendiente',
                created_at  TIMESTAMP NOT NULL DEFAULT now(),
                updated_at  TIMESTAMP
            )
        """))
        conn.execute(text(
            "ALTER TABLE evidencia_mantenimiento "
            "ADD COLUMN IF NOT EXISTS paso_id uuid "
            "REFERENCES paso_mantenimiento(id)"
        ))
        # ── CRUD Operaciones 2026-05-25 ──────────────────────────────────────
        # Columna para fecha de inicio de tarea en el cronograma (Gantt)
        conn.execute(text(
            "ALTER TABLE procedimiento "
            "ADD COLUMN IF NOT EXISTS fecha_inicio_tarea DATE"
        ))
        conn.execute(text(
            "ALTER TABLE procedimiento "
            "ADD COLUMN IF NOT EXISTS fecha_limite DATE"
        ))
        # ── Refactor proyecto_servicio 2026-05-26 ────────────────────────────
        # Estas columnas viven ahora a nivel servicio (antes en proyecto_detalle).
        # Sin ellas, cualquier SELECT del ORM sobre proyecto_servicio falla con
        # UndefinedColumn → HTTP 500 al listar servicios / abrir detalle / configurar.
        # Idempotente (IF NOT EXISTS); se aplica solo si faltan.
        conn.execute(text("""
            ALTER TABLE proyecto_servicio
                ADD COLUMN IF NOT EXISTS lider_id               UUID,
                ADD COLUMN IF NOT EXISTS zona_ejecucion         VARCHAR(255),
                ADD COLUMN IF NOT EXISTS alcance                TEXT,
                ADD COLUMN IF NOT EXISTS tipo_documento_cliente VARCHAR(20),
                ADD COLUMN IF NOT EXISTS nro_documento          VARCHAR(100),
                ADD COLUMN IF NOT EXISTS nro_conformidad        VARCHAR(100) DEFAULT 'En Espera',
                ADD COLUMN IF NOT EXISTS acta_url               VARCHAR(500),
                ADD COLUMN IF NOT EXISTS public_id_cloudinary   VARCHAR(255)
        """))
        # ── Notas por servicio 2026-05-26 ────────────────────────────────────
        # Liga la nota (seguimiento) a un servicio concreto. NULL = nota antigua
        # a nivel proyecto. create_all() no altera tablas existentes.
        # NOTA: proyecto_servicio.id es UUID en Postgres → la FK debe ser UUID,
        # no VARCHAR(36); de lo contrario Postgres lanza DatatypeMismatch.
        conn.execute(text(
            "ALTER TABLE seguimiento_proyecto "
            "ADD COLUMN IF NOT EXISTS proyecto_servicio_id UUID "
            "REFERENCES proyecto_servicio(id)"
        ))
        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='auditoria'
                      AND column_name='datos_anteriores'
                      AND data_type='text'
                ) THEN
                    ALTER TABLE auditoria
                        ALTER COLUMN datos_anteriores
                        TYPE JSONB USING NULLIF(datos_anteriores,'')::jsonb;
                    ALTER TABLE auditoria
                        ALTER COLUMN datos_nuevos
                        TYPE JSONB USING NULLIF(datos_nuevos,'')::jsonb;
                END IF;
            END $$;
        """))

        # ── HU-15 LOGÍSTICA 2026-05-27 ───────────────────────────────────────
        # Material: precio referencial
        conn.execute(text(
            "ALTER TABLE material "
            "ADD COLUMN IF NOT EXISTS precio NUMERIC(10,2)"
        ))
        # Equipo: clase (equipo|herramienta), mantenimiento, etc.
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS clase VARCHAR(20) NOT NULL DEFAULT 'equipo'"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS cantidad INTEGER NOT NULL DEFAULT 1"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS tipo VARCHAR(120)"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS fecha_adquisicion DATE"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS ficha_tecnica TEXT"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS requiere_mantenimiento BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS frecuencia_mantenimiento VARCHAR(20) NOT NULL DEFAULT 'ninguno'"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS proxima_fecha_mantenimiento DATE"
        ))
        # tipo_equipo_id antes era NOT NULL; ahora opcional (idempotente).
        conn.execute(text("""
            DO $$
            BEGIN
                ALTER TABLE equipo ALTER COLUMN tipo_equipo_id DROP NOT NULL;
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END $$;
        """))

        # ── Catálogos de Logística (Marca, Modelo, Unidad) ───────────────────
        # Las tablas marca/modelo_equipo/unidad_medida se crean en
        # _pre_create_migrations() con tipo UUID (las FKs apuntan a empresa.id
        # que es uuid). Aquí solo agregamos las FKs en `equipo`, también uuid.
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS marca_id    uuid REFERENCES marca(id)"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS modelo_id   uuid REFERENCES modelo_equipo(id)"
        ))
        conn.execute(text(
            "ALTER TABLE equipo "
            "ADD COLUMN IF NOT EXISTS almacen_id  uuid REFERENCES almacen(id)"
        ))

        # HU-16: estado por ítem del requerimiento (decisión de logística)
        conn.execute(text(
            "ALTER TABLE requerimiento_detalle "
            "ADD COLUMN IF NOT EXISTS estado_item VARCHAR(20) NOT NULL DEFAULT 'pendiente'"
        ))
        # HU-16: firma del técnico receptor en el requerimiento
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firma_receptor_url TEXT"
        ))
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firma_recibido_por_id uuid REFERENCES empleado(id)"
        ))
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firma_fecha TIMESTAMP"
        ))
        # HU-16 ext: cinema-seat signature locking
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firmando_por_id VARCHAR(36)"
        ))
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firmando_desde TIMESTAMP"
        ))
        conn.execute(text(
            "ALTER TABLE requerimiento "
            "ADD COLUMN IF NOT EXISTS firma_entregador_url TEXT"
        ))
        # HU-17 ext: firma del entregador en entrega
        conn.execute(text(
            "ALTER TABLE requerimiento_entrega "
            "ADD COLUMN IF NOT EXISTS firma_entregador_url TEXT"
        ))
        # HU-16 fix: ampliar columnas VARCHAR(500) existentes a TEXT para firmas Base64
        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='requerimiento'
                      AND column_name='firma_receptor_url'
                      AND character_maximum_length IS NOT NULL
                ) THEN
                    ALTER TABLE requerimiento
                        ALTER COLUMN firma_receptor_url   TYPE TEXT,
                        ALTER COLUMN firma_entregador_url TYPE TEXT;
                END IF;
            END $$;
        """))
        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='requerimiento_entrega'
                      AND column_name='firma_entregador_url'
                      AND character_maximum_length IS NOT NULL
                ) THEN
                    ALTER TABLE requerimiento_entrega
                        ALTER COLUMN firma_receptor_url   TYPE TEXT,
                        ALTER COLUMN firma_entregador_url TYPE TEXT;
                END IF;
            END $$;
        """))

        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='firma_digital'
                      AND column_name='url_cloudinary'
                      AND character_maximum_length IS NOT NULL
                ) THEN
                    ALTER TABLE firma_digital ALTER COLUMN url_cloudinary TYPE TEXT;
                END IF;
            END $$;
        """))
        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='historial_firma'
                      AND column_name='url_cloudinary'
                      AND character_maximum_length IS NOT NULL
                ) THEN
                    ALTER TABLE historial_firma ALTER COLUMN url_cloudinary TYPE TEXT;
                END IF;
            END $$;
        """))

        # Índices únicos para evitar duplicados de categoría/almacén por empresa
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_categoria_material_empresa_nombre "
            "ON categoria_material (empresa_id, lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_almacen_empresa_nombre "
            "ON almacen (empresa_id, lower(nombre))"
        ))
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_tipo_equipo_empresa_nombre "
            "ON tipo_equipo (empresa_id, lower(nombre))"
        ))

        # ── HU-17 COMPRAS 2026-05-28 — Tickets de compra ─────────────────────
        # Tablas creadas en _pre_create_migrations con uuid; IF NOT EXISTS es seguro
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS ticket_compra (
                id                     uuid           PRIMARY KEY,
                empresa_id             uuid           NOT NULL REFERENCES empresa(id),
                requerimiento_id       uuid           REFERENCES requerimiento(id),
                codigo                 VARCHAR(20)    NOT NULL,
                estado                 VARCHAR(20)    NOT NULL DEFAULT 'pendiente',
                proyecto_id            uuid,
                proyecto_servicio_id   uuid,
                proyecto_nombre        VARCHAR(300),
                servicio_nombre        VARCHAR(300),
                solicitante_nombre     VARCHAR(200),
                modo_unificado         BOOLEAN,
                proveedor_unico_id     uuid,
                proveedor_unico_nombre VARCHAR(200),
                canal_unico            VARCHAR(200),
                total_estimado         NUMERIC(12,2),
                total_real             NUMERIC(12,2),
                responsable_id         uuid,
                nota                   TEXT,
                motivo_cancelacion     TEXT,
                created_at             TIMESTAMP      NOT NULL DEFAULT now(),
                updated_at             TIMESTAMP
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS ticket_compra_item (
                id                       uuid         PRIMARY KEY,
                ticket_id                uuid         NOT NULL REFERENCES ticket_compra(id),
                requerimiento_detalle_id uuid,
                material_id              uuid,
                nombre                   VARCHAR(300) NOT NULL,
                cantidad                 INTEGER      NOT NULL DEFAULT 1,
                unidad                   VARCHAR(50),
                cantidad_comprada        INTEGER,
                precio_unitario          NUMERIC(12,2),
                total_item               NUMERIC(12,2),
                proveedor_id             uuid,
                proveedor_nombre         VARCHAR(200),
                canal_personalizado      VARCHAR(200),
                factura                  VARCHAR(100),
                estado_item              VARCHAR(20)  NOT NULL DEFAULT 'pendiente',
                nota                     TEXT
            )
        """))

        # ── MODELO HÍBRIDO (Requerimientos) ───────────────────────────────────
        # Ampliar el CHECK de estado al set completo del modelo híbrido. El flujo
        # de logística usa 'comprando' y 'listo', que el CHECK original no
        # contemplaba; sin esta ampliación el UPDATE a 'listo' de más abajo viola
        # chk_req_estado y la app no arranca. Idempotente (DROP IF EXISTS + ADD).
        conn.execute(text(
            "ALTER TABLE requerimiento DROP CONSTRAINT IF EXISTS chk_req_estado"
        ))
        conn.execute(text("""
            ALTER TABLE requerimiento
                ADD CONSTRAINT chk_req_estado
                CHECK (estado IN ('borrador','pendiente','comprando','listo',
                                  'aprobado','rechazado','entregado','anulado'))
        """))

        # En el flujo anterior (modelo B) `estado='aprobado'` no se usaba; en
        # el modelo híbrido SÍ se usa (= recibido por el equipo, pendiente
        # cierre de logística). Cualquier registro 'aprobado' que NO tenga
        # firma del receptor es inconsistente con el nuevo flujo: lo regresamos
        # a 'listo' para que el técnico pueda firmar normalmente.
        # Idempotente: solo afecta filas que cumplen ambas condiciones.
        conn.execute(text("""
            UPDATE requerimiento
               SET estado = 'listo'
             WHERE estado = 'aprobado'
               AND firma_recibido_por_id IS NULL
        """))

        conn.commit()

        # ── Semillas básicas: unidades por defecto si la empresa no tiene ─────
        # Se ejecuta una sola vez por empresa cuando aún no hay unidades cargadas.
        conn.execute(text("""
            INSERT INTO unidad_medida (id, empresa_id, nombre, abreviatura)
            SELECT uuid_generate_v4(), e.id, u.nombre, u.abrev
            FROM empresa e
            CROSS JOIN (VALUES
                ('Unidad',     'und'),
                ('Par',        'par'),
                ('Metros',     'm'),
                ('Litros',     'l'),
                ('Kilogramos', 'kg'),
                ('Cajas',      'caja'),
                ('Rollos',     'rollo'),
                ('Juego',      'jgo')
            ) AS u(nombre, abrev)
            WHERE NOT EXISTS (
                SELECT 1 FROM unidad_medida um
                WHERE um.empresa_id = e.id AND lower(um.nombre) = lower(u.nombre)
            )
        """))
        conn.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    for intento in range(10):
        try:
            _pre_create_migrations()
            Base.metadata.create_all(bind=engine)
            _run_migrations()
            break
        except Exception as e:
            if intento == 9:
                raise
            print(f"DB no disponible (intento {intento + 1}/10), reintentando en 3s... {e}")
            time.sleep(3)
    iniciar_scheduler()
    yield
    detener_scheduler()


app = FastAPI(title="API E-zyro", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # permite cualquier origen (desarrollo + producción)
    allow_credentials=False,      # tokens JWT en header, no cookies → False
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(AuditContextMiddleware)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": f"{type(exc).__name__}: {exc}"},
    )

app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(permisos_router.router)
app.include_router(asistencia_router.router)
app.include_router(proyectos_router.router)
app.include_router(comunicados_router.router)
app.include_router(operaciones_router.router)
app.include_router(chat_ws_router.router)
app.include_router(notificaciones_router.router)
app.include_router(requerimientos_router.router)
app.include_router(auditoria_router.router)
app.include_router(logistica_router.router)
app.include_router(seguridad_router.router)
app.include_router(prestamo_router.router)
app.include_router(catalogos_router.router)
app.include_router(galeria_router.router)


@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}
