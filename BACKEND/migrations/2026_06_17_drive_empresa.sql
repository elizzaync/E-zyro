-- Drive de empresa: carpetas recursivas + archivos (cualquier tipo) en Cloudinary.
-- Ámbitos: 'compartido' (toda la empresa) y 'personal' (propietario + admin).
-- Tipos uuid explícitos para no romper create_all en prod (FK a empresa/usuario uuid).
-- Aplicar manualmente: railway run -s Postgres-SjrN psql ... < este archivo

CREATE TABLE IF NOT EXISTS drive_carpeta (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id    uuid NOT NULL REFERENCES empresa(id),
    padre_id      uuid REFERENCES drive_carpeta(id),
    nombre        varchar(150) NOT NULL,
    ambito        varchar(20) NOT NULL DEFAULT 'compartido',
    propietario_id uuid REFERENCES usuario(id),
    creado_por_id uuid REFERENCES usuario(id),
    created_at    timestamp NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_drive_carpeta_empresa ON drive_carpeta(empresa_id);
CREATE INDEX IF NOT EXISTS ix_drive_carpeta_padre   ON drive_carpeta(padre_id);
CREATE INDEX IF NOT EXISTS ix_drive_carpeta_ambito  ON drive_carpeta(empresa_id, ambito, propietario_id);

CREATE TABLE IF NOT EXISTS drive_archivo (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id           uuid NOT NULL REFERENCES empresa(id),
    carpeta_id           uuid REFERENCES drive_carpeta(id),
    ambito               varchar(20) NOT NULL DEFAULT 'compartido',
    propietario_id       uuid REFERENCES usuario(id),
    nombre               varchar(255) NOT NULL,
    descripcion          varchar(300),
    url_cloudinary       text NOT NULL,
    public_id_cloudinary varchar(300) NOT NULL,
    recurso_tipo         varchar(20) NOT NULL DEFAULT 'raw',
    formato              varchar(10),
    bytes                integer,
    subido_por_id        uuid REFERENCES usuario(id),
    created_at           timestamp NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_drive_archivo_empresa ON drive_archivo(empresa_id);
CREATE INDEX IF NOT EXISTS ix_drive_archivo_carpeta ON drive_archivo(carpeta_id);
CREATE INDEX IF NOT EXISTS ix_drive_archivo_ambito  ON drive_archivo(empresa_id, ambito, propietario_id);
