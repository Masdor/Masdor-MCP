#!/bin/bash
# ============================================================================
# MCP v7 — Start All Stacks
# ============================================================================
# Starts stacks in dependency order: Core → Ops → Telemetry → Remote → AI
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

cd "$PROJECT_DIR"

# Check .env
if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Copy .env.example to .env first."
    exit 1
fi

ENV_FILE="--env-file .env"

echo ""
echo "============================================"
echo "  MCP v7 — Starting All Stacks"
echo "  $(date)"
echo "============================================"
echo ""

# 1. Core Stack
log_info "Starting Core Stack (postgres, redis, pgvector, openbao, nginx, keycloak, n8n, ntfy)..."
docker compose ${ENV_FILE} -f compose/core/docker-compose.yml up -d
log_ok "Core Stack started"

# Wait for databases to be ready before proceeding
log_info "Waiting for databases to initialize..."
sleep 15

# 2. Ops Stack
log_info "Starting Ops Stack (zammad, elasticsearch, bookstack, vaultwarden, portainer, diun)..."
docker compose ${ENV_FILE} -f compose/ops/docker-compose.yml up -d
log_ok "Ops Stack started"

# 3. Telemetry Stack
log_info "Starting Telemetry Stack (zabbix, grafana, loki, alloy, uptime-kuma, crowdsec)..."
docker compose ${ENV_FILE} -f compose/telemetry/docker-compose.yml up -d
log_ok "Telemetry Stack started"

# 4. Remote Stack
log_info "Starting Remote Stack (meshcentral, guacamole, guacd)..."
docker compose ${ENV_FILE} -f compose/remote/docker-compose.yml up -d
log_ok "Remote Stack started"

# 5. AI Stack
log_info "Starting AI Stack (ollama, litellm, langchain, ai-gateway, redis-queue)..."
docker compose ${ENV_FILE} -f compose/ai/docker-compose.yml up -d
log_ok "AI Stack started"

echo ""
log_ok "All 5 stacks started successfully"
echo ""
log_info "Check status: make status"
log_info "View logs:    make logs"
echo ""
