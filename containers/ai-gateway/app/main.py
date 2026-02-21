"""
MCP v7 — AI Gateway
Zentrale API fuer alle AI-Operationen in der Managed Control Platform.

Endpoints:
    POST /api/v1/analyze          — Alert empfangen, AI-Analyse starten
    POST /api/v1/embed            — Embedding erstellen und in pgvector speichern
    GET  /api/v1/search           — RAG-Wissensbasis durchsuchen
    POST /api/v1/ingest           — Dokument fuer RAG aufnehmen (Chunking + Embedding)
    GET  /api/v1/jobs             — Alle Jobs auflisten
    GET  /api/v1/jobs/{job_id}    — Job-Status abfragen
    GET  /api/v1/models           — Verfuegbare Modelle anzeigen
    DELETE /api/v1/knowledge/{id} — RAG-Eintrag loeschen
    GET  /health                  — Health-Check aller Abhaengigkeiten
    GET  /metrics                 — Prometheus-Metriken
"""

import json
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Optional

import httpx
import redis
from fastapi import FastAPI, Header, HTTPException
from prometheus_client import Counter, Gauge, Histogram, generate_latest
from starlette.responses import Response

from app.config import settings
from app.models.schemas import (
    AnalyzeRequest,
    AnalyzeResponse,
    EmbedRequest,
    EmbedResponse,
    HealthResponse,
    IngestRequest,
    IngestResponse,
    JobListResponse,
    JobStatus,
    ModelInfo,
    SearchResponse,
    SearchResult,
)
from app.services.ollama_client import ollama_client
from app.services.rag_service import rag_service

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("mcp-ai-gateway")

# ---------------------------------------------------------------------------
# Prometheus-Metriken
# ---------------------------------------------------------------------------
REQUESTS_TOTAL = Counter("mcp_requests_total", "Gesamtzahl API-Anfragen", ["endpoint"])
ANALYSES_COMPLETED = Counter("mcp_analyses_completed_total", "Abgeschlossene Analysen")
TICKETS_CREATED = Counter("mcp_tickets_created_total", "Erstellte Zammad-Tickets")
RAG_SEARCHES = Counter("mcp_rag_searches_total", "RAG-Suchvorgaenge")
EMBEDDINGS_STORED = Counter("mcp_embeddings_stored_total", "Gespeicherte Embeddings")
ANALYSIS_DURATION = Histogram(
    "mcp_analysis_duration_seconds", "Analyse-Dauer in Sekunden",
    buckets=[0.5, 1, 2, 5, 10, 30, 60, 120],
)
QUEUE_LENGTH = Gauge("mcp_queue_length", "Aktuelle Queue-Laenge")

_start_time = time.time()

# Redis Connection Pool (statt einzelner Verbindung)
_redis_pool: redis.ConnectionPool | None = None


def get_redis() -> redis.Redis:
    """Redis-Verbindung aus Connection-Pool herstellen."""
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = redis.ConnectionPool(
            host=settings.redis_queue_host,
            port=settings.redis_queue_port,
            password=settings.redis_queue_password or None,
            decode_responses=True,
            max_connections=settings.redis_pool_max,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True,
        )
    return redis.Redis(connection_pool=_redis_pool)


# Wiederverwendbarer HTTP-Client fuer Health-Checks
_http_client: httpx.AsyncClient | None = None


async def get_http_client() -> httpx.AsyncClient:
    """Wiederverwendbaren HTTP-Client fuer Health-Checks bereitstellen."""
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(timeout=5.0)
    return _http_client


