"""
MCP v7 — AI Gateway
Central API for all AI operations in the Managed Control Platform.

Endpoints:
    POST /api/v1/analyze   — Receive alert, run AI analysis
    POST /api/v1/embed     — Create embedding for RAG
    GET  /api/v1/search    — Search RAG knowledge base
    GET  /health           — Health check
    GET  /metrics          — Basic metrics
"""

import json
import logging
import os
import time
from datetime import datetime
from typing import Optional

import httpx
import redis
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("mcp-ai-gateway")

app = FastAPI(title="MCP AI Gateway", version="0.1.0")

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
AI_GATEWAY_SECRET = os.getenv("AI_GATEWAY_SECRET", "")
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
LITELLM_HOST = os.getenv("LITELLM_HOST", "http://litellm:4000")
REDIS_QUEUE_HOST = os.getenv("REDIS_QUEUE_HOST", "redis-queue")
REDIS_QUEUE_PORT = int(os.getenv("REDIS_QUEUE_PORT", "6379"))
ZAMMAD_URL = os.getenv("ZAMMAD_URL", "http://zammad-rails:3000")
ZAMMAD_TOKEN = os.getenv("ZAMMAD_TOKEN", "")
NTFY_URL = os.getenv("NTFY_URL", "http://ntfy:80")
PRIMARY_MODEL = os.getenv("PRIMARY_MODEL", "mistral:7b-instruct-v0.3-q4_K_M")

# Metrics counters
_metrics = {
    "requests_total": 0,
    "analyses_completed": 0,
    "analyses_failed": 0,
    "tickets_created": 0,
    "start_time": time.time(),
}

# Redis connection (lazy init)
_redis_client: Optional[redis.Redis] = None


def get_redis() -> redis.Redis:
    """Get or create Redis connection."""
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(
            host=REDIS_QUEUE_HOST, port=REDIS_QUEUE_PORT, decode_responses=True
        )
    return _redis_client


# ---------------------------------------------------------------------------
# Request/Response models
# ---------------------------------------------------------------------------
class AnalyzeRequest(BaseModel):
    source: str
    severity: str = "warning"
    host: str = "unknown"
    description: str
    metrics: dict = {}
    logs: str = ""
    crowdsec_alerts: str = ""


class AnalyzeResponse(BaseModel):
    status: str
    job_id: str
    message: str


class EmbedRequest(BaseModel):
    text: str
    metadata: dict = {}


class SearchRequest(BaseModel):
    query: str
    top_k: int = 5


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------
def verify_token(authorization: Optional[str]) -> None:
    """Verify Bearer token matches AI_GATEWAY_SECRET."""
    if not AI_GATEWAY_SECRET:
        return  # No secret configured — skip auth (dev mode)
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.removeprefix("Bearer ").strip()
    if token != AI_GATEWAY_SECRET:
        raise HTTPException(status_code=403, detail="Invalid token")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    """Health check endpoint."""
    redis_ok = False
    try:
        r = get_redis()
        redis_ok = r.ping()
    except Exception as e:
        logger.warning(f"Health check: Redis unreachable: {e}")

    ollama_ok = False
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{OLLAMA_HOST}/")
            ollama_ok = resp.status_code == 200
    except Exception as e:
        logger.warning(f"Health check: Ollama unreachable: {e}")

    status = "healthy" if (redis_ok and ollama_ok) else "degraded"
    return {
        "status": status,
        "redis": "ok" if redis_ok else "error",
        "ollama": "ok" if ollama_ok else "error",
        "uptime_seconds": int(time.time() - _metrics["start_time"]),
    }


@app.get("/metrics")
async def metrics():
    """Basic metrics endpoint."""
    return {
        **_metrics,
        "uptime_seconds": int(time.time() - _metrics["start_time"]),
    }


@app.post("/api/v1/analyze", response_model=AnalyzeResponse)
async def analyze(
    request: AnalyzeRequest,
    authorization: Optional[str] = Header(None),
):
    """
    Receive an alert and queue it for AI analysis.

    Flow: Dedup check → Queue job → Worker picks up →
          RAG search → LLM analysis → Ticket creation → Notification
    """
    verify_token(authorization)
    _metrics["requests_total"] += 1

    r = get_redis()

    # Deduplication: check if same alert was processed in last 15 minutes
    dedup_key = f"mcp:dedup:{request.source}:{request.host}:{request.description[:50]}"
    if r.exists(dedup_key):
        return AnalyzeResponse(
            status="deduplicated",
            job_id="",
            message="Duplicate alert — already processed in the last 15 minutes",
        )

    # Set dedup key with 15-minute TTL
    r.setex(dedup_key, 900, "1")

    # Create job
    job_id = f"job_{int(time.time())}_{request.source}"
    job_data = {
        "id": job_id,
        "created_at": datetime.utcnow().isoformat(),
        "status": "pending",
        "source": request.source,
        "severity": request.severity,
        "host": request.host,
        "description": request.description,
        "metrics": json.dumps(request.metrics),
        "logs": request.logs,
        "crowdsec_alerts": request.crowdsec_alerts,
    }

    # Push to Redis queue
    r.hset(f"mcp:job:{job_id}", mapping=job_data)
    r.lpush("mcp:queue:analyze", job_id)

    return AnalyzeResponse(
        status="queued",
        job_id=job_id,
        message=f"Alert queued for AI analysis (job: {job_id})",
    )


@app.post("/api/v1/embed")
async def embed(
    request: EmbedRequest,
    authorization: Optional[str] = Header(None),
):
    """Create an embedding vector for RAG storage."""
    verify_token(authorization)

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{OLLAMA_HOST}/api/embeddings",
                json={"model": "nomic-embed-text", "prompt": request.text},
            )
            resp.raise_for_status()
            data = resp.json()
            return {
                "status": "ok",
                "embedding": data.get("embedding", []),
                "dimensions": len(data.get("embedding", [])),
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding failed: {str(e)}")


@app.get("/api/v1/search")
async def search(
    query: str,
    top_k: int = 5,
    authorization: Optional[str] = Header(None),
):
    """Search the RAG knowledge base using vector similarity."""
    verify_token(authorization)

    # For now, return placeholder — full pgvector search implemented in Phase 9
    return {
        "status": "ok",
        "query": query,
        "results": [],
        "message": "RAG search — pgvector integration pending",
    }
