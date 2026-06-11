-- ============================================================
-- Migración: preferencia_notificacion
-- Fecha: 2026-06-11
-- Permite a cada usuario activar/desactivar push por categoría
-- (general|almuerzo|alertas|comunicados|servicios|chat).
-- Sin fila → default del código (todo ON salvo chat OFF).
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS preferencia_notificacion (
    id          VARCHAR(36)  PRIMARY KEY,
    usuario_id  UUID         NOT NULL REFERENCES usuario(id),
    categoria   VARCHAR(30)  NOT NULL,
    activo      BOOLEAN      NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT uq_pref_notif_usuario_cat UNIQUE (usuario_id, categoria)
);

CREATE INDEX IF NOT EXISTS idx_pref_notif_usuario
    ON preferencia_notificacion(usuario_id);

COMMIT;
