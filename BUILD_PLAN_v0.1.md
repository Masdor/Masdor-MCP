# Masdor-MCP 0.1 — Build Plan & 10-Phase Design

> **Document Type:** Master Build Plan
> **Version:** 0.1
> **Date:** 2026-02-17
> **Status:** Planning Phase — No Code Yet
> **Branch:** `claude/masdor-mcp-planning-Y9tSc`

---

## Executive Summary

### What is Masdor-MCP?

Masdor-MCP is a **fully self-hosted, AI-powered IT Operations Center** designed for MSPs and IT teams. It orchestrates **32 Docker containers** across **5 isolated networks**, combining industry-standard monitoring tools (Zabbix, Grafana, Zammad, Loki) with a **local AI stack** (Ollama + LangChain + pgvector) that analyzes events in real-time and generates professional, actionable tickets automatically.

### Core Philosophy

```
100% Offline → AI-First → Zero-Trust → Human-in-the-Loop → One Script, One Command
```

### Current State of the Repository

| What Exists | What Does NOT Exist |
|---|---|
| Complete architecture documentation (Plan.md) | Docker Compose files |
| System architecture deep-dive (Systemarchitektur.md) | Shell scripts (install, start, stop) |
| Multi-language READMEs (EN, DE, AR) | Configuration templates |
| Security policy (SECURITY.md) | Custom container source code |
| Troubleshooting guide with 21 issues (Tipps.md) | .env.example |
| | Makefile |
| | Tests |
| | n8n workflow JSON files |

**Conclusion:** The project is in a **specification-complete, implementation-zero** state. All architecture is documented. Nothing is built yet.

---

## Understanding Analysis — Key Findings

### 1. Architecture Complexity Map

```
                           ┌──────────────────────┐
                           │    5 Docker Networks   │
                           │  (edge/app/data/sec/ai)│
                           └──────────┬───────────┘
                                      │
               ┌──────────────────────┼──────────────────────┐
               │                      │                      │
        ┌──────┴──────┐      ┌───────┴───────┐      ┌──────┴──────┐
        │  5 Stacks    │      │  32 Containers │      │  8 Workflows │
        │ Core/Ops/Tel │      │  (see below)   │      │  (W1-W8)     │
        │ Remote/AI    │      │                │      │  via n8n     │
        └─────────────┘      └───────────────┘      └─────────────┘
```

### 2. Container Distribution

| Stack | Count | Containers | Complexity |
|-------|-------|------------|------------|
| **Core** | 8 | postgres, redis, pgvector, openbao, nginx, keycloak, n8n, ntfy | HIGH — Foundation dependencies |
| **Ops** | 8 | zammad(3), elasticsearch, bookstack, vaultwarden, portainer, diun | HIGH — Multi-container Zammad |
| **Telemetry** | 8 | zabbix(2), grafana, loki, alloy, uptime-kuma, crowdsec, grafana-renderer | MEDIUM — Standard configs |
| **Remote** | 3 | meshcentral, guacamole, guacd | LOW — Mostly standalone |
| **AI** | 5 | ollama, litellm, langchain, ai-gateway, redis-queue | VERY HIGH — Custom builds |

### 3. Critical Dependencies Chain

```
PostgreSQL → (Keycloak, n8n, Zammad, Zabbix, Grafana, BookStack)
Redis      → (n8n cache, deduplication)
pgvector   → (RAG pipeline, AI knowledge base)
nginx      → (ALL web services — single entry point)
Keycloak   → (SSO for Grafana, Zammad, potentially others)
n8n        → (ALL 8 AI workflows W1-W8)
Ollama     → (ALL AI analysis — GPU required)
```

### 4. Known Risks & Complexity Hotspots

| Risk | Severity | Mitigation in Plan |
|------|----------|-------------------|
| Docker service-name vs container-name confusion | HIGH | Phase 2: Naming convention + validation |
| Port exposure on 0.0.0.0 | HIGH | Phase 2: Only nginx on 80/443 |
| Zammad multi-container setup (init + rails + ws + worker) | HIGH | Phase 4: Dedicated sub-phase |
| AI custom container builds (gateway, langchain) | VERY HIGH | Phase 8: Isolated development |
| n8n workflow activation after import | MEDIUM | Phase 7: Automated activation script |
| CrowdSec offline mode | MEDIUM | Phase 6: Local-only configuration |
| Loki retention configuration | LOW | Phase 5: retention_period: 0 |

