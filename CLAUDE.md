# CLAUDE.md — MCP v7 (Managed Control Platform)

This file provides context for AI assistants working on this codebase.

## Project Overview

MCP (Managed Control Platform) is a self-hosted, AI-powered IT operations center for managed service providers (MSPs). It orchestrates 32+ Docker containers across 5 isolated networks, combining industry-standard monitoring tools (Zabbix, Grafana, Loki) with a local AI stack (Ollama + LangChain + pgvector) that analyzes events in real-time and generates actionable tickets in Zammad.

**Version:** 7.x (Beta)
**License:** Proprietary
**Target OS:** Debian 13 (Trixie)
**Language:** Primarily Bash scripts and Python (FastAPI + LangChain)

## Repository Structure

```
Masdor-MCP/
├── compose/                    # Docker Compose files (one per stack)
│   ├── core/docker-compose.yml     # #1-#8: PostgreSQL, Redis, pgvector, OpenBao, nginx, Keycloak, n8n, ntfy
│   ├── ops/docker-compose.yml      # #9-#16: Zammad (4x), Elasticsearch, BookStack, Vaultwarden, Portainer, DIUN
│   ├── telemetry/docker-compose.yml # #17-#24: Zabbix (2x), Grafana, Loki, Alloy, Uptime Kuma, CrowdSec, Renderer
│   ├── remote/docker-compose.yml   # #25-#27: MeshCentral, Guacamole, Guacd
│   └── ai/docker-compose.yml      # #28-#32: Ollama, LiteLLM, LangChain Worker, AI Gateway, Redis Queue
├── containers/                 # Custom container source code (built locally)
│   ├── ai-gateway/            # FastAPI app — central AI API (Python)
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── app/
│   │       ├── main.py        # FastAPI endpoints (/analyze, /embed, /search, /ingest, /health, /metrics)
│   │       ├── config.py      # Settings from environment variables
│   │       ├── models/schemas.py  # Pydantic request/response models
│   │       └── services/      # ollama_client.py, rag_service.py
│   └── langchain-worker/      # Queue worker — processes AI analysis jobs (Python)
│       ├── Dockerfile
│       ├── requirements.txt
│       └── app/
│           ├── worker.py      # Main loop: Redis queue → RAG → LLM → Zammad ticket → ntfy
│           ├── config.py
│           ├── prompts.py     # Prompt templates for LLM analysis
│           └── services/      # llm_client.py, pgvector_service.py, zammad_client.py, ntfy_client.py
├── config/                    # Configuration files mounted into containers
│   ├── ai/
│   │   ├── models.yml         # LiteLLM model routing config (Ollama backend)
│   │   ├── rag-config.yml     # RAG pipeline settings (chunking, retrieval, queue)
│   │   └── prompts/           # LLM prompt templates (alert-analysis.txt)
│   ├── nginx/
│   │   ├── nginx.conf         # Main nginx config (security headers, gzip, etc.)
│   │   ├── conf.d/default.conf # Reverse proxy routes for all services
│   │   └── dashboard/index.html # Landing page dashboard
│   ├── grafana/               # Datasource provisioning, dashboard JSON
│   ├── loki/loki-config.yml   # Loki log aggregation config
│   ├── alloy/config.alloy     # Grafana Alloy log collector config
│   ├── crowdsec/acquis.yml    # CrowdSec acquisition config
│   ├── n8n/workflows/         # n8n workflow JSON files (W1-W4)
│   ├── ntfy/server.yml        # ntfy push notification config
│   └── keycloak/, portainer/  # Placeholder dirs
├── scripts/                   # Operational scripts
│   ├── mcp-install.sh         # Full 7-phase installation with gate checks
│   ├── mcp-start.sh           # Start all stacks in dependency order
│   ├── mcp-stop.sh            # Stop all stacks in reverse order
│   ├── mcp-status.sh          # Show status of all containers
│   ├── mcp-backup.sh          # Create full backup
│   ├── mcp-restore.sh         # Restore from backup
│   ├── mcp-pull-images.sh     # Pull all Docker images
│   ├── gen-test-env.sh        # Generate .env with random secrets for testing
│   ├── init-db.sh             # PostgreSQL init: creates all roles and databases
│   └── init-pgvector.sh       # pgvector init: creates vector tables and extensions
├── tests/                     # Test suites (Bash)
│   ├── smoke-test.sh          # Verifies all 32 containers are running/healthy
│   ├── ai-pipeline-test.sh    # End-to-end AI pipeline: alert → queue → analysis
│   └── security-test.sh       # Network isolation, port exposure, container security
├── Makefile                   # Primary entry point for all operations
├── .env                       # Environment variables / secrets (git-ignored)
├── .gitignore
├── Tipps.md                   # Known errors, fixes, and design patterns (German)
├── Systemarchitektur.md       # System architecture documentation (German)
├── SECURITY.md                # Security policy and vulnerability reporting
└── docs/                      # Additional documentation and assets
```

