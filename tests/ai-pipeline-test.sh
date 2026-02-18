#!/bin/bash
# ============================================================================
# MCP v7 — AI Pipeline End-to-End Test
# ============================================================================
# Tests the complete AI pipeline: Alert → Queue → Analysis → Ticket
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Load env
if [ -f .env ]; then
    set -a; source .env; set +a
fi

AI_GATEWAY="http://127.0.0.1:8000"
if docker inspect mcp-ai-gateway &>/dev/null; then
    AI_GATEWAY="http://$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mcp-ai-gateway 2>/dev/null | head -1):8000"
fi

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
echo "  MCP v7 — AI Pipeline Test"
echo "  $(date)"
echo "============================================"
echo ""

# 1. AI Gateway health
echo "=== Step 1: AI Gateway Health ==="
health_result=$(docker exec mcp-ai-gateway curl -sf http://127.0.0.1:8000/health 2>/dev/null || echo "FAIL")
if echo "$health_result" | grep -q "status"; then
    check "AI Gateway is healthy" 0
else
    check "AI Gateway is healthy" 1
fi

# 2. Ollama models loaded
echo "=== Step 2: Ollama Models ==="
models=$(docker exec mcp-ollama ollama list 2>/dev/null || echo "")
if echo "$models" | grep -qi "mistral\|llama"; then
    check "Ollama has models loaded" 0
else
    check "Ollama has models loaded" 1
fi

# 3. Redis Queue accessible
echo "=== Step 3: Redis Queue ==="
redis_ping=$(docker exec mcp-redis-queue redis-cli ping 2>/dev/null || echo "")
check "Redis Queue responds to PING" "$([ "$redis_ping" = "PONG" ] && echo 0 || echo 1)"

# 4. Send test alert
echo "=== Step 4: Send Test Alert ==="
analyze_result=$(docker exec mcp-ai-gateway curl -sf \
    -X POST http://127.0.0.1:8000/api/v1/analyze \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${AI_GATEWAY_SECRET:-}" \
    -d '{
        "source": "test",
        "severity": "warning",
        "host": "mcp-test-host",
        "description": "Test: CPU usage above 80% for 5 minutes",
        "metrics": {"cpu": 82, "ram": 45, "disk": 60}
    }' 2>/dev/null || echo "FAIL")

if echo "$analyze_result" | grep -q "queued\|deduplicated"; then
    check "Test alert accepted by AI Gateway" 0
else
    check "Test alert accepted by AI Gateway" 1
fi

# 5. Job in Redis queue
echo "=== Step 5: Job in Queue ==="
sleep 2
queue_len=$(docker exec mcp-redis-queue redis-cli llen mcp:queue:analyze 2>/dev/null || echo "0")
jobs=$(docker exec mcp-redis-queue redis-cli keys "mcp:job:*" 2>/dev/null | wc -l || echo "0")
if [ "$jobs" -gt 0 ]; then
    check "Job exists in Redis" 0
else
    check "Job exists in Redis" 1
fi

echo ""
echo "============================================"
echo -e "  PASS: ${GREEN}${PASS}${NC}  |  FAIL: ${RED}${FAIL}${NC}"
echo "============================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
