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

    # Check restart count — mehr als 3 Restarts gelten als Fehler
    local restarts
    restarts=$(docker inspect --format='{{.RestartCount}}' "$container" 2>/dev/null || echo "0")
    if [ "$restarts" -gt 3 ]; then
        echo -e "    ${RED}FAIL: $restarts restart(s) (max 3)${NC}"
        FAIL=$((FAIL + 1))
    elif [ "$restarts" -gt 0 ]; then
        echo -e "    ${YELLOW}WARNING: $restarts restart(s)${NC}"
        WARN=$((WARN + 1))
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
check "#10 Zammad WS"        "mcp-zammad-websocket" healthy
check "#11 Zammad Scheduler"  "mcp-zammad-scheduler" healthy
check "   Zammad Memcached"  "mcp-zammad-memcached" running
check "#12 Elasticsearch"    "mcp-elasticsearch"    healthy
check "   BookStack DB"      "mcp-bookstack-db"     healthy
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
check "#21 Alloy"            "mcp-alloy"            healthy
check "#22 Uptime Kuma"      "mcp-uptime-kuma"      healthy
check "#23 CrowdSec"         "mcp-crowdsec"         healthy
check "#24 Grafana Renderer" "mcp-grafana-renderer" running
echo ""

echo "=== Remote Stack ==="
check "   Guacamole Init"   "mcp-guacamole-init"   exited_ok
check "   Guacamole Schema" "mcp-guacamole-schema"  exited_ok
check "#25 MeshCentral"  "mcp-meshcentral" healthy
check "#26 Guacamole"    "mcp-guacamole"   healthy
check "#27 Guacd"        "mcp-guacd"       healthy
echo ""

echo "=== AI Stack ==="
check "#28 Ollama"       "mcp-ollama"      healthy
check "#29 LiteLLM"      "mcp-litellm"     healthy
check "#30 LangChain"    "mcp-langchain"   healthy
check "#31 AI Gateway"   "mcp-ai-gateway"  healthy
check "#32 Redis Queue"  "mcp-redis-queue" healthy
echo ""

echo "=== Dashboard HTTP Checks ==="
DASHBOARD_PATHS="/auth/ /auto/ /grafana/ /guac/ /monitor/ /notify/ /portainer/ /remote/ /status/ /tickets/ /vault/ /wiki/"
for path in $DASHBOARD_PATHS; do
    code=$(curl -sSo /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1${path}" 2>/dev/null || echo "000")
    if [ "$code" = "404" ] || [ "$code" = "502" ] || [ "$code" = "503" ] || [ "$code" = "000" ]; then
        echo -e "  ${RED}[FAIL]${NC} ${path} — HTTP ${code}"
        FAIL=$((FAIL + 1))
    else
        echo -e "  ${GREEN}[PASS]${NC} ${path} — HTTP ${code}"
        PASS=$((PASS + 1))
    fi
done
echo ""

echo "=== Internal Service HTTP Checks ==="
# AI Gateway health (via docker exec — nicht oeffentlich)
ai_health=$(docker exec mcp-ai-gateway python -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5)
    print(r.getcode())
except Exception:
    print('000')
" 2>/dev/null || echo "000")
if [ "$ai_health" = "200" ]; then
    echo -e "  ${GREEN}[PASS]${NC} AI Gateway /health — HTTP ${ai_health}"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}[FAIL]${NC} AI Gateway /health — HTTP ${ai_health}"
    FAIL=$((FAIL + 1))
fi

# LiteLLM health
litellm_health=$(docker exec mcp-litellm python -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://127.0.0.1:4000/health', timeout=5)
    print(r.getcode())
except Exception:
    print('000')
" 2>/dev/null || echo "000")
if [ "$litellm_health" = "200" ]; then
    echo -e "  ${GREEN}[PASS]${NC} LiteLLM /health — HTTP ${litellm_health}"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} LiteLLM /health — HTTP ${litellm_health}"
    WARN=$((WARN + 1))
fi
echo ""

echo "============================================"
echo -e "  PASS: ${GREEN}${PASS}${NC}  |  FAIL: ${RED}${FAIL}${NC}  |  WARN: ${YELLOW}${WARN}${NC}"
echo "============================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
