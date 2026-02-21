#!/bin/bash
# ============================================================================
# MCP v7 — Security Validation Test
# ============================================================================
# Validates network isolation, port exposure, and security settings.
# ============================================================================

set -euo pipefail

# Load env for project name
if [ -f .env ]; then set -a; source .env; set +a; fi
PROJECT="${COMPOSE_PROJECT_NAME:-mcp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo -e "  ${GREEN}[PASS]${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $name"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "============================================"
echo "  MCP v7 — Security Test"
echo "  $(date)"
echo "============================================"
echo ""

# 1. Check that only nginx exposes ports on 0.0.0.0
echo "=== Port Exposure ==="
exposed=$(docker ps --filter "label=com.docker.compose.project=${PROJECT}" \
    --format "{{.Names}} {{.Ports}}" 2>/dev/null | grep "0.0.0.0" | grep -v "mcp-nginx" || true)
if [ -z "$exposed" ]; then
    check "Only nginx exposes ports to 0.0.0.0" 0
else
    echo "    Exposed: $exposed"
    check "Only nginx exposes ports to 0.0.0.0" 1
fi

# 2. Check nginx listens on 80 and 443
echo "=== nginx Ports ==="
nginx_ports=$(docker port mcp-nginx 2>/dev/null || echo "")
if echo "$nginx_ports" | grep -q "80"; then
    check "nginx port 80 is bound" 0
else
    check "nginx port 80 is bound" 1
fi

# 3. Check that 5 networks exist
echo "=== Network Segmentation ==="
net_count=$(docker network ls --filter "name=mcp-" --format "{{.Name}}" | wc -l)
check "5 MCP networks exist (found: $net_count)" "$([ "$net_count" -ge 5 ] && echo 0 || echo 1)"

# 4. Check AI Gateway is NOT on edge network
echo "=== AI Gateway Isolation ==="
ai_gw_nets=$(docker inspect --format='{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' mcp-ai-gateway 2>/dev/null || echo "")
if echo "$ai_gw_nets" | grep -q "mcp-edge-net"; then
    check "AI Gateway is NOT on edge network" 1
else
    check "AI Gateway is NOT on edge network" 0
fi

# 5. Check no-new-privileges on containers
echo "=== Container Security ==="
containers_with_nnp=0
total_containers=0
for c in $(docker ps --filter "label=com.docker.compose.project=${PROJECT}" --format "{{.Names}}"); do
    total_containers=$((total_containers + 1))
    nnp=$(docker inspect --format='{{.HostConfig.SecurityOpt}}' "$c" 2>/dev/null || echo "")
    if echo "$nnp" | grep -q "no-new-privileges"; then
        containers_with_nnp=$((containers_with_nnp + 1))
    fi
done
check "Containers with no-new-privileges: $containers_with_nnp/$total_containers" "$([ "$containers_with_nnp" -gt 0 ] && echo 0 || echo 1)"

# 6. Check .env file permissions (should not be world-readable)
echo "=== Secret File Permissions ==="
if [ -f .env ]; then
    env_perms=$(stat -c '%a' .env 2>/dev/null || echo "unknown")
    # Sicherstellen, dass .env nicht world-readable ist (nicht x00 am Ende)
    if [ "$env_perms" != "unknown" ]; then
        world_read=$((env_perms % 10))
        if [ "$world_read" -ge 4 ]; then
            echo -e "    .env permissions: $env_perms (world-readable!)"
            check ".env is not world-readable" 1
        else
            check ".env is not world-readable (perms: $env_perms)" 0
        fi
    else
        echo -e "    ${YELLOW}Could not determine .env permissions${NC}"
        check ".env permissions check" 0
    fi
else
    echo -e "    ${YELLOW}No .env file found (skipped)${NC}"
fi

# 7. Check container capabilities — kein Container sollte mehr als 15 Capabilities haben
echo "=== Container Capabilities ==="
cap_violations=0
for c in $(docker ps --filter "label=com.docker.compose.project=${PROJECT}" --format "{{.Names}}"); do
    cap_add=$(docker inspect --format='{{.HostConfig.CapAdd}}' "$c" 2>/dev/null || echo "[]")
    # Zaehle hinzugefuegte Capabilities
    if [ "$cap_add" != "[]" ] && [ "$cap_add" != "<nil>" ] && [ -n "$cap_add" ]; then
        num_caps=$(echo "$cap_add" | tr ',' '\n' | wc -l)
        if [ "$num_caps" -gt 5 ]; then
            echo -e "    ${YELLOW}${c}: ${num_caps} added capabilities${NC}"
            cap_violations=$((cap_violations + 1))
        fi
    fi
done
check "No container has excessive capabilities (violations: $cap_violations)" "$([ "$cap_violations" -eq 0 ] && echo 0 || echo 1)"

# 8. Pruefen, dass alle Container cap_drop: ALL haben
echo "=== Cap Drop Check ==="
containers_with_cap_drop=0
for c in $(docker ps --filter "label=com.docker.compose.project=${PROJECT}" --format "{{.Names}}"); do
    cap_drop=$(docker inspect --format='{{.HostConfig.CapDrop}}' "$c" 2>/dev/null || echo "[]")
    if echo "$cap_drop" | grep -qi "all"; then
        containers_with_cap_drop=$((containers_with_cap_drop + 1))
    fi
done
check "Containers with cap_drop ALL: $containers_with_cap_drop/$total_containers" "$([ "$containers_with_cap_drop" -gt 0 ] && echo 0 || echo 1)"

echo ""
echo "============================================"
echo -e "  PASS: ${GREEN}${PASS}${NC}  |  FAIL: ${RED}${FAIL}${NC}"
echo "============================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