## Key Commands

All common operations go through the Makefile:

```bash
make help               # Show all available targets
make up                 # Start all stacks (Core → Ops → Telemetry → Remote → AI)
make down               # Stop all stacks (reverse order)
make restart            # Restart all stacks
make status             # Show status of all containers
make ps                 # Docker ps for MCP containers
make test               # Run all tests (smoke + AI pipeline + security)
make test-smoke         # Run smoke tests only
make test-ai            # Run AI pipeline tests only
make test-security      # Run security tests only
make logs               # Tail logs for all stacks
make logs-ai            # Tail AI stack logs only
make backup             # Create full backup
make install            # Run full installation (7 phases with gates)
make clean              # Stop all + remove volumes (DESTRUCTIVE)
```

Individual stack operations: `make up-core`, `make up-ops`, `make up-telemetry`, `make up-remote`, `make up-ai` (and corresponding `down-*` and `logs-*` targets).

## Architecture: 5 Stacks, 5 Networks

| Stack | Compose File | Containers | Purpose |
|-------|-------------|------------|---------|
| Core | `compose/core/` | #1-#8 | Databases, identity, proxy, automation, notifications |
| Ops | `compose/ops/` | #9-#16 (+init) | Ticketing (Zammad), wiki (BookStack), passwords, Docker mgmt |
| Telemetry | `compose/telemetry/` | #17-#24 | Monitoring (Zabbix), dashboards (Grafana), logs (Loki), IDS (CrowdSec) |
| Remote | `compose/remote/` | #25-#27 | Remote desktop (MeshCentral, Guacamole) |
| AI | `compose/ai/` | #28-#32 | LLM inference (Ollama), model router (LiteLLM), RAG worker, API gateway |

| Network | Subnet | Purpose |
|---------|--------|---------|
| `mcp-edge-net` | 172.20.0.0/24 | External ingress (nginx only) |
| `mcp-app-net` | 172.20.1.0/24 | Internal app communication |
| `mcp-data-net` | 172.20.2.0/24 | Database access only |
| `mcp-sec-net` | 172.20.3.0/24 | Security tools (CrowdSec, OpenBao) |
| `mcp-ai-net` | 172.20.4.0/24 | AI stack internal |

All networks and volumes are **external** (created by `mcp-install.sh` Phase 2), not auto-created by Compose.

## Custom Containers (Python)

Two containers are built from source in `containers/`:

### AI Gateway (`containers/ai-gateway/`)
- **Framework:** FastAPI
- **Port:** 8000 (internal only)
- **Key endpoints:**
  - `POST /api/v1/analyze` — Accept alert, deduplicate via Redis, queue for processing
  - `POST /api/v1/embed` — Create and store embedding in pgvector
  - `GET /api/v1/search` — RAG similarity search
  - `POST /api/v1/ingest` — Chunk document + embed + store
  - `GET /health` — Dependency health check (Redis, Ollama, LiteLLM, pgvector, Zammad, ntfy)
  - `GET /metrics` — Prometheus metrics
- **Auth:** Bearer token via `AI_GATEWAY_SECRET` env var
- **Dependencies:** httpx, redis, fastapi, prometheus_client, asyncpg

