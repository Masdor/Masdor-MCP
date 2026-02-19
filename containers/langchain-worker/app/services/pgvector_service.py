"""MCP v7 — pgvector RAG-Service (synchron, fuer den Worker)."""

import json
import logging

import psycopg2
from pgvector.psycopg2 import register_vector

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class PgvectorService:
    """Synchroner pgvector-Client fuer RAG-Suche und Embedding-Speicherung."""

    def __init__(self):
        self._conn = None

    def connect(self):
        """Verbindung zu pgvector herstellen und vector-Extension registrieren."""
        try:
            self._conn = psycopg2.connect(settings.pgvector_dsn)
            self._conn.autocommit = True
            register_vector(self._conn)
            logger.info("pgvector-Verbindung hergestellt")
        except Exception as e:
            logger.error("pgvector-Verbindung fehlgeschlagen: %s", e)
            self._conn = None

    def close(self):
        if self._conn:
            self._conn.close()
            self._conn = None

    def health_check(self) -> bool:
        if not self._conn:
            return False
        try:
            with self._conn.cursor() as cur:
                cur.execute("SELECT 1")
            return True
        except Exception:
            return False

    def search_similar(
        self,
        query_embedding: list[float],
        limit: int = 5,
    ) -> list[dict]:
        """Aehnliche Embeddings via Cosine-Distance suchen."""
        if not self._conn:
            return []

        try:
            embedding_str = "[" + ",".join(str(x) for x in query_embedding) + "]"
            with self._conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, content, metadata, source_type,
                           1 - (embedding <=> %s::vector) AS similarity
                    FROM embeddings
                    ORDER BY embedding <=> %s::vector
                    LIMIT %s
                    """,
                    (embedding_str, embedding_str, limit),
                )
                rows = cur.fetchall()
                return [
                    {
                        "id": row[0],
                        "content": row[1],
                        "metadata": row[2],
                        "source_type": row[3],
                        "similarity": float(row[4]),
                    }
                    for row in rows
                    if float(row[4]) >= settings.rag_similarity_threshold
                ]
        except Exception as e:
            logger.error("RAG-Suche fehlgeschlagen: %s", e)
            return []

    def store_embedding(
        self,
        content: str,
        embedding: list[float],
        source_type: str = "analysis",
        source_id: str | None = None,
        metadata: dict | None = None,
    ) -> int | None:
        """Embedding in pgvector speichern."""
        if not self._conn:
            return None

        try:
            embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
            with self._conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO embeddings (content, embedding, source_type, source_id, metadata)
                    VALUES (%s, %s::vector, %s, %s, %s::jsonb)
                    RETURNING id
                    """,
                    (
                        content,
                        embedding_str,
                        source_type,
                        source_id,
                        json.dumps(metadata or {}),
                    ),
                )
                row = cur.fetchone()
                return row[0] if row else None
        except Exception as e:
            logger.error("Embedding-Speicherung fehlgeschlagen: %s", e)
            return None

    def log_analysis(
        self,
        event_source: str,
        event_data: dict,
        analysis_result: dict,
        confidence_score: float,
        ticket_id: str | None = None,
        model_used: str | None = None,
        processing_time_ms: int | None = None,
    ):
        """Analyse-Ergebnis im Audit-Log speichern."""
        if not self._conn:
            return

        try:
            with self._conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO analysis_log
                        (event_source, event_data, analysis_result, confidence_score,
                         ticket_id, model_used, processing_time_ms)
                    VALUES (%s, %s::jsonb, %s::jsonb, %s, %s, %s, %s)
                    """,
                    (
                        event_source,
                        json.dumps(event_data),
                        json.dumps(analysis_result),
                        confidence_score,
                        ticket_id,
                        model_used,
                        processing_time_ms,
                    ),
                )
        except Exception as e:
            logger.error("Analyse-Log fehlgeschlagen: %s", e)


pgvector_service = PgvectorService()
