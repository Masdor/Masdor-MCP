<p align="center">
  <img src="docs/assets/mcp-logo.png" alt="MCP Logo" width="200"/>
</p>

<h1 align="center">MCP — Managed Control Platform</h1>

<p align="center">
  <strong>AI-Powered IT Operations Center</strong><br>
  <em>Local. Intelligent. Automated.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-7.0-blue?style=flat-square" alt="Version"/>
  <img src="https://img.shields.io/badge/status-Beta-orange?style=flat-square" alt="Status"/>
  <img src="https://img.shields.io/badge/os-Debian%2013%20(Trixie)-red?style=flat-square" alt="OS"/>
  <img src="https://img.shields.io/badge/containers-33-green?style=flat-square" alt="Containers"/>
  <img src="https://img.shields.io/badge/AI-Ollama%20%2B%20LangChain-purple?style=flat-square" alt="AI"/>
  <img src="https://img.shields.io/badge/license-Proprietary-lightgrey?style=flat-square" alt="License"/>
</p>

<p align="center">
  🇬🇧 <strong>English</strong> · 🇩🇪 <a href="README_de.md">Deutsch</a> · 🇸🇦 <a href="README_ar.md">العربية</a>
</p>

> **Project Status:** MCP v7 is in **Beta**. The platform is functional and actively validated in lab environments. Production deployment requires individual assessment and a written license agreement.

---

## Table of Contents