# ---------------------------------------------------------------------------
# App Lifecycle
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: pgvector Pool initialisieren. Shutdown: Verbindungen schliessen."""
    logger.info("MCP AI Gateway startet...")
    await rag_service.init_pool()
    yield
    logger.info("MCP AI Gateway faehrt herunter...")
    # Graceful Shutdown: Alle Verbindungen schliessen
    await ollama_client.close()
    await rag_service.close()
    if _http_client and not _http_client.is_closed:
        await _http_client.aclose()
    if _redis_pool:
        _redis_pool.disconnect()
    logger.info("Alle Verbindungen geschlossen")


app = FastAPI(
    title="MCP AI Gateway",
    description="Zentrale AI-API fuer MCP v7 IT Operations Center",
    version="2.0.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Auth Helper
# ---------------------------------------------------------------------------
def verify_token(authorization: Optional[str]) -> None:
    """Bearer-Token gegen AI_GATEWAY_SECRET pruefen."""
    if not settings.ai_gateway_secret:
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Fehlender oder ungueltiger Authorization-Header")
    token = authorization.removeprefix("Bearer ").strip()
    if token != settings.ai_gateway_secret:
        raise HTTPException(status_code=403, detail="Ungueltiger Token")


# ---------------------------------------------------------------------------
# Health Check
# ---------------------------------------------------------------------------
@app.get("/health", response_model=HealthResponse)
async def health():
    """Health-Check aller Abhaengigkeiten."""
    client = await get_http_client()

    # Redis
    redis_status = "error"
    try:
        r = get_redis()
        if r.ping():
            redis_status = "ok"
    except redis.ConnectionError as e:
        logger.warning("Health: Redis Verbindungsfehler: %s", e)
    except redis.TimeoutError as e:
        logger.warning("Health: Redis Timeout: %s", e)
    except Exception as e:
        logger.warning("Health: Redis nicht erreichbar: %s", e)

    # Ollama
    ollama_status = "ok" if await ollama_client.health_check() else "error"

    # LiteLLM
    litellm_status = "error"
    try:
        resp = await client.get(f"{settings.litellm_host}/health/liveliness")
        litellm_status = "ok" if resp.status_code == 200 else "error"
    except Exception as e:
        logger.warning("Health: LiteLLM nicht erreichbar: %s", e)

    # pgvector
    pgvector_status = "ok" if await rag_service.health_check() else "error"

    # Zammad
    zammad_status = "error"
    try:
        resp = await client.get(f"{settings.zammad_url}/")
        zammad_status = "ok" if resp.status_code in (200, 301, 302) else "error"
    except Exception as e:
        logger.warning("Health: Zammad nicht erreichbar: %s", e)

    # ntfy
    ntfy_status = "error"
    try:
        resp = await client.get(f"{settings.ntfy_url}/v1/health")
        ntfy_status = "ok" if resp.status_code == 200 else "error"
    except Exception as e:
        logger.warning("Health: ntfy nicht erreichbar: %s", e)

    statuses = [redis_status, ollama_status, pgvector_status]
    overall = "healthy" if all(s == "ok" for s in statuses) else "degraded"

    return HealthResponse(
        status=overall,
        redis=redis_status,
        ollama=ollama_status,
        litellm=litellm_status,
        pgvector=pgvector_status,
        zammad=zammad_status,
        ntfy=ntfy_status,
        uptime_seconds=int(time.time() - _start_time),
    )


# ---------------------------------------------------------------------------
# Prometheus Metrics
# ---------------------------------------------------------------------------
@app.get("/metrics")
async def metrics():
    """Prometheus-Metriken im OpenMetrics-Format."""
    try:
        r = get_redis()
        queue_len = r.llen("mcp:queue:analyze")
        QUEUE_LENGTH.set(queue_len)
    except Exception:
        pass

    return Response(
        content=generate_latest(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )


# ---------------------------------------------------------------------------
# POST /api/v1/analyze — Alert zur Analyse queuen
# ---------------------------------------------------------------------------
@app.post("/api/v1/analyze", response_model=AnalyzeResponse)
async def analyze(
    request: AnalyzeRequest,
    authorization: Optional[str] = Header(None),
):
    """Alert empfangen und zur AI-Analyse in die Queue schieben."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="analyze").inc()

    r = get_redis()

    # Deduplizierung (TTL aus Settings)
    dedup_key = f"mcp:dedup:{request.source}:{request.host}:{request.description[:50]}"
    if r.exists(dedup_key):
        return AnalyzeResponse(
            status="deduplicated",
            job_id="",
            message="Duplikat — bereits in den letzten 15 Minuten verarbeitet",
        )

    r.setex(dedup_key, settings.dedup_ttl_seconds, "1")

    # Job erstellen (UUID statt Timestamp fuer Eindeutigkeit)
    job_id = f"job_{uuid.uuid4().hex[:12]}_{request.source}"
    job_data = {
        "id": job_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "pending",
        "source": request.source,
        "severity": request.severity,
        "host": request.host,
        "description": request.description,
        "metrics": json.dumps(request.metrics),
        "logs": request.logs,
        "crowdsec_alerts": request.crowdsec_alerts,
    }

    r.hset(f"mcp:job:{job_id}", mapping=job_data)
    r.lpush("mcp:queue:analyze", job_id)

    # TTL als Sicherheitsnetz: falls Worker den Job nie abholt
    r.expire(f"mcp:job:{job_id}", 86400)  # 24h fuer unbearbeitete Jobs

    return AnalyzeResponse(
        status="queued",
        job_id=job_id,
        message=f"Alert zur AI-Analyse eingereiht (Job: {job_id})",
    )


