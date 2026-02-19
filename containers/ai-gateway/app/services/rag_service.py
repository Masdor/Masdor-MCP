"""MCP v7 — RAG-Service mit pgvector fuer Aehnlichkeitssuche (async)."""

import json
import logging

import asyncpg

from app.config import settings

logger = logging.getLogger("mcp-ai-gateway")


class RAGService:
    """Asynchroner pgvector-Client fuer RAG-Operationen."""

    def __init__(self):
        self.pool: asyncpg.Pool | None = None

    async def init_pool(self):
        """Connection-Pool initialisieren."""
        try:
            self.pool = await asyncpg.create_pool(
                settings.pgvector_dsn,
                min_size=2,
                max_size=10,
            )
            logger.info("pgvector Connection-Pool initialisiert")
        except Exception as e:
            logger.error("pgvector Pool-Initialisierung fehlgeschlagen: %s", e)

    async def close(self):
        if self.pool:
            await self.pool.close()

    async def health_check(self) -> bool:
        if not self.pool:
            return False
        try:
            async with self.pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
            return True
        except Exception:
            return False

    async def search_similar(
        self,
        query_embedding: list[float],
        limit: int = 5,
    ) -> list[dict]:
        """Aehnliche Embeddings via Cosine-Distance suchen."""
        if not self.pool:
            return []

        try:
            embedding_str = "[" + ",".join(str(x) for x in query_embedding) + "]"
            query = """
                SELECT id, content, metadata, source_type, source_id,
                       1 - (embedding <=> $1::vector) AS similarity
                FROM embeddings
                ORDER BY embedding <=> $1::vector
                LIMIT $2
            """
            async with self.pool.acquire() as conn:
                rows = await conn.fetch(query, embedding_str, limit)
                return [
                    {
                        "id": row["id"],
                        "content": row["content"],
                        "metadata": row["metadata"],
                        "source_type": row["source_type"],
                        "source_id": row["source_id"],
                        "similarity": float(row["similarity"]),
                    }
                    for row in rows
                ]
        except Exception as e:
            logger.error("RAG-Suche fehlgeschlagen: %s", e)
            return []

    async def store_embedding(
        self,
        content: str,
        embedding: list[float],
        source_type: str = "manual",
        source_id: str | None = None,
        metadata: dict | None = None,
    ) -> int | None:
        """Embedding in pgvector speichern."""
        if not self.pool:
            return None

        try:
            embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
            async with self.pool.acquire() as conn:
                row_id = await conn.fetchval(
                    """
                    INSERT INTO embeddings (content, embedding, source_type, source_id, metadata)
                    VALUES ($1, $2::vector, $3, $4, $5::jsonb)
                    RETURNING id
                    """,
                    content,
                    embedding_str,
                    source_type,
                    source_id,
                    json.dumps(metadata or {}),
                )
                return row_id
        except Exception as e:
            logger.error("Embedding-Speicherung fehlgeschlagen: %s", e)
            return None

    async def delete_embedding(self, embedding_id: int) -> bool:
        """Embedding aus pgvector loeschen."""
        if not self.pool:
            return False

        try:
            async with self.pool.acquire() as conn:
                result = await conn.execute(
                    "DELETE FROM embeddings WHERE id = $1", embedding_id
                )
                return result == "DELETE 1"
        except Exception as e:
            logger.error("Embedding-Loeschung fehlgeschlagen: %s", e)
            return False

    async def log_analysis(
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
        if not self.pool:
            return

        try:
            async with self.pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO analysis_log
                        (event_source, event_data, analysis_result, confidence_score,
                         ticket_id, model_used, processing_time_ms)
                    VALUES ($1, $2::jsonb, $3::jsonb, $4, $5, $6, $7)
                    """,
                    event_source,
                    json.dumps(event_data),
                    json.dumps(analysis_result),
                    confidence_score,
                    ticket_id,
                    model_used,
                    processing_time_ms,
                )
        except Exception as e:
            logger.error("Analyse-Log fehlgeschlagen: %s", e)


rag_service = RAGService()
