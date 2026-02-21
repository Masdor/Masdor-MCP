#!/bin/bash
# ============================================================================
# MCP v7 — Generate .env for testing (WSL / local dev)
# ============================================================================
# Usage:
#   bash scripts/gen-test-env.sh            # Generate .env (won't overwrite)
#   bash scripts/gen-test-env.sh --force     # Overwrite existing .env
#   bash scripts/gen-test-env.sh --prod      # Production mode (root:root ownership)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FORCE=0
PROD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --prod)  PROD=1; shift ;;
        *)       echo "Unknown option: $1"; exit 1 ;;
    esac
done

ENV_FILE="${PROJECT_DIR}/.env"
EXAMPLE_FILE="${PROJECT_DIR}/.env.example"

if [ ! -f "$EXAMPLE_FILE" ]; then
    echo "ERROR: ${EXAMPLE_FILE} not found"
    exit 1
fi

if [ -f "$ENV_FILE" ] && [ "$FORCE" -eq 0 ]; then
    echo "ERROR: ${ENV_FILE} already exists. Use --force to overwrite."
    exit 1
fi

# Generate a random secret (URL-safe base64, 32 bytes)
gen_secret() {
    python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null \
        || openssl rand -base64 32 | tr -d '/+=' | head -c 44
}

echo "Generating .env from .env.example..."

# Copy template
cp "$EXAMPLE_FILE" "$ENV_FILE"

# Set WSL/test defaults
sed -i "s|^COMPOSE_PROJECT_NAME=.*|COMPOSE_PROJECT_NAME=mcp|" "$ENV_FILE"
sed -i "s|^MCP_HOST_IP=.*|MCP_HOST_IP=127.0.0.1|" "$ENV_FILE"

# Replace all CHANGE_ME values with random secrets
while IFS= read -r line; do
    if echo "$line" | grep -q "CHANGE_ME"; then
        var_name=$(echo "$line" | cut -d= -f1)
        new_secret=$(gen_secret)
        sed -i "s|^${var_name}=.*|${var_name}=${new_secret}|" "$ENV_FILE"
    fi
done < "$EXAMPLE_FILE"

# Auto-generate BookStack APP_KEY in base64 format
BOOKSTACK_KEY=$(openssl rand -base64 32)
sed -i "s|^BOOKSTACK_APP_KEY=.*|BOOKSTACK_APP_KEY=base64:${BOOKSTACK_KEY}|" "$ENV_FILE"

# Set file permissions
if [ "$PROD" -eq 1 ]; then
    chown root:root "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "Production mode: .env owned by root:root (600)"
else
    chmod 600 "$ENV_FILE"
    echo "Test mode: .env with 600 permissions"
fi

echo "Generated: ${ENV_FILE}"
echo "Project name: mcp"
echo "Host IP: 127.0.0.1"
echo ""
echo "Next: sudo bash scripts/mcp-install.sh"
