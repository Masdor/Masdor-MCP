#!/bin/bash
# ============================================================================
# MCP v7 — PostgreSQL Database Initialization
# ============================================================================
# This script runs inside the mcp-postgres container as the entrypoint
# init script. It creates all databases and roles needed by MCP services.
#
# Mount path: /docker-entrypoint-initdb.d/init-db.sh
# Runs automatically on first start when POSTGRES_DB data dir is empty.
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helper: Create role if not exists, with CREATEDB privilege
# ---------------------------------------------------------------------------
create_role() {
    local role_name="$1"
    local role_password="$2"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${role_name}') THEN
                CREATE ROLE ${role_name} WITH LOGIN PASSWORD '${role_password}' CREATEDB;
                RAISE NOTICE 'Role % created', '${role_name}';
            ELSE
                ALTER ROLE ${role_name} WITH PASSWORD '${role_password}' CREATEDB;
                RAISE NOTICE 'Role % already exists, updated password and CREATEDB', '${role_name}';
            END IF;
        END
        \$\$;
EOSQL
}

# ---------------------------------------------------------------------------
# Helper: Create database if not exists, owned by role
# ---------------------------------------------------------------------------
create_database() {
    local db_name="$1"
    local db_owner="$2"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        SELECT 'CREATE DATABASE ${db_name} OWNER ${db_owner}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')
        \gexec

        GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_owner};
EOSQL
}

echo "============================================"
echo "  MCP v7 — Database Initialization"
echo "============================================"

# ---------------------------------------------------------------------------
# 1. Create the mcp_admin database (referenced by some services)
# ---------------------------------------------------------------------------
echo "[1/8] Creating mcp_admin database..."
create_database "mcp_admin" "$POSTGRES_USER"

# ---------------------------------------------------------------------------
# 2. Keycloak
# ---------------------------------------------------------------------------
echo "[2/8] Creating Keycloak role and database..."
create_role "keycloak" "${KEYCLOAK_DB_PASSWORD}"
create_database "keycloak" "keycloak"

# ---------------------------------------------------------------------------
# 3. n8n
# ---------------------------------------------------------------------------
echo "[3/8] Creating n8n role and database..."
create_role "n8n" "${N8N_DB_PASSWORD}"
create_database "n8n" "n8n"

# ---------------------------------------------------------------------------
# 4. Zammad
# ---------------------------------------------------------------------------
echo "[4/8] Creating Zammad role and database..."
create_role "zammad" "${ZAMMAD_DB_PASSWORD}"
create_database "zammad" "zammad"

# ---------------------------------------------------------------------------
# 5. Grafana
# ---------------------------------------------------------------------------
echo "[5/8] Creating Grafana role and database..."
create_role "grafana" "${GRAFANA_DB_PASSWORD}"
create_database "grafana" "grafana"

# ---------------------------------------------------------------------------
# 6. Zabbix
# ---------------------------------------------------------------------------
echo "[6/8] Creating Zabbix role and database..."
create_role "zabbix" "${ZABBIX_DB_PASSWORD}"
create_database "zabbix" "zabbix"

# ---------------------------------------------------------------------------
# 7. Guacamole
# ---------------------------------------------------------------------------
echo "[7/8] Creating Guacamole role and database..."
create_role "guacamole" "${GUACAMOLE_DB_PASSWORD}"
create_database "guacamole" "guacamole"

# ---------------------------------------------------------------------------
# 8. Note: pgvector extension is handled by the dedicated mcp-pgvector
#    container (pgvector/pgvector image), NOT by this postgres instance.
#    DO NOT run CREATE EXTENSION vector here — it will fail (P1-004).
# ---------------------------------------------------------------------------
echo "[8/8] Skipping pgvector (handled by mcp-pgvector container)"

echo "============================================"
echo "  MCP v7 — Database Initialization COMPLETE"
echo "============================================"
echo ""
echo "Databases created:"
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c \
    "SELECT datname AS database, pg_catalog.pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datistemplate = false ORDER BY datname;"
echo ""
echo "Roles created:"
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c \
    "SELECT rolname, rolcreatedb FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolname != 'postgres' ORDER BY rolname;"
