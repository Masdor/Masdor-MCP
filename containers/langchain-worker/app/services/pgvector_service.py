"""MCP v7 — pgvector RAG-Service (synchron, fuer den Worker) mit Connection-Pooling."""

import hashlib
import json
import logging

import psycopg2
import psycopg2.pool
from pgvector.psycopg2 import register_vector

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class PgvectorService:
    """Synchroner pgvector-Client mit Connection-Pool fuer RAG-Suche und Embedding-Speicherung."""

    def __init__(self):
        self._pool = None

    def connect(self):
        """Connection-Pool zu pgvector herstellen."""
        try:
            self._pool = psycopg2.pool.SimpleConnectionPool(
                minconn=1,
                maxconn=5,
                dsn=settings.pgvector_dsn,
            )
            logger.info("pgvector Connection-Pool hergestellt (min=1, max=5)")
        except Exception as e:
            logger.error("pgvector-Verbindung fehlgeschlagen: %s", e)
            self._pool = None

    def _get_conn(self):
        """Verbindung aus Pool holen und vector-Extension registrieren."""
        if not self._pool:
            return None
        try:
            conn = self._pool.getconn()
            conn.autocommit = True
            register_vector(conn)  # Muss fuer jede Connection aufgerufen werden
            return conn
        except Exception as e:
            logger.error("pgvector Pool-Verbindung fehlgeschlagen: %s", e)
            return None

    def _put_conn(self, conn):
        """Verbindung zurueck in Pool geben."""
        if self._pool and conn:
            try:
                self._pool.putconn(conn)
            except Exception:
                pass

    def close(self):
        if self._pool:
            self._pool.closeall()
            self._pool = None
            logger.info("pgvector Connection-Pool geschlossen")

    def health_check(self) -> bool:
        conn = self._get_conn()
        if not conn:
            return False
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
            return True
        except Exception:
            return False
        finally:
            self._put_conn(conn)

    def search_similar(
        self,
        query_embedding: list[float],
        limit: int = 5,
    ) -> list[dict]:
        """Aehnliche Embeddings via Cosine-Distance suchen."""
        conn = self._get_conn()
        if not conn:
            return []

        try:
            embedding_str = "[" + ",".join(str(x) for x in query_embedding) + "]"
            with conn.cursor() as cur:
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
            logger.error("RAG-Suche fehlgeschlagen: %s", e, exc_info=True)
            return []
        finally:
            self._put_conn(conn)

    def store_embedding(
        self,
        content: str,
        embedding: list[float],
        source_type: str = "analysis",
        source_id: str | None = None,
        metadata: dict | None = None,
    ) -> int | None:
        """Embedding in pgvector speichern (mit Content-Hash-Deduplizierung)."""
        conn = self._get_conn()
        if not conn:
            return None

        content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()

        try:
            embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO embeddings
                        (content, content_hash, embedding, source_type, source_id, metadata)
                    VALUES (%s, %s, %s::vector, %s, %s, %s::jsonb)
                    ON CONFLICT (content_hash, source_type)
                        WHERE content_hash IS NOT NULL
                    DO NOTHING
                    RETURNING id
                    """,
                    (
                        content,
                        content_hash,
                        embedding_str,
                        source_type,
                        source_id,
                        json.dumps(metadata or {}),
                    ),
                )
                row = cur.fetchone()
                if row is None:
                    logger.info("Embedding-Duplikat uebersprungen (Hash: %s...)", content_hash[:12])
                return row[0] if row else None
        except Exception as e:
            logger.error("Embedding-Speicherung fehlgeschlagen: %s", e, exc_info=True)
            return None
        finally:
            self._put_conn(conn)

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
        conn = self._get_conn()
        if not conn:
            return

        try:
            with conn.cursor() as cur:
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
        finally:
            self._put_conn(conn)


pgvector_service = PgvectorService()