### LangChain Worker (`containers/langchain-worker/`)
- **Type:** Long-running queue consumer (Redis BRPOP)
- **Pipeline:** Redis queue → RAG search (pgvector) → prompt assembly → LLM call (LiteLLM with Ollama fallback) → Zammad ticket creation → ntfy notification → store results + embedding
- **Dependencies:** redis, psycopg2, httpx

## Critical Rules and Conventions

### Security Rules (NEVER violate)
1. **NEVER expose the AI Gateway to the public internet.** It must remain on `mcp-ai-net` and `mcp-app-net` only.
2. **NEVER commit `.env` or secrets to version control.** The `.env` file contains all passwords and is git-ignored.
3. **Only nginx exposes ports on `0.0.0.0`** (ports 80/443). All other services use `expose:` only.
4. All containers use `security_opt: [no-new-privileges:true]`.

### Docker Compose Conventions
1. **Use service names (not container names) for DNS.** Docker DNS resolves service names (e.g., `postgres`), not container names (e.g., `mcp-postgres`). This applies to all configs, `.env`, and nginx upstream definitions.
   - `docker compose up/down/restart` → service names (e.g., `zammad-init`)
   - `docker logs/exec/inspect` → container names (e.g., `mcp-zammad-init`)
2. **`COMPOSE_PROJECT_NAME=mcp`** must be set in `.env`. Without it, multi-compose setups produce orphan warnings.
3. **All networks and volumes are external.** They are pre-created by `mcp-install.sh` and referenced with `external: true`.
4. **Image tags must be exact versions** (e.g., `7.0.0-alpine` not `7.0-alpine`). Check the registry (Docker Hub vs GHCR vs Quay) before specifying images.

### Healthcheck Conventions
1. Always use `127.0.0.1` instead of `localhost` (avoids IPv6 resolution issues).
2. Always verify the correct protocol (HTTP vs HTTPS) for each service.
3. Always check the correct context path (e.g., `/guacamole/` not `/`).
4. Use `start_period: 120s` for services with database migrations (Keycloak, n8n, Zammad).
5. Check which tool is available in the container (`wget` vs `curl` vs Python stdlib).

### Database Conventions
- `scripts/init-db.sh` creates all roles with `CREATEDB` permission and all databases.
- Affected roles: zammad, n8n, bookstack, keycloak, grafana, zabbix, guacamole.
- pgvector has its own dedicated instance and init script (`init-pgvector.sh`).

