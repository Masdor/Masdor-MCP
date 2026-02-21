#!/bin/bash
# ============================================================================
# MCP v7 — pgvector Database Initialization
# ============================================================================
# Dieses Script laeuft im mcp-pgvector Container als Entrypoint-Init-Script.
# Es erstellt die vector-Extension und alle Tabellen fuer die RAG-Pipeline.
#
# Mount-Pfad: /docker-entrypoint-initdb.d/init-pgvector.sh
# Laeuft automatisch beim ersten Start wenn das Data-Dir leer ist.
# ============================================================================

set -euo pipefail

echo "============================================"
echo "  MCP v7 — pgvector Initialization"
echo "============================================"

# ---------------------------------------------------------------------------
# 1. pgvector Extension aktivieren
# ---------------------------------------------------------------------------
echo "[1/4] Aktiviere pgvector Extension..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL

# ---------------------------------------------------------------------------
# 2. Embeddings-Tabelle fuer RAG-Wissensbasis
# ---------------------------------------------------------------------------
echo "[2/4] Erstelle embeddings Tabelle..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE TABLE IF NOT EXISTS embeddings (
        id              SERIAL PRIMARY KEY,
        content         TEXT NOT NULL,
        content_hash    VARCHAR(64),
        embedding       vector(768),
        source_type     VARCHAR(50) DEFAULT 'manual',
        source_id       VARCHAR(255),
        metadata        JSONB DEFAULT '{}',
        tenant_id       UUID DEFAULT '00000000-0000-0000-0000-000000000000',
        created_at      TIMESTAMPTZ DEFAULT NOW()
    );

    -- HNSW-Index fuer schnelle Vektor-Aehnlichkeitssuche (Cosine Distance)
    CREATE INDEX IF NOT EXISTS idx_embeddings_vector
        ON embeddings USING hnsw (embedding vector_cosine_ops);

    -- Index fuer Quell-Filterung
    CREATE INDEX IF NOT EXISTS idx_embeddings_source
        ON embeddings (source_type, source_id);

    -- Unique-Index fuer Content-Deduplizierung (gleicher Inhalt + Quelltyp)
    CREATE UNIQUE INDEX IF NOT EXISTS idx_embeddings_content_hash
        ON embeddings (content_hash, source_type) WHERE content_hash IS NOT NULL;

    -- Index fuer Tenant-Isolation
    CREATE INDEX IF NOT EXISTS idx_embeddings_tenant
        ON embeddings (tenant_id);
EOSQL

# ---------------------------------------------------------------------------
# 3. Analyse-Log-Tabelle fuer Audit-Trail
# ---------------------------------------------------------------------------
echo "[3/4] Erstelle analysis_log Tabelle..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE TABLE IF NOT EXISTS analysis_log (
        id                  SERIAL PRIMARY KEY,
        event_source        VARCHAR(100),
        event_data          JSONB,
        analysis_result     JSONB,
        confidence_score    FLOAT,
        ticket_id           VARCHAR(100),
        model_used          VARCHAR(100),
        processing_time_ms  INTEGER,
        tenant_id           UUID DEFAULT '00000000-0000-0000-0000-000000000000',
        created_at          TIMESTAMPTZ DEFAULT NOW()
    );

    -- Index fuer zeitbasierte Abfragen
    CREATE INDEX IF NOT EXISTS idx_analysis_log_created
        ON analysis_log (created_at DESC);

    -- Index fuer Quell-Filterung
    CREATE INDEX IF NOT EXISTS idx_analysis_log_source
        ON analysis_log (event_source);
EOSQL

# ---------------------------------------------------------------------------
# 4. Zusammenfassung
# ---------------------------------------------------------------------------
echo "[4/4] Verifiziere Installation..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
    SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    SELECT indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY indexname;
EOSQL

echo "============================================"
echo "  MCP v7 — pgvector Initialization COMPLETE"
echo "============================================"
