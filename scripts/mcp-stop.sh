#!/bin/bash
# ============================================================================
# MCP v7 — Stop All Stacks
# ============================================================================
# Stops stacks in reverse dependency order: AI → Remote → Telemetry → Ops → Core
# This ensures clean shutdown with no orphaned connections.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

cd "$PROJECT_DIR"

# Source .env for project name and suppress orphan warnings
if [ -f .env ]; then
    set -a; source .env; set +a
fi
export COMPOSE_IGNORE_ORPHANS=1

# ENV_FILE nur setzen wenn .env existiert (sonst scheitert docker compose leise)
if [ -f .env ]; then
    ENV_FILE="--env-file .env"
else
    ENV_FILE=""
fi

echo ""
echo "============================================"
echo "  MCP v7 — Stopping All Stacks"
echo "  $(date)"
echo "============================================"
echo ""

# 1. AI Stack (depends on pgvector, redis — stop first)
log_info "Stopping AI Stack..."
docker compose ${ENV_FILE} -f compose/ai/docker-compose.yml down 2>/dev/null || true
log_ok "AI Stack stopped"

# 2. Remote Stack
log_info "Stopping Remote Stack..."
docker compose ${ENV_FILE} -f compose/remote/docker-compose.yml down 2>/dev/null || true
log_ok "Remote Stack stopped"

# 3. Telemetry Stack (depends on databases)
log_info "Stopping Telemetry Stack..."
docker compose ${ENV_FILE} -f compose/telemetry/docker-compose.yml down 2>/dev/null || true
log_ok "Telemetry Stack stopped"

# 4. Ops Stack (depends on databases)
log_info "Stopping Ops Stack..."
docker compose ${ENV_FILE} -f compose/ops/docker-compose.yml down 2>/dev/null || true
log_ok "Ops Stack stopped"

# 5. Core Stack (databases, proxy — stop last)
log_info "Stopping Core Stack..."
docker compose ${ENV_FILE} -f compose/core/docker-compose.yml down 2>/dev/null || true
log_ok "Core Stack stopped"

echo ""
log_ok "All stacks stopped"
echo ""