# ---------------------------------------------------------------------------
# POST /api/v1/embed — Embedding erstellen und speichern
# ---------------------------------------------------------------------------
@app.post("/api/v1/embed", response_model=EmbedResponse)
async def embed(
    request: EmbedRequest,
    authorization: Optional[str] = Header(None),
):
    """Embedding erstellen und in pgvector speichern."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="embed").inc()

    try:
        embedding = await ollama_client.embed(request.text)
        if not embedding:
            raise HTTPException(status_code=503, detail="Embedding-Service nicht verfuegbar")

        # Embedding-Dimension validieren
        if settings.expected_embedding_dimensions and len(embedding) != settings.expected_embedding_dimensions:
            logger.warning(
                "Unerwartete Embedding-Dimension: %d (erwartet: %d)",
                len(embedding), settings.expected_embedding_dimensions,
            )

        embedding_id = await rag_service.store_embedding(
            content=request.text,
            embedding=embedding,
            source_type=request.source_type,
            source_id=request.source_id,
            metadata=request.metadata,
        )

        stored = embedding_id is not None
        if stored:
            EMBEDDINGS_STORED.inc()

        return EmbedResponse(
            status="ok",
            embedding_id=embedding_id,
            dimensions=len(embedding),
            stored=stored,
            model_used=settings.embedding_model,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Embedding fehlgeschlagen: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Embedding fehlgeschlagen: {str(e)}")


# ---------------------------------------------------------------------------
# GET /api/v1/search — RAG-Wissensbasis durchsuchen
# ---------------------------------------------------------------------------
@app.get("/api/v1/search", response_model=SearchResponse)
async def search(
    query: str,
    top_k: int = 5,
    authorization: Optional[str] = Header(None),
):
    """RAG-Wissensbasis via Vektor-Aehnlichkeit durchsuchen."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="search").inc()
    RAG_SEARCHES.inc()

    # Input-Validierung
    top_k = max(1, min(top_k, settings.max_search_top_k))

    if not query or len(query.strip()) == 0:
        raise HTTPException(status_code=422, detail="Query darf nicht leer sein")

    try:
        query_embedding = await ollama_client.embed(query)
        if not query_embedding:
            raise HTTPException(status_code=503, detail="Embedding-Service nicht verfuegbar")

        results = await rag_service.search_similar(query_embedding, limit=top_k)

        return SearchResponse(
            status="ok",
            query=query,
            results=[
                SearchResult(
                    id=r["id"],
                    content=r["content"],
                    similarity=r["similarity"],
                    source_type=r.get("source_type", ""),
                    metadata=r.get("metadata", {}),
                )
                for r in results
            ],
            total=len(results),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Suche fehlgeschlagen: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Suche fehlgeschlagen: {str(e)}")


# ---------------------------------------------------------------------------
# POST /api/v1/ingest — Dokument chunken und einbetten
# ---------------------------------------------------------------------------
@app.post("/api/v1/ingest", response_model=IngestResponse)
async def ingest(
    request: IngestRequest,
    authorization: Optional[str] = Header(None),
):
    """Dokument in Chunks aufteilen, Embeddings erstellen und in pgvector speichern."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="ingest").inc()

    chunks = _chunk_text(request.text, request.chunk_size, request.chunk_overlap)

    stored_count = 0
    for i, chunk in enumerate(chunks):
        try:
            embedding = await ollama_client.embed(chunk)
            if embedding:
                chunk_metadata = {
                    **request.metadata,
                    "chunk_index": i,
                    "total_chunks": len(chunks),
                }
                result = await rag_service.store_embedding(
                    content=chunk,
                    embedding=embedding,
                    source_type=request.source_type,
                    source_id=f"{request.source_id or 'doc'}_{i}",
                    metadata=chunk_metadata,
                )
                if result:
                    stored_count += 1
                    EMBEDDINGS_STORED.inc()
        except Exception as e:
            logger.warning("Chunk %d/%d fehlgeschlagen: %s", i + 1, len(chunks), e)

    return IngestResponse(
        status="ok" if stored_count > 0 else "partial",
        chunks_created=stored_count,
        source_type=request.source_type,
        source_id=request.source_id,
    )


def _chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Text in ueberlappende Chunks aufteilen (an Satz-/Wort-Grenzen)."""
    if len(text) <= chunk_size:
        return [text]

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size

        # Chunk-Ende an Satz- oder Wort-Grenze ausrichten
        if end < len(text):
            # Suche rueckwaerts nach Satz-Ende (.!?\n) im letzten 20% des Chunks
            search_start = max(start, end - chunk_size // 5)
            best_break = -1
            for i in range(end, search_start, -1):
                if text[i - 1] in ".!?\n":
                    best_break = i
                    break
            # Fallback: Wort-Grenze (Leerzeichen)
            if best_break == -1:
                for i in range(end, search_start, -1):
                    if text[i - 1] == " ":
                        best_break = i
                        break
            if best_break > start:
                end = best_break

        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - overlap if end - overlap > start else end
    return chunks


# ---------------------------------------------------------------------------
# GET /api/v1/jobs — Jobs auflisten
# ---------------------------------------------------------------------------
@app.get("/api/v1/jobs", response_model=JobListResponse)
async def list_jobs(
    offset: int = 0,
    limit: int = 20,
    authorization: Optional[str] = Header(None),
):
    """Alle Analyse-Jobs auflisten."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="jobs").inc()

    # Input-Validierung
    offset = max(0, offset)
    limit = max(1, min(limit, 100))

    r = get_redis()
    jobs = []

    cursor = 0
    all_keys = []
    while True:
        cursor, keys = r.scan(cursor=cursor, match="mcp:job:*", count=100)
        all_keys.extend(keys)
        if cursor == 0:
            break

    all_keys.sort(reverse=True)
    total = len(all_keys)
    page_keys = all_keys[offset:offset + limit]

    for key in page_keys:
        try:
            data = r.hgetall(key)
            if data:
                result = None
                if data.get("result"):
                    try:
                        result = json.loads(data["result"])
                    except json.JSONDecodeError:
                        pass

                jobs.append(JobStatus(
                    id=data.get("id", key.split(":")[-1]),
                    status=data.get("status", "unknown"),
                    source=data.get("source", ""),
                    severity=data.get("severity", ""),
                    host=data.get("host", ""),
                    description=data.get("description", "")[:200],
                    created_at=data.get("created_at", ""),
                    completed_at=data.get("completed_at", ""),
                    result=result,
                    model_used=data.get("model_used", ""),
                    processing_time_ms=int(data.get("processing_time_ms", 0)),
                    ticket_id=data.get("ticket_id", ""),
                ))
        except Exception as e:
            logger.warning("Job-Daten fuer %s fehlerhaft: %s", key, e)

    return JobListResponse(jobs=jobs, total=total, offset=offset, limit=limit)


# ---------------------------------------------------------------------------
# GET /api/v1/jobs/{job_id} — Job-Status abfragen
# ---------------------------------------------------------------------------
@app.get("/api/v1/jobs/{job_id}", response_model=JobStatus)
async def get_job(
    job_id: str,
    authorization: Optional[str] = Header(None),
):
    """Status und Ergebnis eines bestimmten Jobs abfragen."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="job_detail").inc()

    r = get_redis()
    data = r.hgetall(f"mcp:job:{job_id}")

    if not data:
        raise HTTPException(status_code=404, detail=f"Job {job_id} nicht gefunden")

    result = None
    if data.get("result"):
        try:
            result = json.loads(data["result"])
        except json.JSONDecodeError:
            pass

    return JobStatus(
        id=data.get("id", job_id),
        status=data.get("status", "unknown"),
        source=data.get("source", ""),
        severity=data.get("severity", ""),
        host=data.get("host", ""),
        description=data.get("description", ""),
        created_at=data.get("created_at", ""),
        completed_at=data.get("completed_at", ""),
        result=result,
        model_used=data.get("model_used", ""),
        processing_time_ms=int(data.get("processing_time_ms", 0)),
        ticket_id=data.get("ticket_id", ""),
    )


# ---------------------------------------------------------------------------
# GET /api/v1/models — Verfuegbare Modelle anzeigen
# ---------------------------------------------------------------------------
@app.get("/api/v1/models", response_model=list[ModelInfo])
async def list_models(
    authorization: Optional[str] = Header(None),
):
    """Verfuegbare LLM-Modelle auflisten (via Ollama)."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="models").inc()

    models = await ollama_client.list_models()
    return [
        ModelInfo(
            name=m.get("name", "unknown"),
            size=str(m.get("size", "")),
            modified_at=m.get("modified_at"),
        )
        for m in models
    ]


# ---------------------------------------------------------------------------
# DELETE /api/v1/knowledge/{id} — RAG-Eintrag loeschen
# ---------------------------------------------------------------------------
@app.delete("/api/v1/knowledge/{embedding_id}")
async def delete_knowledge(
    embedding_id: int,
    authorization: Optional[str] = Header(None),
):
    """RAG-Eintrag aus der Wissensbasis loeschen."""
    verify_token(authorization)
    REQUESTS_TOTAL.labels(endpoint="knowledge_delete").inc()

    success = await rag_service.delete_embedding(embedding_id)
    if not success:
        raise HTTPException(status_code=404, detail=f"Eintrag {embedding_id} nicht gefunden")

    return {"status": "ok", "deleted_id": embedding_id}