### 5. Document Inconsistencies Found

| Issue | Plan.md Says | Systemarchitektur.md Says | README.md Says |
|-------|-------------|--------------------------|----------------|
| Container count | 32 | 32 | 33 (32+1 init) |
| AI stack containers | ollama, litellm, langchain, ai-gateway, redis-queue | Same | ollama, ai-gateway, event-processor, vector-worker, langchain, prometheus, alertmanager |
| Stacks | 5 stacks (8+8+8+3+5) | Same | Different grouping |

**Decision for v0.1:** Follow **Systemarchitektur.md** (the detailed German plan) as the source of truth — 32 containers, 5 stacks (8+8+8+3+5).

---

## The 10-Phase Build Plan

```
┌─────────────────────────────────────────────────────────────────────┐
│                   MASDOR-MCP 0.1 BUILD PHASES                       │
│                                                                     │
│  Phase 1:  Foundation & Environment Setup                           │
│  Phase 2:  Docker Networks & Volume Architecture                    │
│  Phase 3:  Core Stack — Databases, Identity, Proxy                  │
│  Phase 4:  Ops Stack — Ticketing, Wiki, Tools                       │
│  Phase 5:  Telemetry Stack — Monitoring & Logging                   │
│  Phase 6:  Security Stack — CrowdSec & Hardening                   │
│  Phase 7:  Remote Stack — Remote Access                             │
│  Phase 8:  AI Stack — Local AI Engine                               │
│  Phase 9:  Integration — Workflows, Pipelines, Dashboard            │
│  Phase 10: Testing, Validation & Documentation                      │
│                                                                     │
│  Each phase has a GATE CHECK — no phase proceeds without passing    │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Phase 1: Foundation & Environment Setup

**Goal:** Create the project skeleton, .env template, Makefile, and all foundational scripts.

**Deliverables:**

| # | Deliverable | File(s) |
|---|-------------|---------|
| 1.1 | Project directory structure | All directories as per Plan.md Section 11 |
| 1.2 | `.env.example` with ALL variables | `.env.example` |
| 1.3 | `Makefile` with shortcuts | `Makefile` |
| 1.4 | `scripts/init-db.sh` | PostgreSQL init (all DBs + roles + CREATEDB) |
| 1.5 | `scripts/mcp-install.sh` skeleton | 6-phase gate system (structure only) |
| 1.6 | `scripts/mcp-start.sh` | Stack start orchestration |
| 1.7 | `scripts/mcp-stop.sh` | Ordered shutdown (AI→Remote→Tel→Ops→Core) |
| 1.8 | `scripts/mcp-status.sh` | Status of all 32 containers |

**Variables in .env.example (grouped):**

```
# === PROJECT ===
COMPOSE_PROJECT_NAME=mcp
MCP_HOST_IP=192.168.1.100
MCP_DOMAIN=mcp.local

# === POSTGRESQL ===
POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
# Per-service DBs: KEYCLOAK_DB_*, ZAMMAD_DB_*, N8N_DB_*, BOOKSTACK_DB_*, ZABBIX_DB_*, GRAFANA_DB_*

# === REDIS ===
REDIS_PASSWORD

# === KEYCLOAK ===
KC_DB_URL, KEYCLOAK_ADMIN, KEYCLOAK_ADMIN_PASSWORD

# === AI ===
AI_GATEWAY_SECRET, OLLAMA_MODEL, EMBEDDING_MODEL

