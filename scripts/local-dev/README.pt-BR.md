# ToolJet — ambiente local de desenvolvimento (Ubuntu / WSL2)

Roteiro validado em 20/09/2026 sobre a `main` do ToolJet (v3.21.71-beta, edição **CE**),
Node 22.15.1, PostgreSQL 16, Redis 7 e PostgREST 12.2.0. No Windows, execute tudo dentro
de uma distribuição Ubuntu no **WSL2**, conforme `docs/docs/contributing-guide/setup/windows.md`.

## 1. Pré-requisitos (uma única vez)

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3 unzip curl git openssl postgresql redis-server
```

Node e npm são instalados pelo script via `nvm`, na versão exata exigida por
`server/package.json` (`engine-strict=true` em `server/.npmrc` recusa outras versões).

## 2. Instalação

```bash
git clone https://github.com/<sua-conta>/ToolJet.git
cd ToolJet
bash scripts/local-dev/setup-local-dev.sh
```

O script:

1. instala Node/npm pelo `nvm`;
2. inicia PostgreSQL e Redis e define a senha do usuário `postgres` (padrão `postgres`, ajustável com `PG_ADMIN_PASS`);
3. instala o binário do PostgREST em `/usr/local/bin`;
4. gera o `.env` com chaves aleatórias (`LOCKBOX_MASTER_KEY`, `SECRET_KEY_BASE`, `PGRST_JWT_SECRET`);
5. instala as dependências (raiz, `server`, `plugins`, `frontend`) e compila os plugins;
6. cria os bancos `tooljet_development`, `tooljet_db` e `sample_db` e executa as migrações.

## 3. Operação

```bash
bash scripts/local-dev/start-local-dev.sh   # sobe PostgREST (3001), backend (3000) e frontend (8082)
bash scripts/local-dev/stop-local-dev.sh    # encerra os três
```

Logs em `.local-dev/`. Acesse `http://localhost:8082`; no primeiro acesso o ToolJet pede a
criação do administrador e do primeiro workspace. Também é possível criar pela API:

```bash
curl -X POST http://localhost:3000/api/onboarding/setup-super-admin \
  -H 'Content-Type: application/json' \
  -d '{"name":"Nome","email":"usuario@dominio","password":"<senha>","workspaceName":"STI-CJF"}'
```

## 4. Verificações

| Serviço   | Verificação                                   | Esperado                        |
|-----------|-----------------------------------------------|---------------------------------|
| Backend   | `curl http://localhost:3000/api/health`       | `{"status":"healthy", ...}`     |
| PostgREST | `curl -I http://localhost:3001/`              | `HTTP/1.1 200 OK`               |
| Frontend  | `curl -I http://localhost:8082/`              | `HTTP/1.1 200 OK`               |
| Redis     | `redis-cli ping`                              | `PONG`                          |

## 5. Problemas conhecidos e contornos

| Sintoma | Causa | Contorno |
|---|---|---|
| `listen EAFNOSUPPORT :::3000` | Host sem IPv6; o backend escuta em `::` por padrão | `LISTEN_ADDR=0.0.0.0` no `.env` (já incluído pelo script) |
| `Could not locate the bindings file ... ibm_db` ao migrar | O `postinstall` do conector IBM Db2 baixa o *clidriver* de `public.dhe.ibm.com`; bloqueado por proxy | Baixe `linuxx64_odbc_cli.tar.gz` (repositório `ibmdb/db2drivers`, pasta `clidriver/`), copie para `plugins/node_modules/ibm_db/installer/` e rode `IBM_DB_INSTALLER_URL=$PWD/plugins/node_modules/ibm_db/installer/ node plugins/node_modules/ibm_db/installer/driverInstall.js` |
| `403 GET https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz` | `frontend/package.json` aponta o `xlsx` para o CDN da SheetJS | Libere o host no proxy. Em último caso, instale com o espelho `npm:@e965/xlsx@0.20.3` (mesmo build) sem versionar a alteração em `package.json`/`package-lock.json` |
| `Unable to download sentry-cli binary` | `@sentry/cli` baixa binário de `downloads.sentry-cdn.com` | `SENTRYCLI_SKIP_DOWNLOAD=1 npm install --prefix frontend` (já incluído pelo script) |
| `db:migrate` falha por `@tooljet/plugins/dist/server` | Plugins não compilados | `npm run build:plugins` antes de migrar |

## 6. Referências do repositório

- `AGENTS.md` (raiz) — arquitetura, edições e comandos de desenvolvimento.
- `docs/docs/contributing-guide/setup/ubuntu.md` e `windows.md` — roteiro oficial.
- `.env.example` — referência de variáveis de ambiente.
- `server/dev-entrypoint.sh` — sequência de inicialização usada pelo `docker-compose-debug.yaml`.
