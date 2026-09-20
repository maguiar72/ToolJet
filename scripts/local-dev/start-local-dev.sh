#!/usr/bin/env bash
# Inicia os serviços do ToolJet em desenvolvimento: PostgREST, backend (NestJS) e frontend (webpack).
# Logs em ./.local-dev/*.log. Para encerrar: bash scripts/local-dev/stop-local-dev.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm use "$(node -p "require('./server/package.json').engines.node")" >/dev/null

set -a; . ./.env; set +a
LOGDIR="$ROOT/.local-dev"; mkdir -p "$LOGDIR"

(service postgresql start >/dev/null 2>&1 || sudo service postgresql start >/dev/null 2>&1 || true)
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes >/dev/null

cat > "$LOGDIR/postgrest.conf" <<CONF
db-uri = "postgres://${TOOLJET_DB_USER}:${TOOLJET_DB_PASS}@${TOOLJET_DB_HOST}:${PG_PORT:-5432}/${TOOLJET_DB}"
db-schemas = "public"
db-anon-role = "${TOOLJET_DB_USER}"
db-pre-config = "${PGRST_DB_PRE_CONFIG:-postgrest.pre_config}"
jwt-secret = "${PGRST_JWT_SECRET}"
server-host = "127.0.0.1"
server-port = 3001
log-level = "info"
CONF

pgrep -x postgrest >/dev/null || (setsid nohup postgrest "$LOGDIR/postgrest.conf" >"$LOGDIR/postgrest.log" 2>&1 < /dev/null &)
pgrep -f "nest start" >/dev/null || (cd server && setsid nohup npm run start:dev >"$LOGDIR/server.log" 2>&1 < /dev/null &)
pgrep -f "webpack serve" >/dev/null || (cd frontend && setsid nohup npm start >"$LOGDIR/frontend.log" 2>&1 < /dev/null &)

echo "Aguardando backend (http://localhost:${PORT:-3000}/api/health)..."
for _ in $(seq 1 120); do
  curl -sf "http://localhost:${PORT:-3000}/api/health" >/dev/null && break
  sleep 3
done
curl -s "http://localhost:${PORT:-3000}/api/health"; echo
echo "Frontend: http://localhost:8082  (a primeira compilação do webpack leva alguns minutos; ver $LOGDIR/frontend.log)"
