#!/usr/bin/env bash
# Migra la BD de Railway (plan gratuito agotado) al Postgres local (Docker).
# Uso:  bash migrar_railway_a_local.sh
# Lee la URL de Railway de la línea "# DATABASE_URL_RAILWAY=..." del .env
# (quedó comentada al apuntar DATABASE_URL al Postgres local).
set -euo pipefail
cd "$(dirname "$0")"

RAILWAY_URL=$(grep -oP '^# DATABASE_URL_RAILWAY=\K.*' .env)
[ -z "$RAILWAY_URL" ] && { echo "No encontré DATABASE_URL_RAILWAY en .env"; exit 1; }

echo "1/3 Dump desde Railway (puede tardar)…"
docker exec ezyro-pg pg_dump "$RAILWAY_URL" -Fc -f /tmp/ezyro.dump

echo "2/3 Restore en el Postgres local (BD ezyro)…"
docker exec ezyro-pg pg_restore -U postgres -d ezyro --clean --if-exists --no-owner --no-privileges /tmp/ezyro.dump || true
# pg_restore devuelve warnings por extensiones/ownership de Railway — inofensivos.

echo "3/3 Verificación:"
docker exec ezyro-pg psql -U postgres -d ezyro -c "SELECT (SELECT count(*) FROM usuario) AS usuarios, (SELECT count(*) FROM empresa) AS empresas;"
echo "Listo. Arranca el API con:  python -m uvicorn app.main:app --host 0.0.0.0 --port 8000"
