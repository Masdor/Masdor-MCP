#!/bin/bash
# ============================================================================
# MCP v7 — Main Installation Script
# ============================================================================
# Usage:
#   sudo bash scripts/mcp-install.sh                  # Full installation
#   sudo bash scripts/mcp-install.sh --resume-from phase3  # Resume from phase 3
#   sudo bash scripts/mcp-install.sh --only phase6    # Run only phase 6
#   sudo bash scripts/mcp-install.sh --clean           # Clean and reinstall
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ERROR_LOG="${LOG_DIR}/mcp-install-error-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

gate_fail() {
    local phase="$1"
    local gate="$2"
    local cause="${3:-Unknown}"

    mkdir -p "$LOG_DIR"

    {
        echo "========================================"
        echo "MCP INSTALLATION FAILED"
        echo "========================================"
        echo "Timestamp: $(date)"
        echo "Phase:     ${phase}"
        echo "Gate:      ${gate}"
        echo "Cause:     ${cause}"
        echo ""
        echo "=== Docker Container Status ==="
        docker ps -a --filter "label=com.docker.compose.project=mcp" \
            --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        echo ""
        echo "=== System Resources ==="
        echo "RAM: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
        echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
        if command -v nvidia-smi &>/dev/null; then
            echo "GPU: $(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo 'Not available')"
        fi
    } > "$ERROR_LOG"

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  MCP INSTALLATION STOPPED                                    ║${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  Phase:     ${phase}${NC}"
    echo -e "${RED}║  Gate:      ${gate}${NC}"
    echo -e "${RED}║  Cause:     ${cause}${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  Error log: ${ERROR_LOG}${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  Fix the issue, then resume:                                 ║${NC}"
    echo -e "${RED}║    sudo bash scripts/mcp-install.sh --resume-from ${phase}${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    exit 1
}

wait_healthy() {
    local container="$1"
    local timeout="${2:-120}"
    local elapsed=0

    while [ $elapsed -lt "$timeout" ]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
        case "$status" in
            healthy)   return 0 ;;
            not_found) ;;
            *)         ;;
        esac
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# ---------------------------------------------------------------------------
# Phase 1: Preflight Checks
# ---------------------------------------------------------------------------
phase1_preflight() {
    log_info "Phase 1: Preflight Checks"
    echo "----------------------------------------"

    # Docker Engine
    if ! command -v docker &>/dev/null; then
        gate_fail "phase1" "Docker Engine not installed" "Install Docker: https://docs.docker.com/engine/install/"
    fi
    if ! docker info &>/dev/null; then
        gate_fail "phase1" "Docker daemon not running" "Start Docker: sudo systemctl start docker"
    fi
    log_ok "Docker Engine installed and running"

    # Docker Compose
    if ! docker compose version &>/dev/null; then
        gate_fail "phase1" "Docker Compose plugin not found" "Install: sudo apt install docker-compose-plugin"
    fi
    log_ok "Docker Compose plugin available"

    # .env file
    if [ ! -f "${PROJECT_DIR}/.env" ]; then
        gate_fail "phase1" ".env file not found" "Copy .env.example to .env and fill in values: cp .env.example .env"
    fi
    log_ok ".env file exists"

    # Source .env
    set -a
    # shellcheck source=/dev/null
    source "${PROJECT_DIR}/.env"
    set +a

    # Auto-generate BookStack APP_KEY if placeholder
    if grep -q "BOOKSTACK_APP_KEY=CHANGE_ME" "${PROJECT_DIR}/.env" 2>/dev/null; then
        NEW_KEY=$(openssl rand -base64 32)
        sed -i "s|BOOKSTACK_APP_KEY=CHANGE_ME.*|BOOKSTACK_APP_KEY=base64:${NEW_KEY}|" "${PROJECT_DIR}/.env"
        log_ok "BookStack APP_KEY auto-generated"
        # Re-source .env with new key
        set -a; source "${PROJECT_DIR}/.env"; set +a
    fi

    # Check for CHANGE_ME values
    if grep -q "CHANGE_ME" "${PROJECT_DIR}/.env"; then
        log_warn "Found CHANGE_ME values in .env — update all passwords before production!"
    fi

    # RAM check (warn if < 28 GB)
    local total_ram_kb
    total_ram_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))
    if [ "$total_ram_gb" -lt 28 ]; then
        log_warn "RAM: ${total_ram_gb} GB detected (minimum: 28 GB for full stack)"
    else
        log_ok "RAM: ${total_ram_gb} GB available"
    fi

    # Disk check (warn if < 50 GB free)
    local free_disk_gb
    free_disk_gb=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [ "$free_disk_gb" -lt 50 ]; then
        log_warn "Disk: ${free_disk_gb} GB free (minimum: 50 GB recommended)"
    else
        log_ok "Disk: ${free_disk_gb} GB free"
    fi

    # Sysctl tuning (Redis vm.overcommit_memory — P1-005)
    local overcommit
    overcommit=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "0")
    if [ "$overcommit" != "1" ]; then
        log_info "Setting vm.overcommit_memory=1 (required by Redis)"
        sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1 || log_warn "Could not set vm.overcommit_memory (not root?)"
        if ! grep -q "vm.overcommit_memory" /etc/sysctl.conf 2>/dev/null; then
            echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf 2>/dev/null || true
        fi
        log_ok "vm.overcommit_memory=1 set"
    else
        log_ok "vm.overcommit_memory already set to 1"
    fi

    # GPU check (optional — warn only)
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            log_ok "NVIDIA GPU detected"
        else
            log_warn "NVIDIA driver installed but GPU not responding"
        fi
    else
        log_warn "No NVIDIA GPU detected — Ollama will use CPU (slower inference)"
    fi

    log_ok "Phase 1: Preflight PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 2: Environment Setup (Networks + Volumes)
