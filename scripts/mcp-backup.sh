#!/bin/bash
# ============================================================================
# MCP v7 — Backup Script
# ============================================================================
# Erstellt ein vollstaendiges Backup aller Datenbanken und Docker-Volumes.
# Verwendung: ./scripts/mcp-backup.sh [backup-verzeichnis]
# ============================================================================

set -euo pipefail

BACKUP_DIR="${1:-/tmp/mcp-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/mcp-backup-${TIMESTAMP}"

# Cleanup bei Fehler
cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "FEHLER: Backup fehlgeschlagen (Exit-Code: ${exit_code})"
        if [ -d "${BACKUP_PATH}" ]; then
            echo "Bereinige unvollstaendiges Backup..."
            rm -rf "${BACKUP_PATH}"
        fi
    fi
}
trap cleanup EXIT

echo "============================================"
echo "  MCP v7 — Backup gestartet"
echo "  Zeitstempel: ${TIMESTAMP}"
echo "  Zielverzeichnis: ${BACKUP_PATH}"
echo "============================================"

# ---------------------------------------------------------------------------
# Disk-Space pruefen (mindestens 5 GB frei)
# ---------------------------------------------------------------------------
mkdir -p "${BACKUP_DIR}"
available_kb=$(df "${BACKUP_DIR}" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -z "$available_kb" ] || ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
    echo "FEHLER: Konnte freien Speicherplatz auf ${BACKUP_DIR} nicht ermitteln"
    exit 1
fi
available_gb=$((available_kb / 1024 / 1024))
if [ "$available_gb" -lt 5 ]; then
    echo "FEHLER: Nur ${available_gb} GB frei auf ${BACKUP_DIR} (Minimum: 5 GB)"
    exit 1
fi
echo "  Freier Speicher: ${available_gb} GB"
echo ""

mkdir -p "${BACKUP_PATH}"

# ---------------------------------------------------------------------------
# 1. PostgreSQL Dump (mcp-postgres)
# ---------------------------------------------------------------------------
echo "[1/4] PostgreSQL Dump..."
if docker ps --format '{{.Names}}' | grep -q "mcp-postgres"; then
    docker exec mcp-postgres pg_dumpall -U postgres \
        > "${BACKUP_PATH}/postgres-all.sql" 2>/dev/null
    echo "  OK: postgres-all.sql ($(du -sh "${BACKUP_PATH}/postgres-all.sql" | cut -f1))"
else
    echo "  WARNUNG: mcp-postgres Container nicht gestartet — ueberspringe"
fi

# ---------------------------------------------------------------------------
# 2. pgvector Dump (mcp-pgvector)
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] pgvector Dump..."
if docker ps --format '{{.Names}}' | grep -q "mcp-pgvector"; then
    docker exec mcp-pgvector pg_dump -U "${PGVECTOR_USER:-pgvector}" \
        "${PGVECTOR_DB:-mcp_vectors}" \
        > "${BACKUP_PATH}/pgvector.sql" 2>/dev/null
    echo "  OK: pgvector.sql ($(du -sh "${BACKUP_PATH}/pgvector.sql" | cut -f1))"
else
    echo "  WARNUNG: mcp-pgvector Container nicht gestartet — ueberspringe"
fi

# ---------------------------------------------------------------------------
# 3. Docker Volume Backups
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Docker Volumes sichern..."

VOLUMES=(
    mcp-postgres-data
    mcp-redis-data
    mcp-pgvector-data
    mcp-n8n-data
    mcp-grafana-data
    mcp-loki-data
    mcp-elasticsearch-data
    mcp-zammad-data
    mcp-zammad-tmp
    mcp-bookstack-data
    mcp-vaultwarden-data
    mcp-portainer-data
    mcp-uptime-kuma-data
    mcp-crowdsec-data
    mcp-meshcentral-data
    mcp-guacamole-data
    mcp-ollama-data
    mcp-redis-queue-data
    mcp-keycloak-data
    mcp-ntfy-cache
)

mkdir -p "${BACKUP_PATH}/volumes"

for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" &>/dev/null; then
        echo "  Sichere Volume: ${vol}..."
        docker run --rm \
            -v "${vol}:/source:ro" \
            -v "${BACKUP_PATH}/volumes:/backup" \
            alpine tar czf "/backup/${vol}.tar.gz" -C /source . 2>/dev/null
        echo "  OK: ${vol}.tar.gz ($(du -sh "${BACKUP_PATH}/volumes/${vol}.tar.gz" | cut -f1))"
    else
        echo "  UEBERSPRINGE: ${vol} (existiert nicht)"
    fi
done

# ---------------------------------------------------------------------------
# 4. Komprimieren
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Komprimiere Backup..."
cd "${BACKUP_DIR}"
if ! tar czf "mcp-backup-${TIMESTAMP}.tar.gz" "mcp-backup-${TIMESTAMP}/"; then
    echo "FEHLER: tar-Komprimierung fehlgeschlagen"
    exit 1
fi
if [ ! -f "mcp-backup-${TIMESTAMP}.tar.gz" ]; then
    echo "FEHLER: Backup-Archiv wurde nicht erstellt"
    exit 1
fi
rm -rf "${BACKUP_PATH}"

FINAL_SIZE=$(du -sh "${BACKUP_DIR}/mcp-backup-${TIMESTAMP}.tar.gz" | cut -f1)

echo ""
echo "============================================"
echo "  MCP v7 — Backup ABGESCHLOSSEN"
echo "  Datei: ${BACKUP_DIR}/mcp-backup-${TIMESTAMP}.tar.gz"
echo "  Groesse: ${FINAL_SIZE}"
echo "============================================"
