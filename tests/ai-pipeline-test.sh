#!/bin/bash
# ============================================================================
# MCP v7 — AI Pipeline End-to-End Test
# ============================================================================
# Tests the complete AI pipeline: Alert → Queue → Analysis → Ticket
# Uses only Python stdlib inside containers (no curl dependency).
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

# 1. AI Gateway health (Python stdlib — no curl)
echo "=== Step 1: AI Gateway Health ==="
health_result=$(docker exec -e AI_GATEWAY_SECRET="${AI_GATEWAY_SECRET:-}" mcp-ai-gateway python -c "
import urllib.request, json, sys
try:
    r = urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5)
    data = json.loads(r.read())
    print(json.dumps(data))
except Exception as e:
    print(f'FAIL: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "FAIL")
if echo "$health_result" | grep -q "status"; then
    check "AI Gateway is healthy" 0
else
    echo "    Response: $health_result"
    check "AI Gateway is healthy" 1
fi

# 2. Ollama models loaded
echo "=== Step 2: Ollama Models ==="
models=$(docker exec mcp-ollama ollama list 2>/dev/null || echo "")
if echo "$models" | grep -qi "mistral\|llama\|nomic"; then
    check "Ollama has models loaded" 0
else
    echo "    Models: $models"
    check "Ollama has models loaded" 1
fi

# 3. Redis Queue accessible
echo "=== Step 3: Redis Queue ==="
redis_ping=$(docker exec mcp-redis-queue redis-cli ping 2>/dev/null || echo "")
check "Redis Queue responds to PING" "$([ "$redis_ping" = "PONG" ] && echo 0 || echo 1)"

# 4. Send test alert via Python stdlib
echo "=== Step 4: Send Test Alert ==="
TIMESTAMP=$(date +%s)
analyze_result=$(docker exec -e AI_GATEWAY_SECRET="${AI_GATEWAY_SECRET:-}" mcp-ai-gateway python -c "
import urllib.request, json, sys, os

secret = os.environ.get('AI_GATEWAY_SECRET', '')
url = 'http://127.0.0.1:8000/api/v1/analyze'
payload = json.dumps({
    'source': 'test',
    'severity': 'warning',
    'host': 'mcp-test-host',
    'description': 'Pipeline test ${TIMESTAMP}: CPU usage above 80%',
    'metrics': {'cpu': 82, 'ram': 45, 'disk': 60},
    'logs': 'test log entry ${TIMESTAMP}'
}).encode()

headers = {'Content-Type': 'application/json'}
if secret:
    headers['Authorization'] = f'Bearer {secret}'

req = urllib.request.Request(url, data=payload, headers=headers)
try:
    r = urllib.request.urlopen(req, timeout=10)
    data = r.read().decode()
    print(data)
except urllib.error.HTTPError as e:
    body = e.read().decode() if e.fp else ''
    print(f'HTTP {e.code}: {body}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'FAIL: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 || echo "FAIL")

if echo "$analyze_result" | grep -q "queued\|deduplicated\|job_id"; then
    check "Test alert accepted by AI Gateway" 0
else
    echo "    Response: $analyze_result"
    check "Test alert accepted by AI Gateway" 1
fi

# 5. Job in Redis queue
echo "=== Step 5: Job in Queue ==="
sleep 2
# Search multiple key patterns
jobs=$(docker exec mcp-redis-queue redis-cli keys "mcp:job:*" 2>/dev/null | wc -l || echo "0")
queue_len=$(docker exec mcp-redis-queue redis-cli llen "mcp:queue:analyze" 2>/dev/null || echo "0")
dedup_keys=$(docker exec mcp-redis-queue redis-cli keys "mcp:dedup:*" 2>/dev/null | wc -l || echo "0")
total_keys=$((jobs + dedup_keys))

if [ "$total_keys" -gt 0 ] || [ "$queue_len" -gt 0 ]; then
    check "Job/dedup key exists in Redis (jobs=$jobs, dedup=$dedup_keys, queue=$queue_len)" 0
else
    # Fallback: scan for any mcp-related keys
    all_keys=$(docker exec mcp-redis-queue redis-cli keys "*" 2>/dev/null | wc -l || echo "0")
    echo "    Total Redis keys: $all_keys"
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
