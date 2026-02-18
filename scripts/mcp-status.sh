#!/bin/bash
# ============================================================================
# MCP v7 — Status of All 32 Containers
# ============================================================================
# Shows a table of all MCP containers grouped by stack.
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "============================================"
echo "  MCP v7 — Container Status"
echo "  $(date)"
echo "============================================"
echo ""

# Function to check one container
check_container() {
    local name="$1"
    local expected_name="$2"

    local status
    local health
    local restarts

    status=$(docker inspect --format='{{.State.Status}}' "$expected_name" 2>/dev/null || echo "not_found")
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' "$expected_name" 2>/dev/null || echo "unknown")
    restarts=$(docker inspect --format='{{.RestartCount}}' "$expected_name" 2>/dev/null || echo "?")

    local status_icon
    case "$status" in
        running)
            case "$health" in
                healthy)         status_icon="${GREEN}HEALTHY${NC}" ;;
                unhealthy)       status_icon="${RED}UNHEALTHY${NC}" ;;
                starting)        status_icon="${YELLOW}STARTING${NC}" ;;
                no_healthcheck)  status_icon="${YELLOW}RUNNING${NC}" ;;
                *)               status_icon="${YELLOW}RUNNING${NC}" ;;
            esac
            ;;
        exited)
            # Init containers (exit 0 is OK)
            local exit_code
            exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$expected_name" 2>/dev/null || echo "?")
            if [ "$exit_code" = "0" ]; then
                status_icon="${GREEN}DONE${NC}"
            else
                status_icon="${RED}EXITED(${exit_code})${NC}"
            fi
            ;;
        not_found) status_icon="${RED}NOT FOUND${NC}" ;;
        *)         status_icon="${RED}${status}${NC}" ;;
    esac

    printf "  %-28s %-20b  Restarts: %s\n" "$name" "$status_icon" "$restarts"
}

# --- Core Stack ---
echo -e "${CYAN}=== Core Stack (8 containers) ===${NC}"
check_container "#1  postgres"    "mcp-postgres"
check_container "#2  redis"       "mcp-redis"
check_container "#3  pgvector"    "mcp-pgvector"
check_container "#4  openbao"     "mcp-openbao"
check_container "#5  nginx"       "mcp-nginx"
check_container "#6  keycloak"    "mcp-keycloak"
check_container "#7  n8n"         "mcp-n8n"
check_container "#8  ntfy"        "mcp-ntfy"
echo ""

# --- Ops Stack ---
echo -e "${CYAN}=== Ops Stack (8 containers + init) ===${NC}"
check_container "    zammad-init" "mcp-zammad-init"
check_container "#9  zammad-rails"     "mcp-zammad-rails"
check_container "#10 zammad-websocket" "mcp-zammad-websocket"
check_container "#11 zammad-worker"    "mcp-zammad-worker"
check_container "#12 elasticsearch"    "mcp-elasticsearch"
check_container "#13 bookstack"        "mcp-bookstack"
check_container "#14 vaultwarden"      "mcp-vaultwarden"
check_container "#15 portainer"        "mcp-portainer"
check_container "#16 diun"             "mcp-diun"
echo ""

# --- Telemetry Stack ---
echo -e "${CYAN}=== Telemetry Stack (8 containers) ===${NC}"
check_container "#17 zabbix-server"    "mcp-zabbix-server"
check_container "#18 zabbix-web"       "mcp-zabbix-web"
check_container "#19 grafana"          "mcp-grafana"
check_container "#20 loki"             "mcp-loki"
check_container "#21 alloy"            "mcp-alloy"
check_container "#22 uptime-kuma"      "mcp-uptime-kuma"
check_container "#23 crowdsec"         "mcp-crowdsec"
check_container "#24 grafana-renderer" "mcp-grafana-renderer"
echo ""

# --- Remote Stack ---
echo -e "${CYAN}=== Remote Stack (3 containers) ===${NC}"
check_container "#25 meshcentral" "mcp-meshcentral"
check_container "#26 guacamole"   "mcp-guacamole"
check_container "#27 guacd"       "mcp-guacd"
echo ""

# --- AI Stack ---
echo -e "${CYAN}=== AI Stack (5 containers) ===${NC}"
check_container "#28 ollama"       "mcp-ollama"
check_container "#29 litellm"      "mcp-litellm"
check_container "#30 langchain"    "mcp-langchain"
check_container "#31 ai-gateway"   "mcp-ai-gateway"
check_container "#32 redis-queue"  "mcp-redis-queue"
echo ""

# Summary
total=$(docker ps --filter "label=com.docker.compose.project=mcp" -q 2>/dev/null | wc -l)
healthy=$(docker ps --filter "label=com.docker.compose.project=mcp" --filter "health=healthy" -q 2>/dev/null | wc -l)
unhealthy=$(docker ps --filter "label=com.docker.compose.project=mcp" --filter "health=unhealthy" -q 2>/dev/null | wc -l)

echo "============================================"
echo -e "  Running: ${GREEN}${total}${NC}  |  Healthy: ${GREEN}${healthy}${NC}  |  Unhealthy: ${RED}${unhealthy}${NC}"
echo "============================================"
echo ""
