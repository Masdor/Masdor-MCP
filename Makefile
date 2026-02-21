# ============================================================================
# MCP v7 — Managed Control Platform
# Makefile — Shortcuts for common operations
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if it exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

ENV_FILE := --env-file .env
COMPOSE_CORE := docker compose $(ENV_FILE) -f compose/core/docker-compose.yml
COMPOSE_OPS := docker compose $(ENV_FILE) -f compose/ops/docker-compose.yml
COMPOSE_TELEMETRY := docker compose $(ENV_FILE) -f compose/telemetry/docker-compose.yml
COMPOSE_REMOTE := docker compose $(ENV_FILE) -f compose/remote/docker-compose.yml
COMPOSE_AI := docker compose $(ENV_FILE) -f compose/ai/docker-compose.yml

# === LIFECYCLE ==============================================================

.PHONY: up
up: ## Start all stacks (Core → Ops → Telemetry → Remote → AI)
	@bash scripts/mcp-start.sh

.PHONY: down
down: ## Stop all stacks (AI → Remote → Telemetry → Ops → Core)
	@bash scripts/mcp-stop.sh

.PHONY: restart
restart: down up ## Restart all stacks

# === INDIVIDUAL STACKS ======================================================

.PHONY: up-core
up-core: ## Start Core stack only
	$(COMPOSE_CORE) up -d

.PHONY: up-ops
up-ops: ## Start Ops stack only
	$(COMPOSE_OPS) up -d

.PHONY: up-telemetry
up-telemetry: ## Start Telemetry stack only
	$(COMPOSE_TELEMETRY) up -d

.PHONY: up-remote
up-remote: ## Start Remote stack only
	$(COMPOSE_REMOTE) up -d

.PHONY: up-ai
up-ai: ## Start AI stack only
	$(COMPOSE_AI) up -d

.PHONY: down-core
down-core: ## Stop Core stack
	$(COMPOSE_CORE) down

.PHONY: down-ops
down-ops: ## Stop Ops stack
	$(COMPOSE_OPS) down

.PHONY: down-telemetry
down-telemetry: ## Stop Telemetry stack
	$(COMPOSE_TELEMETRY) down

.PHONY: down-remote
down-remote: ## Stop Remote stack
	$(COMPOSE_REMOTE) down

.PHONY: down-ai
down-ai: ## Stop AI stack
	$(COMPOSE_AI) down

# === STATUS & LOGS ==========================================================

.PHONY: status
status: ## Show status of all containers
	@bash scripts/mcp-status.sh

.PHONY: ps
ps: ## Show running containers (docker ps)
	@docker ps --filter "label=com.docker.compose.project=mcp" \
		--format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

.PHONY: logs
logs: ## Tail logs for all stacks (Ctrl+C to stop)
	@docker ps --filter "label=com.docker.compose.project=mcp" -q | \
		xargs -r docker logs --tail 20 --follow 2>&1

.PHONY: logs-core
logs-core: ## Tail Core stack logs
	$(COMPOSE_CORE) logs -f --tail 50

.PHONY: logs-ops
logs-ops: ## Tail Ops stack logs
	$(COMPOSE_OPS) logs -f --tail 50

.PHONY: logs-telemetry
logs-telemetry: ## Tail Telemetry stack logs
	$(COMPOSE_TELEMETRY) logs -f --tail 50

.PHONY: logs-remote
logs-remote: ## Tail Remote stack logs
	$(COMPOSE_REMOTE) logs -f --tail 50

.PHONY: logs-ai
logs-ai: ## Tail AI stack logs
	$(COMPOSE_AI) logs -f --tail 50

# === TESTING ================================================================

.PHONY: test
test: ## Run all tests (smoke + AI pipeline + security)
	@echo "=== Smoke Test ==="
	@bash tests/smoke-test.sh
	@echo ""
	@echo "=== AI Pipeline Test ==="
	@bash tests/ai-pipeline-test.sh
	@echo ""
	@echo "=== Security Test ==="
	@bash tests/security-test.sh

.PHONY: test-smoke
test-smoke: ## Run smoke tests only
	@bash tests/smoke-test.sh

.PHONY: test-ai
test-ai: ## Run AI pipeline tests only
	@bash tests/ai-pipeline-test.sh

.PHONY: test-security
test-security: ## Run security tests only
	@bash tests/security-test.sh

# === BACKUP & RESTORE =======================================================

.PHONY: backup
backup: ## Create full backup
	@bash scripts/mcp-backup.sh

.PHONY: restore
restore: ## Restore from backup (interactive)
	@bash scripts/mcp-restore.sh

# === INSTALLATION ===========================================================

.PHONY: install
install: ## Run full installation (7 phases with gate checks)
	@sudo bash scripts/mcp-install.sh

.PHONY: pull-images
pull-images: ## Pull all Docker images (requires internet)
	@bash scripts/mcp-pull-images.sh

# === CLEANUP ================================================================

.PHONY: clean
clean: ## Stop all containers and remove volumes (DESTRUCTIVE)
	@echo "WARNING: This will stop all containers and remove all data!"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	$(COMPOSE_AI) down -v 2>/dev/null || true
	$(COMPOSE_REMOTE) down -v 2>/dev/null || true
	$(COMPOSE_TELEMETRY) down -v 2>/dev/null || true
	$(COMPOSE_OPS) down -v 2>/dev/null || true
	$(COMPOSE_CORE) down -v 2>/dev/null || true
	@echo "All containers stopped and volumes removed."

# === HELP ===================================================================

.PHONY: help
help: ## Show this help
	@echo "MCP v7 — Managed Control Platform"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