# ---------------------------------------------------------------------------
phase2_environment() {
    log_info "Phase 2: Environment Setup"
    echo "----------------------------------------"

    # Create Docker networks
    local networks=("mcp-edge-net:172.20.0.0/24" "mcp-app-net:172.20.1.0/24" "mcp-data-net:172.20.2.0/24" "mcp-sec-net:172.20.3.0/24" "mcp-ai-net:172.20.4.0/24")

    for net_def in "${networks[@]}"; do
        local net_name="${net_def%%:*}"
        local subnet="${net_def##*:}"
        if docker network inspect "$net_name" &>/dev/null; then
            log_ok "Network ${net_name} already exists"
        else
            docker network create \
                --driver bridge \
                --subnet "$subnet" \
                "$net_name" >/dev/null
            log_ok "Network ${net_name} created (${subnet})"
        fi
    done

    # Verify networks
    local net_count
    net_count=$(docker network ls --filter "name=mcp-" --format "{{.Name}}" | wc -l)
    if [ "$net_count" -lt 5 ]; then
        gate_fail "phase2" "Network creation failed" "Expected 5 networks, found ${net_count}"
    fi

    log_ok "All 5 Docker networks created"

    # Create ALL volumes upfront for ALL phases (P2-001)
    local volumes=(
        # Core Stack
        "mcp-postgres-data" "mcp-pgvector-data" "mcp-redis-data"
        "mcp-keycloak-data" "mcp-n8n-data" "mcp-ntfy-cache"
        # Ops Stack
        "mcp-elasticsearch-data" "mcp-zammad-data" "mcp-zammad-tmp"
        "mcp-bookstack-data" "mcp-vaultwarden-data" "mcp-portainer-data"
        # Telemetry Stack
        "mcp-grafana-data" "mcp-loki-data" "mcp-uptime-kuma-data" "mcp-crowdsec-data"
        # Remote Stack
        "mcp-meshcentral-data" "mcp-guacamole-data"
        # AI Stack
        "mcp-ollama-data" "mcp-redis-queue-data"
    )

    for vol in "${volumes[@]}"; do
        if docker volume inspect "$vol" &>/dev/null; then
            log_ok "Volume ${vol} already exists"
        else
            docker volume create "$vol" >/dev/null
            log_ok "Volume ${vol} created"
        fi
    done

    log_ok "All 20 Docker volumes created"

    # Create logs directory
    mkdir -p "${PROJECT_DIR}/logs"

    # YAML validation gate — validate all compose files before any deployment
    log_info "Validating Docker Compose files..."
    local compose_files=(
        "compose/core/docker-compose.yml"
        "compose/ops/docker-compose.yml"
        "compose/telemetry/docker-compose.yml"
        "compose/remote/docker-compose.yml"
        "compose/ai/docker-compose.yml"
    )
    for cf in "${compose_files[@]}"; do
        if [ -f "${PROJECT_DIR}/${cf}" ]; then
            if docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${cf}" config --quiet 2>/dev/null; then
                log_ok "YAML valid: ${cf}"
            else
                gate_fail "phase2" "YAML validation failed: ${cf}" "Run: docker compose -f ${cf} config"
            fi
        fi
    done

    log_ok "Phase 2: Environment Setup PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 3: Core Stack (#1-#8)
# ---------------------------------------------------------------------------
phase3_core() {
    log_info "Phase 3: Core Stack (8 containers)"
    echo "----------------------------------------"

    cd "$PROJECT_DIR"
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/core/docker-compose.yml up -d

    log_info "Waiting for Core containers to become healthy..."

    local core_containers=("mcp-postgres" "mcp-redis" "mcp-pgvector" "mcp-openbao" "mcp-nginx" "mcp-keycloak" "mcp-n8n" "mcp-ntfy")

    for container in "${core_containers[@]}"; do
        if wait_healthy "$container" 180; then
            log_ok "${container} is healthy"
        else
            gate_fail "phase3" "${container} not healthy" "Check logs: docker logs ${container} --tail 100"
        fi
    done

    log_ok "Phase 3: Core Stack PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 4: Ops Stack (#9-#16)
# ---------------------------------------------------------------------------
phase4_ops() {
    log_info "Phase 4: Ops Stack (8 containers + init)"
    echo "----------------------------------------"

    cd "$PROJECT_DIR"
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/ops/docker-compose.yml up -d

    log_info "Waiting for Ops containers..."

    # Wait for zammad-init to complete
    log_info "Waiting for Zammad init to complete (this may take a few minutes)..."
    local timeout=300
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local exit_code
        exit_code=$(docker inspect --format='{{.State.ExitCode}}' mcp-zammad-init 2>/dev/null || echo "-1")
        local running
        running=$(docker inspect --format='{{.State.Running}}' mcp-zammad-init 2>/dev/null || echo "false")
        if [ "$running" = "false" ] && [ "$exit_code" = "0" ]; then
            log_ok "mcp-zammad-init completed successfully"
            break
        elif [ "$running" = "false" ] && [ "$exit_code" != "0" ] && [ "$exit_code" != "-1" ]; then
            gate_fail "phase4" "Zammad init failed (exit code: ${exit_code})" "Check: docker logs mcp-zammad-init --tail 100"
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    local ops_containers=("mcp-zammad-rails" "mcp-elasticsearch" "mcp-bookstack" "mcp-vaultwarden")
    for container in "${ops_containers[@]}"; do
        if wait_healthy "$container" 180; then
            log_ok "${container} is healthy"
        else
            gate_fail "phase4" "${container} not healthy" "Check logs: docker logs ${container} --tail 100"
        fi
    done

    # Portainer has no /bin/sh — check running instead of healthy
    if docker ps --filter "name=mcp-portainer" --filter "status=running" -q | grep -q .; then
        log_ok "mcp-portainer is running"
    else
        gate_fail "phase4" "mcp-portainer not running" "Check logs: docker logs mcp-portainer --tail 100"
    fi

    log_ok "Phase 4: Ops Stack PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 5: Telemetry Stack (#17-#24)
# ---------------------------------------------------------------------------
phase5_telemetry() {
    log_info "Phase 5: Telemetry Stack (8 containers)"
    echo "----------------------------------------"

    cd "$PROJECT_DIR"
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/telemetry/docker-compose.yml up -d

    log_info "Waiting for Telemetry containers..."

    local telemetry_containers=("mcp-zabbix-server" "mcp-zabbix-web" "mcp-grafana" "mcp-loki" "mcp-uptime-kuma")
    for container in "${telemetry_containers[@]}"; do
        if wait_healthy "$container" 180; then
            log_ok "${container} is healthy"
        else
            gate_fail "phase5" "${container} not healthy" "Check logs: docker logs ${container} --tail 100"
        fi
    done

    log_ok "Phase 5: Telemetry Stack PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 6: AI Stack (#28-#32)
# ---------------------------------------------------------------------------
phase6_ai() {
    log_info "Phase 6: AI Stack (5 containers)"
    echo "----------------------------------------"

    cd "$PROJECT_DIR"

    # Start Ollama first to load models
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/ai/docker-compose.yml up -d ollama redis-queue
    log_info "Waiting for Ollama to start..."
    sleep 30

    # Pull AI models
    log_info "Pulling AI models (this may take a while)..."
    docker exec mcp-ollama ollama pull "${OLLAMA_MODEL:-mistral:7b}" || log_warn "Primary model pull failed"
    docker exec mcp-ollama ollama pull "${EMBEDDING_MODEL:-nomic-embed-text}" || log_warn "Embedding model pull failed"

    # Start remaining AI services
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/ai/docker-compose.yml up -d

    log_info "Waiting for AI containers..."

    local ai_containers=("mcp-ollama" "mcp-redis-queue" "mcp-ai-gateway")
    for container in "${ai_containers[@]}"; do
        if wait_healthy "$container" 180; then
            log_ok "${container} is healthy"
        else
            gate_fail "phase6" "${container} not healthy" "Check logs: docker logs ${container} --tail 100"
        fi
    done

    log_ok "Phase 6: AI Stack PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 7: Remote Stack (#25-#27)
# ---------------------------------------------------------------------------
phase7_remote() {
    log_info "Phase 7: Remote Stack (3 containers)"
    echo "----------------------------------------"

    cd "$PROJECT_DIR"
    docker compose -p "${COMPOSE_PROJECT_NAME:-mcp}" --env-file .env -f compose/remote/docker-compose.yml up -d

    log_info "Waiting for Remote containers..."

    if wait_healthy "mcp-meshcentral" 120; then
        log_ok "mcp-meshcentral is healthy"
    else
        log_warn "mcp-meshcentral not healthy yet (may need more time)"
    fi

    if wait_healthy "mcp-guacamole" 120; then
        log_ok "mcp-guacamole is healthy"
    else
        log_warn "mcp-guacamole not healthy yet (may need more time)"
    fi

    # guacd has no healthcheck — check running
    if docker ps --filter "name=mcp-guacd" --filter "status=running" -q | grep -q .; then
        log_ok "mcp-guacd is running"
    else
        log_warn "mcp-guacd not running"
    fi

    log_ok "Phase 7: Remote Stack PASSED"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================"
    echo "  MCP v7 — Installation"
    echo "  $(date)"
    echo "============================================"
    echo ""

    export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-mcp}"
    export COMPOSE_IGNORE_ORPHANS=1

    local start_phase=1
    local only_phase=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resume-from)
                start_phase="${2//[!0-9]/}"
                shift 2
                ;;
            --only)
                only_phase="${2//[!0-9]/}"
                start_phase="$only_phase"
                shift 2
                ;;
            --clean)
                log_warn "Clean installation — removing all existing containers and volumes"
                bash "${SCRIPT_DIR}/mcp-stop.sh" 2>/dev/null || true
                docker volume ls --filter "name=mcp-" -q | xargs -r docker volume rm 2>/dev/null || true
                docker network ls --filter "name=mcp-" -q | xargs -r docker network rm 2>/dev/null || true
                start_phase=1
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Usage: sudo bash scripts/mcp-install.sh [--resume-from phaseN] [--only phaseN] [--clean]"
                exit 1
                ;;
        esac
    done

    cd "$PROJECT_DIR"

    # Source .env
    if [ -f .env ]; then
        set -a
        # shellcheck source=/dev/null
        source .env
        set +a
    fi

    # Run phases
    if [ "$start_phase" -le 1 ]; then phase1_preflight; fi
    if [ "$only_phase" -gt 0 ] && [ "$only_phase" -ne 1 ] && [ "$start_phase" -le 1 ]; then :; fi

    if [ "$start_phase" -le 2 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 2 ]; }; then
        phase2_environment
    fi

    if [ "$start_phase" -le 3 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 3 ]; }; then
        phase3_core
    fi

    if [ "$start_phase" -le 4 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 4 ]; }; then
        phase4_ops
    fi

    if [ "$start_phase" -le 5 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 5 ]; }; then
        phase5_telemetry
    fi

    if [ "$start_phase" -le 6 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 6 ]; }; then
        phase6_ai
    fi

    if [ "$start_phase" -le 7 ] && { [ "$only_phase" -eq 0 ] || [ "$only_phase" -eq 7 ]; }; then
        phase7_remote
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  MCP INSTALLATION COMPLETE                                   ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  Dashboard: http://${MCP_HOST_IP:-192.168.1.100}              ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  Next steps:                                                 ║${NC}"
    echo -e "${GREEN}║    make status    — Check all containers                     ║${NC}"
    echo -e "${GREEN}║    make test      — Run all tests                            ║${NC}"
    echo -e "${GREEN}║    make logs      — View logs                                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

main "$@"
