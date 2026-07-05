FROM python:3.11-slim

# System deps needed by psycopg2, opencv, numpy
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    libgl1 \
    libglib2.0-0 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# postgresql-client-18: pg_dump para el módulo de Backups (el servidor es PG 18;
# el binario de pg_dump debe ser >= la versión del servidor, y Debian trae 15)
RUN install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
       https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends postgresql-client-18 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY assets ./assets

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
