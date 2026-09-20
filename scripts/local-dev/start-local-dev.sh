#!/usr/bin/env bash
# Inicia os serviços do ToolJet em desenvolvimento: PostgREST, backend (NestJS) e frontend (webpack).
# Logs em ./.local-dev/*.log. Para encerrar: bash scripts/local-dev/stop-local-dev.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  echo "nvm não encontrado em $NVM_DIR. Execute antes: bash scripts/local-dev/setup-local-dev.sh" >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh" --no-use   # --no-use: nao ativar a versao do .nvmrc antes de instalada
nvm use "$(tr -d 'v[:space:]' < .nvmrc)" >/dev/null

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

echo "Aguardando backend (http://localhost:${PORT:-3000}/api/health); a primeira compilação leva alguns minutos..."
ok=0
for i in $(seq 1 200); do
  if curl -sf "http://localhost:${PORT:-3000}/api/health" >/dev/null; then ok=1; break; fi
  if ! pgrep -f "nest start" >/dev/null; then
    echo; echo "O processo do backend encerrou. Últimas linhas de $LOGDIR/server.log:" >&2
    tail -n 60 "$LOGDIR/server.log" >&2; exit 1
  fi
  [ $((i % 10)) -eq 0 ] && echo "  ... ainda compilando/iniciando ($((i*3))s)"
  sleep 3
done
if [ "$ok" -ne 1 ]; then
  echo; echo "Backend não respondeu em 10 minutos. Últimas linhas de $LOGDIR/server.log:" >&2
  tail -n 60 "$LOGDIR/server.log" >&2; exit 1
fi
echo "Backend OK: $(curl -s "http://localhost:${PORT:-3000}/api/health")"
echo "PostgREST: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/)  Redis: $(redis-cli ping 2>/dev/null || echo sem resposta)"
echo "Frontend: http://localhost:8082  (aguarde 'compiled' em $LOGDIR/frontend.log: tail -f $LOGDIR/frontend.log)"
