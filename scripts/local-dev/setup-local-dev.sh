#!/usr/bin/env bash
# Prepara um ambiente local de desenvolvimento do ToolJet (CE) em Ubuntu / WSL2.
# Idempotente: pode ser executado mais de uma vez.
#
# Pré-requisitos do sistema (Ubuntu 22.04/24.04):
#   sudo apt-get install -y build-essential python3 unzip curl git postgresql redis-server
#
# Uso:
#   bash scripts/local-dev/setup-local-dev.sh
#
# Variáveis opcionais:
#   PG_ADMIN_PASS      senha do usuário postgres (padrão: postgres)
#   SKIP_SYSTEM_START  =1 para não iniciar postgresql/redis (quando já gerenciados por systemd)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

NODE_VERSION="$(node -p "require('./server/package.json').engines.node")"
NPM_VERSION="$(node -p "require('./server/package.json').engines.npm" 2>/dev/null || echo 10.9.2)"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-postgres}"
POSTGREST_VERSION="v12.2.0"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- Node via nvm
log "Node ${NODE_VERSION} / npm ${NPM_VERSION} via nvm"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$NODE_VERSION" >/dev/null
nvm use "$NODE_VERSION" >/dev/null
nvm alias default "$NODE_VERSION" >/dev/null
npm install -g "npm@${NPM_VERSION}" >/dev/null 2>&1 || true
node -v; npm -v

# ------------------------------------------------------- PostgreSQL e Redis
if [ "${SKIP_SYSTEM_START:-0}" != "1" ]; then
  log "Iniciando PostgreSQL e Redis"
  (sudo service postgresql start 2>/dev/null || service postgresql start 2>/dev/null || true)
  (sudo service redis-server start 2>/dev/null || service redis-server start 2>/dev/null || redis-server --daemonize yes >/dev/null 2>&1 || true)
fi
log "Definindo senha do usuário postgres"
(sudo -u postgres psql -c "ALTER USER postgres PASSWORD '${PG_ADMIN_PASS}';" 2>/dev/null \
  || su postgres -c "psql -c \"ALTER USER postgres PASSWORD '${PG_ADMIN_PASS}';\"") >/dev/null

# ------------------------------------------------------------------ PostgREST
if ! command -v postgrest >/dev/null 2>&1; then
  log "Instalando PostgREST ${POSTGREST_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/postgrest.tar.xz" \
    "https://github.com/PostgREST/postgrest/releases/download/${POSTGREST_VERSION}/postgrest-${POSTGREST_VERSION}-linux-static-x64.tar.xz"
  tar -xJf "$tmp/postgrest.tar.xz" -C "$tmp"
  (sudo install -m 755 "$tmp/postgrest" /usr/local/bin/postgrest 2>/dev/null || install -m 755 "$tmp/postgrest" /usr/local/bin/postgrest)
  rm -rf "$tmp"
fi

# ------------------------------------------------------------------------ .env
if [ ! -f .env ]; then
  log "Gerando .env com chaves aleatórias"
  cat > .env <<ENV
TOOLJET_EDITION=ce
TOOLJET_HOST=http://localhost:8082
LOCKBOX_MASTER_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
MFA_MASTER_SECRET=$(openssl rand -hex 32)
NODE_ENV=development
PORT=3000
LISTEN_ADDR=0.0.0.0
LOG_LEVEL=info
ORM_LOGGING=error

# Banco principal
PG_HOST=localhost
PG_PORT=5432
PG_USER=postgres
PG_PASS=${PG_ADMIN_PASS}
PG_DB=tooljet_development

# ToolJet Database (PostgREST)
TOOLJET_DB=tooljet_db
TOOLJET_DB_USER=postgres
TOOLJET_DB_HOST=localhost
TOOLJET_DB_PASS=${PG_ADMIN_PASS}
TOOLJET_DB_RECONFIG=true
TOOLJET_DB_STATEMENT_TIMEOUT=60000
PGRST_HOST=http://localhost:3001
PGRST_JWT_SECRET=$(openssl rand -hex 32)
PGRST_DB_PRE_CONFIG=postgrest.pre_config

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

CHECK_FOR_UPDATES=false
ENV
else
  log ".env já existe; mantido"
fi

# ------------------------------------------------------------ Dependências
log "Instalando dependências (raiz, server, plugins, frontend)"
npm install --no-audit --no-fund
npm install --no-audit --no-fund --prefix server
npm install --no-audit --no-fund --prefix plugins
# SENTRYCLI_SKIP_DOWNLOAD evita o download do binário do Sentry (não é necessário em desenvolvimento).
SENTRYCLI_SKIP_DOWNLOAD=1 npm install --no-audit --no-fund --prefix frontend

log "Compilando plugins (pré-requisito das migrações)"
npm run build:plugins

# ------------------------------------------------------------------ Banco
log "Criando bancos e executando migrações"
npm run --prefix server db:create || true
npm run --prefix server db:migrate

log "Concluído. Inicie os serviços com: bash scripts/local-dev/start-local-dev.sh"
