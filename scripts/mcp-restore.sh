#!/bin/bash
# ============================================================================
# MCP v7 — Restore Script
# ============================================================================
# Stellt ein MCP-Backup wieder her.
# Verwendung: ./scripts/mcp-restore.sh <backup-datei.tar.gz>
# ============================================================================

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Verwendung: $0 <backup-datei.tar.gz>"
    echo ""
    echo "Verfuegbare Backups:"
    ls -lh /tmp/mcp-backups/mcp-backup-*.tar.gz 2>/dev/null || echo "  Keine Backups gefunden in /tmp/mcp-backups/"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "FEHLER: Backup-Datei nicht gefunden: ${BACKUP_FILE}"
    exit 1
fi

echo "============================================"
echo "  MCP v7 — Restore gestartet"
echo "  Quelle: ${BACKUP_FILE}"
echo "============================================"
echo ""
echo "WARNUNG: Dies wird alle bestehenden Daten ueberschreiben!"
read -p "Fortfahren? (ja/nein): " confirm
if [ "$confirm" != "ja" ]; then
    echo "Restore abgebrochen."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Backup entpacken
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Entpacke Backup..."
TEMP_DIR=$(mktemp -d)
tar xzf "${BACKUP_FILE}" -C "${TEMP_DIR}"
BACKUP_DIR=$(ls -d "${TEMP_DIR}"/mcp-backup-* | head -1)
echo "  OK: ${BACKUP_DIR}"

# ---------------------------------------------------------------------------
# 2. Stacks stoppen
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Stoppe alle MCP-Stacks..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/mcp-stop.sh" ]; then
    bash "${SCRIPT_DIR}/mcp-stop.sh"
else
    echo "  WARNUNG: mcp-stop.sh nicht gefunden — Container manuell stoppen"
fi

# ---------------------------------------------------------------------------
# 3. PostgreSQL Restore
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Stelle PostgreSQL wieder her..."
if [ -f "${BACKUP_DIR}/postgres-all.sql" ]; then
    docker start mcp-postgres 2>/dev/null || true
    sleep 5
    docker exec -i mcp-postgres psql -U postgres < "${BACKUP_DIR}/postgres-all.sql" 2>/dev/null
    echo "  OK: PostgreSQL wiederhergestellt"
else
    echo "  UEBERSPRINGE: postgres-all.sql nicht im Backup"
fi

if [ -f "${BACKUP_DIR}/pgvector.sql" ]; then
    docker start mcp-pgvector 2>/dev/null || true
    sleep 5
    docker exec -i mcp-pgvector psql -U "${PGVECTOR_USER:-pgvector}" \
        "${PGVECTOR_DB:-mcp_vectors}" < "${BACKUP_DIR}/pgvector.sql" 2>/dev/null
    echo "  OK: pgvector wiederhergestellt"
else
    echo "  UEBERSPRINGE: pgvector.sql nicht im Backup"
fi

# ---------------------------------------------------------------------------
# 4. Volume Restore
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Stelle Docker Volumes wieder her..."
if [ -d "${BACKUP_DIR}/volumes" ]; then
    for archive in "${BACKUP_DIR}"/volumes/*.tar.gz; do
        vol_name=$(basename "$archive" .tar.gz)
        if docker volume inspect "$vol_name" &>/dev/null; then
            echo "  Stelle wieder her: ${vol_name}..."
            docker run --rm \
                -v "${vol_name}:/target" \
                -v "$(dirname "$archive"):/backup:ro" \
                alpine sh -c "rm -rf /target/* && tar xzf /backup/$(basename "$archive") -C /target"
            echo "  OK: ${vol_name}"
        else
            echo "  UEBERSPRINGE: ${vol_name} (Volume existiert nicht)"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 5. Stacks starten
# ---------------------------------------------------------------------------
echo ""
echo "[5/5] Starte alle MCP-Stacks..."
if [ -f "${SCRIPT_DIR}/mcp-start.sh" ]; then
    bash "${SCRIPT_DIR}/mcp-start.sh"
else
    echo "  WARNUNG: mcp-start.sh nicht gefunden — Container manuell starten"
fi

# Aufraeumen
rm -rf "${TEMP_DIR}"

echo ""
echo "============================================"
echo "  MCP v7 — Restore ABGESCHLOSSEN"
echo "  Bitte fuehre 'make test-smoke' aus"
echo "============================================"
