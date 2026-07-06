-- Programación editable de los backups automáticos (pantalla Gestión TIC → Backups).
-- Fila única (id=1). El scheduler la lee en cada tick: los cambios aplican al minuto.
CREATE TABLE IF NOT EXISTS backup_config (
    id              SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    bd_auto         BOOLEAN     NOT NULL DEFAULT TRUE,
    bd_frecuencia   VARCHAR(10) NOT NULL DEFAULT 'diario',   -- cada_hora | diario | semanal
    bd_hora         VARCHAR(5)  NOT NULL DEFAULT '23:30',    -- HH:MM hora local (America/Lima)
    bd_dia_semana   SMALLINT    NOT NULL DEFAULT 6,          -- 0=lunes … 6=domingo (solo semanal)
    bd_correo       BOOLEAN     NOT NULL DEFAULT TRUE,       -- enviar dump por correo a Soporte
    archivos_auto   BOOLEAN     NOT NULL DEFAULT TRUE,       -- backups de archivos Cloudinary on/off
    actualizado_por VARCHAR(36),                             -- usuario.id del último cambio (sin FK, auditoría)
    actualizado_en  TIMESTAMP DEFAULT now()
);

INSERT INTO backup_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE backup_config IS 'Programación de backups automáticos, editable por Soporte. Fila única id=1.';
