#!/bin/bash
# ============================================================================
# MCP v7 — Pull All Docker Images
# ============================================================================
# Extrahiert alle Images aus den Docker-Compose-Dateien und pullt sie.
# Lokal gebaute Images werden uebersprungen.
# ============================================================================

set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "$0")/../compose" && pwd)"

echo "============================================"
echo "  MCP v7 — Image Pull gestartet"
echo "============================================"
echo ""

# Alle image:-Zeilen aus den Compose-Dateien extrahieren
IMAGES=()
for compose_file in "${COMPOSE_DIR}"/*/docker-compose.yml; do
    while IFS= read -r line; do
        # Image-Name extrahieren (nach "image: ")
        image=$(echo "$line" | sed 's/.*image: *//' | sed 's/ *$//' | sed 's/"//g' | sed "s/'//g")

        # Variable-Substitution entfernen (${VAR:-default} → default)
        image=$(echo "$image" | sed 's/\${[^:}]*:-\([^}]*\)}/\1/g' | sed 's/\${[^}]*}//g')

        # Lokal gebaute Images ueberspringen
        if [[ "$image" == mcp-* ]] || [[ -z "$image" ]]; then
            continue
        fi

        IMAGES+=("$image")
    done < <(grep '^\s*image:' "$compose_file" 2>/dev/null)
done

# Duplikate entfernen
UNIQUE_IMAGES=($(printf '%s\n' "${IMAGES[@]}" | sort -u))

echo "Gefundene Images: ${#UNIQUE_IMAGES[@]}"
echo ""

# Images pullen
SUCCESS=0
FAILED=0

for image in "${UNIQUE_IMAGES[@]}"; do
    echo "Pulling: ${image}..."
    if docker pull "$image" 2>/dev/null; then
        echo "  OK: ${image}"
        ((SUCCESS++))
    else
        echo "  FEHLER: ${image}"
        ((FAILED++))
    fi
    echo ""
done

echo "============================================"
echo "  MCP v7 — Image Pull ABGESCHLOSSEN"
echo "  Erfolgreich: ${SUCCESS}"
echo "  Fehlgeschlagen: ${FAILED}"
echo "  Gesamt: ${#UNIQUE_IMAGES[@]}"
echo "============================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