### Code Style (Python — custom containers)
- Docstrings and comments are in **German** (the project's primary language).
- Logging uses `%(asctime)s [%(levelname)s] %(message)s` format.
- Config is loaded from environment variables via a `settings` object (`app/config.py`).
- Both custom containers use Python stdlib for health checks (no curl dependency inside containers).

### Nginx Conventions
- All services are accessed via nginx reverse proxy subpaths (e.g., `/grafana/`, `/tickets/`, `/wiki/`).
- Security headers are set globally: `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`.
- `client_max_body_size 50m` for file uploads.
- Upstream references must use Docker service names, not container names.

## Installation Flow

The installer (`scripts/mcp-install.sh`) runs 7 phases with gate checks:

| Phase | Description | Gate |
|-------|-------------|------|
| 1 | Preflight: Docker, .env, RAM, disk, GPU, sysctl | All checks pass |
| 2 | Environment: Create 5 networks + 20 volumes + validate YAML | All resources exist |
| 3 | Core Stack: PostgreSQL, Redis, pgvector, OpenBao, nginx, Keycloak, n8n, ntfy | All containers healthy |
| 4 | Ops Stack: Zammad (init + 3 services), ES, BookStack, Vaultwarden, Portainer, DIUN | All containers healthy |
| 5 | Telemetry Stack: Zabbix, Grafana, Loki, Alloy, Uptime Kuma, CrowdSec, Renderer | All containers healthy |
| 6 | AI Stack: Ollama (+ model pull), LiteLLM, LangChain, AI Gateway, Redis Queue | AI Gateway healthy |
| 7 | Remote Stack: MeshCentral, Guacamole, Guacd | Containers running |

Resume from a failed phase: `sudo bash scripts/mcp-install.sh --resume-from phase3`

## Testing

Three test suites are available (all Bash):

1. **Smoke test** (`tests/smoke-test.sh`): Checks all 32 containers are running/healthy with zero restarts. Also tests HTTP endpoints for all nginx-proxied services.
2. **AI pipeline test** (`tests/ai-pipeline-test.sh`): End-to-end test of the AI pipeline — checks gateway health, Ollama models, Redis queue, sends a test alert, and verifies job creation.
3. **Security test** (`tests/security-test.sh`): Validates that only nginx exposes ports, 5 networks exist, AI Gateway is not on the edge network, and `no-new-privileges` is set.

Run all: `make test`

## AI Pipeline Flow

```
Alert (Zabbix/Loki/CrowdSec/manual)
  → AI Gateway (/api/v1/analyze)
    → Redis deduplication (15-min window)
    → Redis queue (mcp:queue:analyze)
      → LangChain Worker picks up job
        → RAG search in pgvector (similar past incidents)
        → Build prompt with context
        → LLM inference via LiteLLM (Ollama backend)
        → Parse structured JSON response
        → Create Zammad ticket (if high severity + confidence)
        → Send ntfy notification
        → Store analysis result as embedding (for future RAG)
        → Log to audit table in pgvector
```

## Environment Variables

All configuration is in `.env` (git-ignored). Key variable groups:

- `COMPOSE_PROJECT_NAME=mcp` — Required for multi-compose setup
- `MCP_HOST_IP` — Server IP for nginx and service URLs
- `POSTGRES_*`, `PGVECTOR_*`, `REDIS_*` — Database credentials
- `KEYCLOAK_*`, `N8N_*`, `ZAMMAD_*`, `GRAFANA_*`, `ZABBIX_*`, `GUACAMOLE_*`, `BOOKSTACK_*` — Per-service DB credentials
- `AI_GATEWAY_SECRET` — Bearer token for AI Gateway API
- `ZAMMAD_AI_TOKEN` — Token for Zammad ticket creation
- `OLLAMA_MODEL`, `EMBEDDING_MODEL` — AI model selection
- `LITELLM_MASTER_KEY` — LiteLLM API key

Generate a test `.env` with random secrets: `bash scripts/gen-test-env.sh`

## Known Issues and Gotchas

See `Tipps.md` for the full list of 21 documented issues with solutions. Key ones:

- **Service names vs container names:** Docker DNS only resolves service names. All configs must use `postgres` not `mcp-postgres`.
- **Zabbix image tags:** Must use full version `7.0.0-alpine`, not `7.0-alpine`.
- **MeshCentral:** Image is on GHCR (`ghcr.io/ylianst/meshcentral`), not Docker Hub.
- **Loki retention:** Set `retention_period: 0` to prevent compactor crash in single-node mode.
- **n8n workflows:** Imported workflows are inactive by default; must be activated post-import.
- **WSL development:** Project must be on the Linux filesystem (`~/...`), not `/mnt/c/`.
- **CrowdSec:** Runs in offline mode (`DISABLE_ONLINE_API: "true"`).
- **Two Redis instances:** `mcp-redis` (Core stack, cache/queue) and `mcp-redis-queue` (AI stack, job queue). Do not confuse them.

## Deployment Checklist

Before any deployment, verify:

- [ ] `.env` contains `COMPOSE_PROJECT_NAME=mcp`
- [ ] All image tags are exact versions (not `:latest` in production)
- [ ] All DB hosts in `.env` and compose use service names (not `mcp-*`)
- [ ] All nginx configs use service names for upstreams
- [ ] `init-db.sh` creates all databases and roles with `CREATEDB`
- [ ] Healthchecks use `127.0.0.1` and correct protocol
- [ ] Zammad has `RAILS_SERVE_STATIC_FILES=true`
- [ ] Loki has `retention_period: 0` (or compactor properly configured)
- [ ] No `ports:` on `0.0.0.0` except nginx (80/443)
- [ ] AI Gateway is NOT on `mcp-edge-net`
