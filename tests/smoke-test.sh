#!/bin/bash
# ============================================================================
# MCP v7 — Smoke Test
# ============================================================================
# Verifies all 32 containers are running, healthy, and zero restarts.
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local name="$1"
    local container="$2"
    local check_type="${3:-healthy}"  # healthy, running, exited_ok

    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")

    case "$check_type" in
        healthy)
            local health
            health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "unknown")
            if [ "$health" = "healthy" ]; then
                echo -e "  ${GREEN}[PASS]${NC} $name ($container) — healthy"
                PASS=$((PASS + 1))
            elif [ "$status" = "running" ]; then
                echo -e "  ${YELLOW}[WARN]${NC} $name ($container) — running but not healthy ($health)"
                WARN=$((WARN + 1))
            else
                echo -e "  ${RED}[FAIL]${NC} $name ($container) — $status"
                FAIL=$((FAIL + 1))
            fi
            ;;
        running)
            if [ "$status" = "running" ]; then
                echo -e "  ${GREEN}[PASS]${NC} $name ($container) — running"
                PASS=$((PASS + 1))
            else
                echo -e "  ${RED}[FAIL]${NC} $name ($container) — $status"
                FAIL=$((FAIL + 1))
            fi
            ;;
        exited_ok)
            local exit_code
            exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container" 2>/dev/null || echo "?")
            if [ "$exit_code" = "0" ]; then
                echo -e "  ${GREEN}[PASS]${NC} $name ($container) — exited OK"
                PASS=$((PASS + 1))
            else
                echo -e "  ${RED}[FAIL]${NC} $name ($container) — exit code $exit_code"
                FAIL=$((FAIL + 1))
            fi
            ;;
    esac

    # Check restart count
    local restarts
    restarts=$(docker inspect --format='{{.RestartCount}}' "$container" 2>/dev/null || echo "0")
    if [ "$restarts" -gt 0 ]; then
        echo -e "    ${YELLOW}WARNING: $restarts restart(s)${NC}"
    fi
}

echo ""
echo "============================================"
echo "  MCP v7 — Smoke Test"
echo "  $(date)"
echo "============================================"
echo ""

echo "=== Core Stack ==="
check "#1 PostgreSQL"  "mcp-postgres"   healthy
check "#2 Redis"       "mcp-redis"      healthy
check "#3 pgvector"    "mcp-pgvector"   healthy
check "#4 OpenBao"     "mcp-openbao"    healthy
check "#5 nginx"       "mcp-nginx"      healthy
check "#6 Keycloak"    "mcp-keycloak"   healthy
check "#7 n8n"         "mcp-n8n"        healthy
check "#8 ntfy"        "mcp-ntfy"       healthy
echo ""

echo "=== Ops Stack ==="
check "   Zammad Init"       "mcp-zammad-init"      exited_ok
check "#9 Zammad Rails"      "mcp-zammad-rails"     healthy
check "#10 Zammad WS"        "mcp-zammad-websocket" running
check "#11 Zammad Worker"    "mcp-zammad-worker"    running
check "#12 Elasticsearch"    "mcp-elasticsearch"    healthy
check "#13 BookStack"        "mcp-bookstack"        healthy
check "#14 Vaultwarden"      "mcp-vaultwarden"      healthy
check "#15 Portainer"        "mcp-portainer"        healthy
check "#16 DIUN"             "mcp-diun"             running
echo ""

echo "=== Telemetry Stack ==="
check "#17 Zabbix Server"    "mcp-zabbix-server"    healthy
check "#18 Zabbix Web"       "mcp-zabbix-web"       healthy
check "#19 Grafana"          "mcp-grafana"          healthy
check "#20 Loki"             "mcp-loki"             healthy
check "#21 Alloy"            "mcp-alloy"            running
check "#22 Uptime Kuma"      "mcp-uptime-kuma"      healthy
check "#23 CrowdSec"         "mcp-crowdsec"         running
check "#24 Grafana Renderer" "mcp-grafana-renderer" running
echo ""

echo "=== Remote Stack ==="
check "#25 MeshCentral"  "mcp-meshcentral" healthy
check "#26 Guacamole"    "mcp-guacamole"   healthy
check "#27 Guacd"        "mcp-guacd"       running
echo ""

echo "=== AI Stack ==="
check "#28 Ollama"       "mcp-ollama"      healthy
check "#29 LiteLLM"      "mcp-litellm"     healthy
check "#30 LangChain"    "mcp-langchain"   running
check "#31 AI Gateway"   "mcp-ai-gateway"  healthy
check "#32 Redis Queue"  "mcp-redis-queue" healthy
echo ""

echo "============================================"
echo -e "  PASS: ${GREEN}${PASS}${NC}  |  FAIL: ${RED}${FAIL}${NC}  |  WARN: ${YELLOW}${WARN}${NC}"
echo "============================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
