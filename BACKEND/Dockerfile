# Pin EXPLÍCITO de la base: Python 3.11 sobre Debian 13 "trixie".
# Nunca usar el tag flotante `python:3.11-slim`: cambió de bookworm a trixie
# sin aviso y rompió el repo PGDG (libldap-2.5 vs libldap-2.6).
FROM python:3.11-slim-trixie

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ── Dependencias de sistema ────────────────────────────────────────────────
# libgl1/libglib2.0-0: runtime de opencv; curl/ca-certificates: repo PGDG y TLS.
# postgresql-client-18: pg_dump para el módulo de Backups (el servidor es PG 18;
# pg_dump debe ser >= la versión del servidor y trixie solo trae la 17).
# El sufijo del repo PGDG DEBE coincidir con el Debian de la imagen base (trixie).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        curl \
        ca-certificates \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends postgresql-client-18 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencias Python primero (capa cacheada mientras requirements.txt no cambie).
# Todo son wheels precompilados (psycopg2-binary incl.): no se necesita gcc ni libpq-dev.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Código al final: cambiar código no invalida la capa de dependencias.
COPY app ./app
COPY assets ./assets

# Usuario no-root. Los backups escriben en BACKUP_DIR (default: /tmp, escribible);
# si se monta un volumen para BACKUP_DIR en otro servidor, darle permisos a uid 1000.
RUN useradd --create-home --uid 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

# Healthcheck para servidores que sí lo respetan (docker/compose); Railway usa
# su propio healthcheckPath en railway.toml y lo ignora.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8080')+'/', timeout=4)" || exit 1

# Respeta $PORT (Railway y cualquier PaaS lo inyectan); 8080 como fallback local.
CMD ["sh", "-c", "python -m uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