# === IMAGE TAGS ===
(All 32 container image tags with exact versions)
```

**Gate Check 1:**
- [ ] All directories exist
- [ ] `.env.example` contains all required variables
- [ ] `Makefile` has targets: up, down, status, logs, test, backup
- [ ] All scripts are executable and pass shellcheck

---

### Phase 2: Docker Networks & Volume Architecture

**Goal:** Define the 5 isolated networks and all persistent volumes.

**Deliverables:**

| # | Deliverable | Detail |
|---|-------------|--------|
| 2.1 | Network definitions | 5 networks in each compose file |
| 2.2 | Volume definitions | Named volumes for all persistent data |
| 2.3 | Network assignment matrix | Which container joins which network(s) |

**Network Architecture:**

| Network | Subnet | IPAM | Purpose |
|---------|--------|------|---------|
| `mcp-edge-net` | 172.20.0.0/24 | driver: bridge | Only nginx — external entry |
| `mcp-app-net` | 172.20.1.0/24 | driver: bridge | All app services |
| `mcp-data-net` | 172.20.2.0/24 | driver: bridge | Databases only |
| `mcp-sec-net` | 172.20.3.0/24 | driver: bridge | Security tools |
| `mcp-ai-net` | 172.20.4.0/24 | driver: bridge | AI stack isolated |

**Volume List (17 named volumes):**

```
mcp-postgres-data, mcp-pgvector-data, mcp-redis-data,
mcp-elasticsearch-data, mcp-keycloak-data, mcp-n8n-data,
mcp-zammad-data, mcp-bookstack-data, mcp-vaultwarden-data,
mcp-grafana-data, mcp-loki-data, mcp-uptime-kuma-data,
mcp-meshcentral-data, mcp-guacamole-data, mcp-portainer-data,
mcp-ollama-data, mcp-redis-queue-data
```

**Critical Rules:**
- All networks defined as `external: true` in compose files (created by install script)
- No `ports:` on any service except nginx (80/443)
- All other services use `expose:` only
- Service names = DNS names (NOT container names with mcp- prefix)

**Gate Check 2:**
- [ ] `docker network ls` shows all 5 networks
- [ ] Network isolation validated (container in data-net cannot reach edge-net)
- [ ] All volumes created

---

### Phase 3: Core Stack — Databases, Identity, Proxy (8 Containers)

**Goal:** Deploy the foundation: PostgreSQL, Redis, pgvector, OpenBao, nginx, Keycloak, n8n, ntfy.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 3.1 | Core docker-compose.yml | `compose/core/docker-compose.yml` |
| 3.2 | nginx configuration | `config/nginx/nginx.conf` + `config/nginx/conf.d/*.conf` |
| 3.3 | Keycloak realm export | `config/keycloak/realm-export.json` |
| 3.4 | ntfy configuration | `config/ntfy/server.yml` |
| 3.5 | PostgreSQL init script | `scripts/init-db.sh` (creates ALL databases + roles) |

**Container Details:**

| Container | Image | Networks | Healthcheck |
|-----------|-------|----------|-------------|
| postgres | postgres:16 | data | `pg_isready -U mcp_admin` |
| redis | redis:7 | data | `redis-cli ping` |
| pgvector | pgvector/pgvector:pg16 | data, ai | `pg_isready` |
| openbao | openbao/openbao | sec, app | `bao status -address=http://127.0.0.1:8200` |
| nginx | nginx:alpine | edge, app | `curl -f http://127.0.0.1/health` |
| keycloak | keycloak/keycloak | app, data | `curl -f http://127.0.0.1:8080/health/ready` |
| n8n | n8nio/n8n | app, data | `wget -qO- http://127.0.0.1:5678/healthz` |
| ntfy | binwiederhier/ntfy | app | `wget -qO- http://127.0.0.1:80/v1/health` |

**PostgreSQL Databases to Create:**

```sql
CREATE DATABASE mcp_core OWNER mcp_admin;
CREATE DATABASE mcp_admin OWNER mcp_admin;
CREATE DATABASE keycloak OWNER keycloak;
CREATE DATABASE n8n OWNER n8n;
CREATE DATABASE zammad OWNER zammad;       -- + ALTER ROLE zammad CREATEDB
CREATE DATABASE bookstack OWNER bookstack;
CREATE DATABASE grafana OWNER grafana;
CREATE DATABASE zabbix OWNER zabbix;
```

**nginx Proxy Paths (13 routes):**

```
/           → Dashboard (static HTML)
/grafana    → grafana:3000
/tickets    → zammad-rails:3000
/monitor    → zabbix-web:8080
/wiki       → bookstack:80
/status     → uptime-kuma:3001
/vault      → vaultwarden:80
/auth       → keycloak:8080
/auto       → n8n:5678
/remote     → meshcentral:443 (HTTPS!)
/guac       → guacamole:8080/guacamole/
/portainer  → portainer:9000
/notify     → ntfy:80
```

**Gate Check 3:**
- [ ] PostgreSQL accepts connections, all 8 databases exist
- [ ] Redis responds to PING
- [ ] pgvector extension loaded (`SELECT * FROM pg_extension WHERE extname='vector'`)
- [ ] OpenBao status returns initialized
- [ ] nginx returns 200 on `/health`
- [ ] Keycloak admin console loads
- [ ] n8n healthcheck passes
- [ ] ntfy test message sent and received

---

### Phase 4: Ops Stack — Ticketing, Wiki, Tools (8 Containers)

**Goal:** Deploy Zammad (3 containers + init), Elasticsearch, BookStack, Vaultwarden, Portainer, DIUN.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 4.1 | Ops docker-compose.yml | `compose/ops/docker-compose.yml` |
| 4.2 | Zammad configuration | Environment variables in compose |
| 4.3 | BookStack configuration | Environment variables in compose |

**Container Details:**

| Container | Image | Networks | Critical Config |
|-----------|-------|----------|-----------------|
| zammad-init | zammad/zammad | app, data | One-shot init container |
| zammad-rails | zammad/zammad | app, data | `RAILS_SERVE_STATIC_FILES=true` |
| zammad-websocket | zammad/zammad | app | WebSocket server |
| zammad-worker | zammad/zammad | app, data | Background jobs |
| elasticsearch | elasticsearch:8 | data | `discovery.type=single-node` |
| bookstack | linuxserver/bookstack | app, data | Needs MariaDB or uses PostgreSQL |
| vaultwarden | vaultwarden/server | app | Web vault |
| portainer | portainer/portainer-ce | app | Docker socket mount |
| diun | crazymax/diun | app | Image update watcher |

**Known Issues to Pre-Solve:**
- Zammad role needs `CREATEDB` (Tipps.md #9)
- `RAILS_SERVE_STATIC_FILES=true` is CRITICAL (Tipps.md #12)
- Service names in all configs, NOT container names (Tipps.md #13)

**Gate Check 4:**
- [ ] Zammad-init completes with exit 0
- [ ] Zammad UI loads (no 404 on assets)
- [ ] BookStack login page renders
- [ ] Vaultwarden web vault accessible
- [ ] Portainer shows all running containers
- [ ] Elasticsearch cluster status is green
- [ ] DIUN recognizes container list

---

### Phase 5: Telemetry Stack — Monitoring & Logging (8 Containers)

**Goal:** Deploy Zabbix, Grafana, Loki, Alloy, Uptime Kuma, CrowdSec, Grafana Renderer.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 5.1 | Telemetry docker-compose.yml | `compose/telemetry/docker-compose.yml` |
| 5.2 | Loki configuration | `config/loki/loki-config.yml` |
| 5.3 | Alloy configuration | `config/alloy/config.alloy` |
| 5.4 | Grafana datasources | `config/grafana/datasources.yml` |
| 5.5 | Grafana dashboards | `config/grafana/dashboards/` |
| 5.6 | CrowdSec configuration | `config/crowdsec/acquis.yml` + scenarios |

**Container Details:**

| Container | Image | Networks | Critical Config |
|-----------|-------|----------|-----------------|
| zabbix-server | zabbix/zabbix-server-pgsql:7.0.0-alpine | app, data | NO bind-mount for config! |
| zabbix-web | zabbix/zabbix-web-nginx-pgsql:7.0.0-alpine | app | Tag: 7.0.0 (not 7.0) |
| grafana | grafana/grafana | app, data | Datasources: Loki, Zabbix, PostgreSQL |
| loki | grafana/loki | data | `retention_period: 0` |
| alloy | grafana/alloy | app, data | Log collector to Loki |
| uptime-kuma | louislam/uptime-kuma | app | Availability monitoring |
| crowdsec | crowdsecurity/crowdsec | sec, app | `online_client.enabled: false` |
| grafana-renderer | grafana/grafana-image-renderer | app | PDF/PNG export |

**Known Issues to Pre-Solve:**
- Zabbix image tag: `7.0.0-alpine` NOT `7.0-alpine` (Tipps.md #1)
- NO bind-mount for Zabbix config — use env vars only (Tipps.md #15)
- Loki: `retention_period: 0` to avoid compactor crash (Tipps.md #14)
- CrowdSec: `online_client.enabled: false` for offline operation

**Gate Check 5:**
- [ ] Zabbix Server connected to PostgreSQL
- [ ] Zabbix Web UI login works
- [ ] Grafana loads with configured datasources
- [ ] Loki `/ready` returns OK (no CrashLoop)
- [ ] Alloy is forwarding logs to Loki
- [ ] Uptime Kuma dashboard accessible
- [ ] CrowdSec scenarios loaded (offline mode)
- [ ] Grafana Renderer test render successful

---

### Phase 6: Security Hardening

**Goal:** Implement network isolation validation, CrowdSec bouncer, container hardening.

**Deliverables:**

| # | Deliverable | Detail |
|---|-------------|--------|
| 6.1 | Network isolation test script | `tests/security-test.sh` |
| 6.2 | CrowdSec nginx bouncer config | nginx integration |
| 6.3 | Container security settings | Read-only filesystems, no-new-privileges |
| 6.4 | TLS/SSL self-signed certificates | For local deployment |

**Security Measures:**

```yaml
# Applied to ALL containers where possible:
security_opt:
  - no-new-privileges:true
read_only: true     # Where applicable
tmpfs:
  - /tmp
  - /run
```

**Gate Check 6:**
- [ ] Container in mcp-ai-net CANNOT reach mcp-edge-net directly
- [ ] No service is exposed on 0.0.0.0 except nginx
- [ ] CrowdSec detects simulated brute-force
- [ ] Self-signed TLS works on nginx
- [ ] `tcpdump` shows zero outbound internet traffic

---

### Phase 7: Remote Stack — Remote Access (3 Containers)

**Goal:** Deploy MeshCentral, Guacamole, Guacd.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 7.1 | Remote docker-compose.yml | `compose/remote/docker-compose.yml` |
| 7.2 | Guacamole configuration | DB init + proxy config |

**Container Details:**

| Container | Image | Networks | Critical Config |
|-----------|-------|----------|-----------------|
| meshcentral | ghcr.io/ylianst/meshcentral:latest | app | GHCR not Docker Hub! (Tipps.md #2) |
| guacamole | guacamole/guacamole | app | Context path: `/guacamole/` (Tipps.md #16) |
| guacd | guacamole/guacd | app | Proxy daemon |

**Known Issues to Pre-Solve:**
- MeshCentral: use GHCR registry (Tipps.md #2)
- MeshCentral: HTTPS protocol (Tipps.md #17)
- Guacamole: context path is `/guacamole/` not `/` (Tipps.md #16)

**Gate Check 7:**
- [ ] MeshCentral web UI loads (via HTTPS)
- [ ] Guacamole login page at `/guacamole/`
- [ ] Guacd proxy daemon running

---

### Phase 8: AI Stack — Local AI Engine (5 Containers)

**Goal:** Deploy Ollama, LiteLLM, LangChain worker, AI Gateway, Redis Queue.

**This is the most complex phase — it requires custom container builds.**

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 8.1 | AI docker-compose.yml | `compose/ai/docker-compose.yml` |
| 8.2 | AI Gateway (custom FastAPI) | `containers/ai-gateway/` |
| 8.3 | LangChain Worker (custom Python) | `containers/langchain-worker/` |
| 8.4 | LiteLLM model config | `config/ai/models.yml` |
| 8.5 | RAG configuration | `config/ai/rag-config.yml` |
| 8.6 | Prompt templates | `config/ai/prompts/` |
| 8.7 | Ollama model pull script | `scripts/mcp-pull-models.sh` |

**Container Details:**

| Container | Image | Networks | Critical Config |
|-----------|-------|----------|-----------------|
| ollama | ollama/ollama | ai | GPU passthrough (nvidia) |
| litellm | ghcr.io/berriai/litellm | ai, app | Model routing config |
| langchain | custom build | ai, data | pgvector + RAG pipeline |
| ai-gateway | custom build (FastAPI) | ai, app | Central AI API |
| redis-queue | redis:7-alpine | ai | Dedicated KI job queue |

**AI Gateway API Endpoints:**

```
POST /api/v1/analyze     → Receive alert, run AI analysis
POST /api/v1/embed       → Create embedding for RAG
GET  /api/v1/search      → Search RAG knowledge base
GET  /health             → Health check
GET  /metrics            → Prometheus metrics
```

**LLM Models to Load:**

```
mistral:7b-instruct-v0.3-q4_K_M    → Primary analysis model
llama3:8b-instruct-q4_K_M          → Fallback model
nomic-embed-text                    → Embedding model for RAG
```

**RAG Pipeline Flow:**

```
New Alert → Dedup (Redis) → Context Gather → RAG Search (pgvector)
    → LLM Analysis (Ollama) → Structured JSON → Ticket (Zammad)
    → Notification (ntfy) → Knowledge Feedback Loop
```

**Gate Check 8:**
- [ ] Ollama running with GPU detected (`nvidia-smi` inside container)
- [ ] All 3 models loaded (`ollama list`)
- [ ] LiteLLM `/health` returns OK
- [ ] AI Gateway `/health` returns healthy
- [ ] Redis Queue is reachable on mcp-ai-net
- [ ] Test prompt returns structured JSON response
- [ ] RAG search returns results from pgvector

---

### Phase 9: Integration — Workflows, Pipelines, Dashboard

**Goal:** Wire everything together: n8n workflows, AI pipeline end-to-end, nginx dashboard.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 9.1 | n8n Workflow W1 (Alert → AI → Ticket) | `config/n8n/workflows/W1-alert-analysis.json` |
| 9.2 | n8n Workflow W2 (Log Anomaly → Ticket) | `config/n8n/workflows/W2-log-anomaly.json` |
| 9.3 | n8n Workflow W3 (Security → Ticket) | `config/n8n/workflows/W3-security-finding.json` |
| 9.4 | n8n Workflow W4 (Predictive Alert) | `config/n8n/workflows/W4-predictive.json` |
| 9.5 | n8n Workflow W5 (Ticket Close → Knowledge) | `config/n8n/workflows/W5-knowledge-feedback.json` |
| 9.6 | n8n Workflow W6 (Network Anomaly) | `config/n8n/workflows/W6-network-anomaly.json` |
| 9.7 | n8n Workflow W7 (Capacity Planning) | `config/n8n/workflows/W7-capacity-report.json` |
| 9.8 | n8n Workflow W8 (Daily Health Report) | `config/n8n/workflows/W8-daily-report.json` |
| 9.9 | Dashboard HTML/CSS/JS | `config/nginx/dashboard/` |
| 9.10 | Workflow import + activation script | `scripts/mcp-import-workflows.sh` |

**Webhook Registration (after activation):**

| Webhook Path | Workflow |
|---|---|
| `/webhook/zabbix-alert` | W1 |
| `/webhook/loki-alert` | W2 |
| `/webhook/security-finding` | W3 |
| `/webhook/ticket-closed` | W5 |
| `/webhook/network-anomaly` | W6 |

**Dashboard Components:**
- System health: All 32 containers (green/yellow/red)
- Last 10 AI-generated tickets
- Active alarms (Zabbix + Uptime Kuma + CrowdSec)
- AI confidence distribution (High/Medium/Low)
- Quick access tiles to all 13 services
- Printer status overview
- Security summary (CrowdSec)
- Recent notifications (ntfy feed)

**Gate Check 9:**
- [ ] All 8 workflows imported and active in n8n
- [ ] Webhooks registered and responding
- [ ] End-to-end test: Fake Zabbix alert → n8n → AI Gateway → Ollama analysis → Zammad ticket → ntfy push
- [ ] Dashboard loads at `/` showing all services
- [ ] All 13 proxy paths return correct service

---

### Phase 10: Testing, Validation & Documentation

**Goal:** Comprehensive testing, offline validation, backup/restore, and operational documentation.

**Deliverables:**

| # | Deliverable | File |
|---|-------------|------|
| 10.1 | Smoke test script | `tests/smoke-test.sh` |
| 10.2 | AI pipeline end-to-end test | `tests/ai-pipeline-test.sh` |
| 10.3 | Security validation test | `tests/security-test.sh` |
| 10.4 | Backup script | `scripts/mcp-backup.sh` |
| 10.5 | Restore script | `scripts/mcp-restore.sh` |
| 10.6 | Image pull script | `scripts/mcp-pull-images.sh` |
| 10.7 | Image export/import scripts | `scripts/mcp-export-images.sh` + `scripts/mcp-import-images.sh` |
| 10.8 | Model export script | `scripts/mcp-export-models.sh` |
| 10.9 | Deployment runbook | `docs/deployment-runbook.md` |

**Smoke Test Coverage (32 containers):**

```bash
# For each container:
# 1. Is it running?
# 2. Is it healthy?
# 3. Zero restarts?
# 4. Can it respond to its healthcheck endpoint?
```

**AI Pipeline Test:**

```bash
# 1. Send fake alert to AI Gateway
# 2. Verify job in Redis Queue
# 3. Verify RAG search in pgvector
# 4. Verify LLM analysis (structured JSON)
# 5. Verify ticket created in Zammad
# 6. Verify ntfy push notification sent
# 7. Close ticket → verify knowledge feedback to pgvector
```

**Security Test:**

```bash
# 1. Network isolation (cross-network ping tests)
# 2. No ports on 0.0.0.0 except nginx
# 3. CrowdSec brute-force detection
# 4. Zero outbound traffic (tcpdump)
# 5. TLS verification
# 6. AI Gateway not reachable from edge-net
```

**Go-Live Checklist:**

- [ ] All 32 containers running with STATUS=healthy
- [ ] No container restarts (0 restarts in 1 hour)
- [ ] Dashboard at `http://<IP>` shows all 13 services
- [ ] All 13 nginx proxy paths work
- [ ] Portainer shows all 32 containers
- [ ] Zabbix monitors at least one device
- [ ] AI Pipeline: Fake-Alert → redis-queue → Analysis → Ticket in Zammad
- [ ] ntfy notification received on ticket creation
- [ ] RAG works: Resolved ticket found in similar alert search
- [ ] CrowdSec detects simulated brute-force
- [ ] Zero outbound network requests (tcpdump verified)
- [ ] Keycloak SSO works for Grafana + Zammad
- [ ] Backup + Restore tested successfully
- [ ] Install script runs through all 6 phases without error

---

## Phase Dependencies Graph

```
Phase 1 (Foundation)
    │
    ▼
Phase 2 (Networks & Volumes)
    │
    ▼
Phase 3 (Core Stack) ──────────────────────┐
    │                                       │
    ▼                                       │
Phase 4 (Ops Stack)                         │
    │                                       │
    ▼                                       │
Phase 5 (Telemetry Stack)                   │
    │                                       │
    ├───▶ Phase 6 (Security Hardening)      │
    │                                       │
    ▼                                       │
Phase 7 (Remote Stack)                      │
    │                                       │
    ▼                                       ▼
Phase 8 (AI Stack) ◀───── Requires Phase 3 (pgvector, redis)
    │
    ▼
Phase 9 (Integration) ◀── Requires ALL previous phases
    │
    ▼
Phase 10 (Testing & Validation)
```

---

## File Tree — Complete v0.1 Deliverables

```
Masdor-MCP/
├── .env.example                          ← Phase 1
├── Makefile                              ← Phase 1
│
├── compose/
│   ├── core/docker-compose.yml           ← Phase 3
│   ├── ops/docker-compose.yml            ← Phase 4
│   ├── telemetry/docker-compose.yml      ← Phase 5
│   ├── remote/docker-compose.yml         ← Phase 7
│   └── ai/docker-compose.yml             ← Phase 8
│
├── config/
│   ├── nginx/
│   │   ├── nginx.conf                    ← Phase 3
│   │   ├── conf.d/                       ← Phase 3 (13 proxy configs)
│   │   └── dashboard/                    ← Phase 9
│   ├── grafana/
│   │   ├── datasources.yml              ← Phase 5
│   │   └── dashboards/                   ← Phase 5
│   ├── loki/loki-config.yml             ← Phase 5
│   ├── alloy/config.alloy               ← Phase 5
│   ├── keycloak/realm-export.json       ← Phase 3
│   ├── ntfy/server.yml                  ← Phase 3
│   ├── crowdsec/
│   │   ├── acquis.yml                    ← Phase 6
│   │   └── scenarios/                    ← Phase 6
│   ├── portainer/                        ← Phase 4
│   ├── n8n/workflows/
│   │   ├── W1-alert-analysis.json        ← Phase 9
│   │   ├── W2-log-anomaly.json           ← Phase 9
│   │   ├── W3-security-finding.json      ← Phase 9
│   │   ├── W4-predictive.json            ← Phase 9
│   │   ├── W5-knowledge-feedback.json    ← Phase 9
│   │   ├── W6-network-anomaly.json       ← Phase 9
│   │   ├── W7-capacity-report.json       ← Phase 9
│   │   └── W8-daily-report.json          ← Phase 9
│   └── ai/
│       ├── prompts/                      ← Phase 8
│       ├── models.yml                    ← Phase 8
│       └── rag-config.yml               ← Phase 8
│
├── containers/
│   ├── ai-gateway/
│   │   ├── Dockerfile                    ← Phase 8
│   │   ├── requirements.txt              ← Phase 8
│   │   └── app/                          ← Phase 8
│   └── langchain-worker/
│       ├── Dockerfile                    ← Phase 8
│       ├── requirements.txt              ← Phase 8
│       └── app/                          ← Phase 8
│
├── scripts/
│   ├── mcp-install.sh                    ← Phase 1 (skeleton) + Phase 10 (complete)
│   ├── mcp-start.sh                      ← Phase 1
│   ├── mcp-stop.sh                       ← Phase 1
│   ├── mcp-status.sh                     ← Phase 1
│   ├── mcp-pull-images.sh               ← Phase 10
│   ├── mcp-export-images.sh             ← Phase 10
│   ├── mcp-import-images.sh             ← Phase 10
│   ├── mcp-export-models.sh             ← Phase 10
│   ├── mcp-export-crowdsec.sh           ← Phase 6
│   ├── mcp-backup.sh                    ← Phase 10
│   ├── mcp-restore.sh                   ← Phase 10
│   ├── mcp-import-workflows.sh          ← Phase 9
│   └── init-db.sh                       ← Phase 1
│
├── tests/
│   ├── smoke-test.sh                     ← Phase 10
│   ├── ai-pipeline-test.sh              ← Phase 10
│   └── security-test.sh                 ← Phase 6 + Phase 10
│
├── logs/                                 ← Created at runtime
├── images/                               ← For offline deployment
├── models/                               ← For offline deployment
│
└── docs/
    ├── assets/mcp-logo.png
    ├── deployment-runbook.md             ← Phase 10
    └── troubleshooting.md               ← Phase 10
```

---

## Design Rules for ALL Phases

These rules apply to every line of code written across all 10 phases:

### Naming Rules
1. **Service names** in docker-compose are the DNS names (e.g., `postgres`, NOT `mcp-postgres`)
2. **Container names** use the project prefix (e.g., `mcp-postgres`) — set via `container_name:`
3. All **nginx upstream** configs use service names
4. All **database host** references use service names
5. `COMPOSE_PROJECT_NAME=mcp` is always set

### Healthcheck Rules
1. Always use `127.0.0.1`, never `localhost` (IPv6 issue)
2. Always verify protocol (HTTP vs HTTPS) per service
3. Always check context path (e.g., `/guacamole/` not `/`)
4. Use `start_period: 120s` for services with DB migrations
5. Check which tool exists in container (wget vs curl)

### Security Rules
1. No `ports:` except nginx (80/443) — use `expose:` instead
2. No secrets in code — all in `.env`
3. No internet access at runtime
4. `no-new-privileges: true` where possible
5. `read_only: true` where possible
6. AI Gateway NEVER exposed publicly

### Offline Rules
1. All images pre-pulled with exact version tags
2. No `:latest` in production (except MeshCentral if needed)
3. CrowdSec: `online_client.enabled: false`
4. ntfy replaces email notifications
5. Two Redis instances: `mcp-redis` (cache) and `mcp-redis-queue` (AI jobs)

---

## Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Custom AI containers fail to build | HIGH | CRITICAL | Phase 8 dedicated to AI; fallback to simpler API wrapper |
| GPU not available | MEDIUM | HIGH | CPU fallback mode in Ollama config |
| Memory exhaustion (32 GB tight) | MEDIUM | HIGH | Configurable stack profiles (Core-only, Full) |
| Zammad multi-container init fails | MEDIUM | MEDIUM | Pre-solved: CREATEDB + RAILS_SERVE_STATIC_FILES |
| n8n workflow import breaks | LOW | MEDIUM | SQL activation fallback (Tipps.md #20) |
| Network isolation bypass | LOW | CRITICAL | Phase 6 dedicated security validation |
| Loki CrashLoop | LOW | LOW | Pre-solved: retention_period: 0 |

---

## Success Criteria for v0.1

The Masdor-MCP v0.1 release is considered **COMPLETE** when:

1. All 32 containers start and report `healthy`
2. Zero container restarts in 60 minutes
3. The installation script completes all 6 phases without manual intervention
4. The AI pipeline processes a fake alert end-to-end (alert → ticket → notification)
5. The RAG pipeline returns relevant results for similar incidents
6. The dashboard shows all 13 services with correct status
7. No outbound internet traffic detected
8. Backup and restore tested successfully
9. All tests pass (smoke, AI pipeline, security)
10. Documentation is complete (deployment runbook)

---

<p align="center">
  <strong>Masdor-MCP 0.1 — Build Plan</strong><br>
  <em>10 Phases. 32 Containers. 5 Networks. 1 Vision.</em><br><br>
  <code>From Documentation to Reality</code>
</p>