- [Overview](#overview)
- [Design Principles](#design-principles)
- [What's New in v7](#whats-new-in-v7)
- [The 5 Pillars](#the-5-pillars)
- [Architecture](#architecture)
  - [AI Stack](#ai-stack)
  - [RAG Pipeline](#rag-pipeline)
  - [Analysis Engine](#analysis-engine)
- [Smart Ticketing](#smart-ticketing)
- [Container Infrastructure](#container-infrastructure)
- [Network Segmentation](#network-segmentation)
- [AI Workflows (n8n)](#ai-workflows-n8n)
- [Predictive Maintenance & Anomaly Detection](#predictive-maintenance--anomaly-detection)
- [AI Security Analysis](#ai-security-analysis)
- [Multi-Tenant Operations](#multi-tenant-operations)
- [Installation](#installation)
  - [Hardware Requirements](#hardware-requirements)
  - [Installation Phases](#installation-phases)
- [Day-2 Operations](#day-2-operations)
- [Go-Live Checklist](#go-live-checklist)
- [Roadmap](#roadmap)
- [Licensing](#licensing)

---

## Overview

**MCP (Managed Control Platform)** is a fully self-hosted, AI-powered IT operations center designed for managed service providers (MSPs) and IT teams. It transforms traditional IT operations into an intelligent, automated workflow — from monitoring and alerting to root-cause analysis and ticket generation — all running **100% on-premise** with no cloud dependencies.

MCP v7 orchestrates **33 Docker containers** (32 long-running + 1 init) across 5 isolated networks, combining industry-standard tools (Zabbix, Grafana, Zammad, Loki) with a local AI stack (Ollama + LangChain + pgvector) that analyzes events in real-time and generates professional, actionable tickets automatically.

```
Single .env  →  AI Pipeline  →  Auto-Tickets
```

---

## Design Principles

Every architecture and operational decision in MCP is guided by five core principles:

- **Secure-by-Design** — Security is a foundation, not an add-on
- **Network Segmentation** — 5 isolated networks limit the blast radius
- **Human-in-the-Loop** — AI recommends, humans decide
- **Local AI** — Full data sovereignty with zero cloud dependency
- **Auditable Operations** — Traceability across every phase

---

## What's New in v7

MCP v7 represents a major leap from v6, introducing a fully local AI system that analyzes monitoring data, security events, and network anomalies in real-time.

| Area | v6 (Before) | v7 (Now) | Business Impact |
|------|-------------|----------|-----------------|
| AI | pgvector embeddings only | Local LLM + RAG + Analysis Pipeline | Automatic fault diagnosis |
| Tickets | Manually created | AI writes complete tickets | 80% less manual work |
| Monitoring | Separate tools | Unified AI correlation | Cross-tool root-cause analysis |
| Prediction | None | Predictive maintenance | Fix problems BEFORE they occur |
| Security | Trivy + Nuclei (cron) | Real-time AI security analysis | Instant threat detection |
| Network | Basic monitoring | AI network anomaly detection | Automatic network diagnosis |
| Knowledge | Manual wiki | AI-powered knowledge base | Context from all past incidents |
| Containers | 25 | 33 (+8 AI stack, +1 init) | Fully on-premise |

---

## The 5 Pillars

| # | Pillar | Description | Components |
|---|--------|-------------|------------|
| 1 | **Local AI Engine** | On-premise LLM — no cloud dependency | Ollama + Mistral 7B / Llama 3 8B |
| 2 | **Unified Data Collector** | All monitoring sources in one data stream | Alloy + Loki + Zabbix + Vector |
| 3 | **AI Analysis Pipeline** | Automatic fault analysis with context | LangChain + pgvector + RAG |
| 4 | **Smart Ticketing** | AI writes complete tickets with recommendations | n8n → Zammad API → AI-enriched |
| 5 | **Predictive Ops** | Predict future problems | Time-series ML + anomaly detection |

---

## Architecture

### AI Stack

The heart of MCP v7 is a fully local AI system. No data leaves the server. The architecture is built on three layers:

#### Layer 1: Local LLM Engine (Ollama)

| Component | Model | RAM | Task |
|-----------|-------|-----|------|
| Primary LLM | Mistral 7B / Llama 3 8B | 6–8 GB | Ticket creation, root-cause analysis, recommendations |
| Code Analysis | CodeLlama 7B | 6 GB | Log parsing, config analysis, script generation |
| Embedding | nomic-embed-text | 0.5 GB | Vectorization for RAG knowledge base |
| Classification | Phi-3 Mini 3.8B | 3 GB | Fast alert categorization, priority scoring |

> ⚠️ **Hardware Note:** The AI stack requires a minimum of 32 GB RAM and 8 CPU cores. GPU (NVIDIA) is recommended but not required. See [Hardware Requirements](#hardware-requirements) for Core-only vs. Full-stack profiles.

### RAG Pipeline

The RAG (Retrieval Augmented Generation) pipeline provides the LLM with context from the entire knowledge base. When a new alert arrives, the system automatically searches for similar past incidents, solutions, and configurations.

**Data Sources:**

| Source | Content | Update Frequency |
|--------|---------|------------------|
| Zammad Tickets | All resolved tickets + solutions | On ticket close |
| BookStack Wiki | IT documentation, runbooks, SOPs | On page update |
| Zabbix History | Monitoring metrics + trigger history | Hourly |
| Grafana Alerts | Alert history + annotations | On alert trigger |
| Security Scans | Trivy / Nuclei / Lynis reports | After each scan |
| Network Logs | Firewall, VPN, DNS logs | Every 15 minutes |
| Container Logs | Docker logs from all services | Real-time via Loki |

### Analysis Engine

The analysis engine orchestrates the complete AI workflow:

```
1. EVENT INTAKE        →  Zabbix trigger, Loki alert, security finding, or manual request
2. CONTEXT ENRICHMENT  →  RAG search in pgvector for similar incidents (last 90 days)
3. DATA AGGREGATION    →  Current metrics from Zabbix + Loki + container status
4. LLM ANALYSIS        →  Local model analyzes event + context + metrics
5. TICKET GENERATION   →  Structured ticket with all findings
6. VALIDATION          →  Confidence score + human review if score is low
7. FEEDBACK LOOP       →  Resolved tickets flow back into the knowledge base
```

---

## Smart Ticketing

The core value for MSPs: AI automatically creates complete, professional tickets that can be forwarded directly to clients.

Every AI-generated ticket includes:

| Section | Content | Data Source |
|---------|---------|-------------|
| 🔴 Error Description | What happened? Technical summary | Zabbix triggers + Loki logs |
| 🔧 Root-Cause Analysis | WHY did it happen? Causal chain | AI correlation of all sources |
| 📊 Impact Analysis | Which services/clients affected? | Service map + Zabbix dependencies |
| ⏪ Historical Correlation | Has this happened before? What helped? | pgvector RAG over past tickets |
| ⚙️ Current Status | Live metrics at the time of the incident | Zabbix + Grafana + container status |
| 🔮 Prognosis | Will it get worse? When will it recur? | Time-series analysis + trends |
| 📋 Recommended Actions | Immediate fix + long-term solution + prevention | AI + knowledge base + best practices |
| 📈 Technical Details | Logs, metrics, configs, screenshots | All monitoring tools aggregated |
| ⏰ SLA Status | SLA countdown, priority, escalation level | Zammad SLA engine + AI priority |

### AI Confidence Levels

| Confidence | Meaning | Action |
|------------|---------|--------|
| 95–100% | Known problem, exact solution available | Auto-ticket + auto-fix (if approved) |
| 75–94% | Probable cause, solution suggested | Auto-ticket + human review |
| 50–74% | Multiple possible causes | Draft ticket + human analysis |
| < 50% | Unknown pattern | Alert only, no ticket — human takes over |

---

## Container Infrastructure

MCP v7 runs **33 containers** (32 long-running + 1 init) organized into functional stacks:

<details>
<summary><strong>Click to expand full container list</strong></summary>

| # | Container | Image | Network | Stack |
|---|-----------|-------|---------|-------|
| 1 | mcp-postgres | postgres:16-alpine | data | Data |
| 2 | mcp-pgvector | pgvector/pgvector:pg16 | data | Data |
| 3 | mcp-redis | redis:7-alpine | data | Data |
| 4 | mcp-nginx | nginx:1.27-alpine | edge+app | Edge |
| 5 | mcp-keycloak | keycloak:26.0 | app+data | Core |
| 6 | mcp-openbao | openbao:2.1 | app | Core |
| 7 | mcp-n8n | n8nio/n8n:1.76.1 | app+data | Core |
| 8 | mcp-zammad-init | ghcr.io/zammad/zammad:6.4.1 | app+data | Ops (init) |
| 9 | mcp-zammad-rails | ghcr.io/zammad/zammad:6.4.1 | app+data+edge | Ops |
| 10 | mcp-zammad-ws | ghcr.io/zammad/zammad:6.4.1 | app+data+edge | Ops |
| 11 | mcp-zammad-worker | ghcr.io/zammad/zammad:6.4.1 | app+data | Ops |
| 12 | mcp-zammad-es | elasticsearch:8.17.0 | app | Ops |
| 13 | mcp-zammad-memcached | memcached:1.6-alpine | app | Ops |
| 14 | mcp-bookstack-db | mariadb:11.6 | data | Ops |
| 15 | mcp-bookstack | linuxserver/bookstack:24.12.1 | app+data+edge | Ops |
| 16 | mcp-vaultwarden | vaultwarden/server:1.32.5 | app+edge | Ops |
| 17 | mcp-diun | crazymax/diun:4.28 | app | Ops |
| 18 | mcp-zabbix-server | zabbix-server-pgsql:7.0.0-alpine | app+data | Telemetry |
| 19 | mcp-zabbix-web | zabbix-web-nginx-pgsql:7.0.0-alpine | app+data+edge | Telemetry |
| 20 | mcp-loki | grafana/loki:3.3.2 | app+data | Telemetry |
| 21 | mcp-alloy | grafana/alloy:v1.5.1 | app | Telemetry |
| 22 | mcp-grafana | grafana/grafana:11.4.0 | app+data+edge | Telemetry |
| 23 | mcp-uptime-kuma | louislam/uptime-kuma:1 | app+edge | Telemetry |
| 24 | mcp-meshcentral | ghcr.io/ylianst/meshcentral:latest | app+edge | Remote |
| 25 | mcp-guacd | guacamole/guacd:1.5.5 | app | Remote |
| 26 | mcp-guacamole | guacamole/guacamole:1.5.5 | app+data+edge | Remote |
| 27 | mcp-ollama | ollama/ollama:latest | ai | **AI** |
| 28 | mcp-ai-gateway | custom:fastapi | ai+app+data | **AI** |
| 29 | mcp-event-processor | custom:python | ai+app+data | **AI** |
| 30 | mcp-vector-worker | custom:python | ai+data | **AI** |
| 31 | mcp-langchain | custom:python | ai+app+data | **AI** |
| 32 | mcp-prometheus | prom/prometheus:latest | ai+app | **AI** |
| 33 | mcp-alertmanager | prom/alertmanager:latest | ai+app | **AI** |

> **Note:** mcp-zammad-init is a one-shot init container that runs DB migrations and exits. 33 containers total, 32 long-running.

</details>

---

## Network Segmentation

MCP uses 5 isolated Docker bridge networks for defense-in-depth:

| Network | Subnet | Purpose | Access |
|---------|--------|---------|--------|
| `mcp-edge-net` | 172.20.0.0/24 | Nginx only (80/443) | External |
| `mcp-app-net` | 172.20.1.0/24 | All app containers internal | Internal |
| `mcp-data-net` | 172.20.2.0/24 | Databases only | DB clients only |
| `mcp-sec-net` | 172.20.3.0/24 | Security tools (SIEM) | Reserved |
| `mcp-ai-net` | 172.20.4.0/24 | AI stack **(NEW)** | AI + App only |

### Critical Rule

**Never expose the AI Gateway to the public internet.**
It must remain internal within the platform networks.

---

## AI Workflows (n8n)

All AI workflows run via n8n using the AI Gateway as a central interface:

| # | Workflow | Trigger | Action | Output |
|---|----------|---------|--------|--------|
| W1 | Alert → AI Analysis | Zabbix trigger (webhook) | Event → AI Gateway → RAG analysis → LLM | Complete Zammad ticket |
| W2 | Log Anomaly → Ticket | Loki alert rule | Log pattern analysis + correlation | Zammad ticket + Grafana annotation |
| W3 | Security Finding → Ticket | Trivy/Nuclei webhook | CVE analysis + impact assessment | Priority ticket + wiki entry |
| W4 | Predictive Alert | Cron (every 6h) | Time-series trend analysis | Warning ticket if risk > 70% |
| W5 | Ticket Close → Knowledge | Zammad webhook | Resolved ticket → wiki + embedding | BookStack article + pgvector |
| W6 | Network Anomaly | Alloy + custom rule | Traffic pattern analysis | Security ticket + firewall recommendation |
| W7 | Capacity Planning | Cron (weekly) | Resource trend analysis for all containers | Planning report as wiki page |
| W8 | Health Report | Cron (daily 08:00) | Summary of all systems | Daily status report |

### Workflow W1: Alert → AI Analysis (Detail)

This is the most critical workflow, triggered on every Zabbix alert:

```
Step 1 — Event Intake:     Zabbix sends webhook to n8n (trigger ID, hostname, severity, description)
Step 2 — Deduplication:    Redis check if same alert was processed in the last 15 minutes
Step 3 — Context Gather:   Parallel: Zabbix history (24h), Loki logs (2h), container status, pgvector matches
Step 4 — AI Analysis:      AI Gateway sends everything to Ollama/Mistral with structured prompt
Step 5 — Ticket Creation:  Structured JSON → Zammad API → new ticket with all sections
Step 6 — Notification:     Email/Slack/Teams to responsible team based on AI routing
```

---

## Predictive Maintenance & Anomaly Detection

MCP v7 continuously analyzes trends and detects problems before they occur. The system learns from every resolved incident.

| Metric | Collection | AI Analysis | Action on Anomaly |
|--------|-----------|-------------|-------------------|
| CPU per container | Zabbix (60s) | Trend + seasonal patterns | Ticket if 70%+ for >5 min |
| RAM usage | Zabbix + cAdvisor | Memory leak detection | Ticket + restart recommendation |
| Disk I/O + space | Zabbix | Growth rate → days-until-full | Ticket 14 days before full |
| DB connections | PostgreSQL Exporter | Connection leak patterns | Ticket + pooler recommendation |
| HTTP response times | Nginx logs + Alloy | Latency anomalies | Ticket if p95 > 2x normal |
| Container restarts | Docker events | Crash loop detection | Ticket after 3rd restart in 1h |
| TLS certificates | Certbot + custom check | Expiry tracking | Ticket 30 days before expiry |
| Backup status | restic + custom check | Backup completeness | Critical ticket if >24h old |
| Network traffic | Alloy + iptables | DDoS / scan detection | Security ticket + auto-block |
| DNS resolution | Custom probe | DNS propagation check | Ticket if outage > 5 min |

---

## AI Security Analysis

Instead of periodic scans only, v7 integrates continuous security analysis through AI:

| Threat | Detection | AI Reaction | Automation |
|--------|-----------|-------------|------------|
| CVE in container image | Trivy (daily) + DIUN | Impact analysis: is CVE exploitable in our setup? | Ticket with upgrade plan |
| Brute-force SSH/Web | fail2ban + Loki logs | Pattern analysis: targeted attack or bot? | Auto-ban + security ticket |
| Unusual traffic | Alloy + iptables | DDoS vs. legitimate traffic | Rate limiting + alert |
| Config drift | Git diff + custom check | What changed? Security risk? | Ticket + rollback option |
| SSL/TLS weakness | Nuclei + testssl.sh | Cipher analysis + recommendation | Auto-config + ticket |
| Container escape attempt | Falco + Docker events | Forensic analysis | Critical ticket + isolation |

---

## Multi-Tenant Operations

MCP v7 is specifically designed for MSPs managing multiple clients. Each tenant has isolated data, while the AI learns across all tenants (with appropriate data boundaries).

**Tenant onboarding** is AI-assisted across 10 steps covering Keycloak realm setup, Zammad SLA configuration, BookStack documentation spaces, Zabbix host groups, Grafana dashboards, pgvector row-level security, customer-specific LLM profiles, Uptime Kuma monitors, MeshCentral device groups, and Vaultwarden collections.

The AI considers **customer context** during analysis: infrastructure type, SLA level, known quirks, contact persons, historical tickets (via `tenant_id`), service maps, and escalation matrices.

---

## Installation

### Hardware Requirements

| Profile | CPU | RAM | Disk | GPU | Use Case |
|---------|-----|-----|------|-----|----------|
| **Core only** (no AI) | 4 cores | 16 GB | 60 GB NVMe | — | Monitoring, Ticketing, Wiki — validation and evaluation |
| **Minimum** (full stack) | 8 cores | 32 GB | 100 GB NVMe | None (CPU-only) | All 33 containers, AI at ~15 tok/s |
| **Recommended** | 16 cores | 64 GB | 200 GB NVMe | NVIDIA T4 (16 GB) | Comfortable headroom, AI at ~60 tok/s |
| **Optimal** | 16+ cores | 128 GB | 500 GB NVMe | NVIDIA A10 (24 GB) | Multi-tenant production workloads |

> ℹ️ **Core-only profile** allows evaluating Monitoring, Ticketing, Wiki, and Remote stacks without the AI stack. Useful for teams testing the platform on lighter hardware.

#### RAM Distribution (Full Stack)

| Area | Containers | RAM |
|------|-----------|-----|
| Databases | PostgreSQL + pgvector + Redis + MariaDB + Elasticsearch | 5 GB |
| Apps | Keycloak + Zammad (3x) + BookStack + n8n + Vaultwarden | 6 GB |
| Monitoring | Zabbix (2x) + Grafana + Loki + Alloy + Uptime Kuma | 5 GB |
| Remote | MeshCentral + Guacamole (2x) | 1.5 GB |
| **AI Stack** | Ollama + Gateway + Workers | **12 GB** |
| System + Overhead | OS + Docker + Buffers | 3.5 GB |
| **TOTAL** | | **33 GB** |

### Installation Phases

The production deployment follows a **Phases + Gates** approach. Gates must not be skipped.

| Phase | Content | Containers | Duration | Gate |
|-------|---------|-----------|----------|------|
| 0 | Host hardening + Docker + networks | 0 | 30 min | SSH + UFW + WG + Docker OK |
| 1 | Databases + identity + TLS + Nginx | 7 | 45 min | PG + Redis + Keycloak healthy |
| 2 | Zammad + BookStack + Vaultwarden + DIUN | 10 (incl. init) | 30 min | Ticketing + wiki + PW manager OK |
| 3 | Ticket → Wiki → Embedding pipeline | 0 | 20 min | n8n workflows active |
| 4 | Monitoring + remote support | 9 | 30 min | Zabbix + Grafana + remote OK |
| **5** | **AI Stack: Ollama + Gateway + Workflows** | **7** | **60 min** | **AI analysis pipeline works** |

> **Entry point:** See [`docs/deployment-runbook.md`](docs/deployment-runbook.md) for the complete phase-based deployment guide.

#### Phase 5: AI Stack Installation

```bash
# Step 1: Start Ollama + download models
docker compose -f compose/ai/docker-compose.yml up -d ollama
sleep 30
docker exec mcp-ollama ollama pull mistral:7b
docker exec mcp-ollama ollama pull nomic-embed-text
docker exec mcp-ollama ollama pull codellama:7b
docker exec mcp-ollama ollama pull phi3:mini
docker exec mcp-ollama ollama list  # Verify all 4 models

# Step 2: Deploy all AI services
docker compose -f compose/ai/docker-compose.yml up -d --build
sleep 15
curl -sf http://localhost:8000/health

# Step 3: Import n8n AI workflows (W1-W8) via CLI
for workflow in config/n8n/workflows/W*.json; do
  docker cp "$workflow" mcp-n8n:/tmp/"$(basename "$workflow")"
  docker exec mcp-n8n n8n import:workflow --input=/tmp/"$(basename "$workflow")"
done
docker exec mcp-n8n n8n update:workflow --all --active=true

# Step 4: Test alert
curl -X POST http://localhost:8000/api/v1/analyze \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${AI_GATEWAY_SECRET}" \
  -d '{
    "source": "test",
    "severity": "warning",
    "host": "mcp-vps",
    "description": "Test: CPU usage above 80% for 5 minutes",
    "metrics": {"cpu": 82, "ram": 45, "disk": 60}
  }'
# Expected: New ticket created in Zammad with AI analysis
```

---

## Security & Privacy

MCP is built with secure-by-design defaults:

* **Segmentation first** (5 networks)
* **Identity & MFA** (Keycloak)
* **Secrets management** (OpenBao / `.env` policy)
* **TLS everywhere** (reverse proxy + certificate automation)
* **Local AI** (by default, no data leaves your infrastructure)

MCP is designed to *support* regulated environments — the responsibility for compliance assessment lies with the operator.

Full security policy and responsible disclosure:

* See [`SECURITY.md`](SECURITY.md)

---

## Day-2 Operations

### Daily AI Report (Workflow W8)

Every morning at 08:00, the AI generates a status report covering: system status (all containers), open issues, performance trends (24h), security status (new CVEs), predictions (next 7 days), capacity utilization, and top-3 recommended actions.

### AI-Assisted Update Workflow

```
DIUN Alert → AI analyzes changelog → Risk assessment (LOW/MEDIUM/HIGH) → Update ticket with rollback plan → Post-update health verification
```

### Scheduled Jobs (v7)

| Job | Schedule | New in v7? |
|-----|----------|-----------|
| Backup | Daily 03:00 | — |
| Certbot renewal | Monday 04:00 | — |
| Trivy → AI | Daily 05:00 | Enhanced |
| Nuclei → AI | Wednesday 05:00 | Enhanced |
| Lynis → AI | Monthly 1st, 06:00 | Enhanced |
| Restore drill | Monthly 15th, 04:00 | — |
| **AI Daily Report** | Daily 08:00 | **NEW** |
| **Predictive Scan** | Every 6 hours | **NEW** |
| **Embedding Refresh** | Daily 02:00 | **NEW** |
| **Capacity Report** | Weekly Sun 09:00 | **NEW** |
| **AI Model Health** | Hourly | **NEW** |

---

## Go-Live Checklist

| Check | Test | Expected |
|-------|------|----------|
| Preflight | `preflight.sh` | All PASSED |
| SSH key-only | `ssh root@<VPS_IP>` | Permission denied |
| UFW active | `ufw status` | Only 22, 80, 443, 51820 |
| WireGuard | `wg show` | wg0 active |
| MFA Keycloak | Login without TOTP | Fails |
| TLS active | `curl -v https://tickets.<domain>` | TLS 1.2/1.3 |
| Smoke tests | `make test` | All [OK] incl. AI |
| Ollama models | `docker exec mcp-ollama ollama list` | 4 models loaded |
| AI Gateway | `curl http://localhost:8000/health` | Status: healthy |
| AI test ticket | Send test alert | Ticket created in Zammad |
| RAG pipeline | Test query to pgvector | Relevant results |
| Predictive | `predictive-scan.sh` | Report generated |
| Daily report | `ai-daily-report.sh` | Report in wiki |
| Backup | `restic snapshots` | Includes AI data |
| DIUN | `docker logs mcp-diun` | Scans OK |
| Uptime Kuma | `status.<domain>` | Dashboard green |

---

## Versioning & Support Policy

* **7.x** — actively maintained (Beta)
* **6.x** — security patches only
* **≤5.x** — end of life

(Details in `SECURITY.md`.)

---

## Roadmap

| Phase | Feature | Description | Timeline |
|-------|---------|-------------|----------|
| v7.1 | AI Auto-Remediation | AI executes simple fixes autonomously (restart, scale, cleanup) | Q2 2026 |
| v7.2 | Customer Portal | Client dashboard with AI status updates | Q3 2026 |
| v7.3 | Multi-LLM | Dynamically route tasks to different models | Q3 2026 |
| v8.0 | Multi-Node | AI stack on dedicated GPU server | Q4 2026 |
| v8.1 | Fine-Tuning | Train LLM on own ticket data | Q1 2027 |
| v8.2 | Voice Interface | Phone-based status queries via AI | Q2 2027 |

---

## Licensing

**MCP is proprietary software.**
Copyright © <Owner/Company>. All rights reserved.

| Usage Type | Terms |
|---|---|
| **Evaluation** (Lab/Test) | Permitted only with written approval from the owner. No production use. |
| **Commercial License** | Individual license agreement required. |
| **Production Deployment** | Expressly prohibited without a valid license. |

**Third-party components** included via container images remain subject to their respective licenses and trademarks. MCP claims no ownership of these projects.

For licensing, partnerships, or evaluation access:

* **security@<your-domain>** — Security inquiries & responsible disclosure
* **contact@<your-domain>** — Commercial / Licensing / Partnerships

---

## Disclaimer

MCP is a technical platform. It must be validated in a lab environment and deployed with appropriate security measures.
The project documentation provides operational guidance but does not constitute legal or compliance advice.

---

<p align="center">
  <strong>MCP v7 — AI-Powered IT Operations Center</strong><br>
  <em>Local. Intelligent. Automated.</em>
</p>
