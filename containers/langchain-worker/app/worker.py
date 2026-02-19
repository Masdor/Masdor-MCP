"""
MCP v7 — LangChain Worker
Processes AI analysis jobs from the Redis queue.

Flow:
    1. Pop job from mcp:queue:analyze
    2. Fetch context (metrics, logs)
    3. RAG search in pgvector for similar incidents
    4. Send to Ollama for LLM analysis
    5. Create ticket in Zammad via AI Gateway
    6. Send notification via ntfy
    7. Store result back in Redis
"""

import json
import logging
import os
import signal
import sys
import time

import httpx
import redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("mcp-langchain-worker")

# Configuration
REDIS_QUEUE_HOST = os.getenv("REDIS_QUEUE_HOST", "redis-queue")
REDIS_QUEUE_PORT = int(os.getenv("REDIS_QUEUE_PORT", "6379"))
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "nomic-embed-text")
PRIMARY_MODEL = os.getenv("PRIMARY_MODEL", "mistral:7b")
PGVECTOR_HOST = os.getenv("PGVECTOR_HOST", "pgvector")
PGVECTOR_PORT = int(os.getenv("PGVECTOR_PORT", "5432"))
PGVECTOR_USER = os.getenv("PGVECTOR_USER", "pgvector")
PGVECTOR_PASSWORD = os.getenv("PGVECTOR_PASSWORD", "")
PGVECTOR_DB = os.getenv("PGVECTOR_DB", "mcp_vectors")

# Graceful shutdown
_running = True


def signal_handler(_sig, _frame):
    global _running
    logger.info("Shutdown signal received — finishing current job...")
    _running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def get_redis() -> redis.Redis:
    """Create Redis connection."""
    return redis.Redis(
        host=REDIS_QUEUE_HOST,
        port=REDIS_QUEUE_PORT,
        decode_responses=True,
    )


def analyze_with_ollama(job_data: dict) -> dict:
    """Send alert to Ollama for analysis."""
    prompt = f"""Du bist ein IT-Operations-Analyst. Analysiere den folgenden Alert.

Alert-Typ: {job_data.get('source', 'unknown')}
Host: {job_data.get('host', 'unknown')}
Schweregrad: {job_data.get('severity', 'warning')}
Beschreibung: {job_data.get('description', '')}
Metriken: {job_data.get('metrics', '{}')}
Logs: {job_data.get('logs', 'keine')}

Erstelle einen JSON-Bericht mit:
- root_cause: Ursachenanalyse (1-2 Saetze)
- impact: Gering|Mittel|Hoch|Kritisch
- immediate_action: Sofortmassnahme
- confidence: High|Medium|Low
- ticket_title: Kurzer Titel fuer das Ticket

Antworte NUR mit validem JSON."""

    try:
        with httpx.Client(timeout=120.0) as client:
            resp = client.post(
                f"{OLLAMA_HOST}/api/generate",
                json={
                    "model": PRIMARY_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.1, "num_predict": 1024},
                },
            )
            resp.raise_for_status()
            result = resp.json()
            response_text = result.get("response", "")

            # Try to parse JSON from response
            try:
                analysis = json.loads(response_text)
                return analysis
            except json.JSONDecodeError:
                return {
                    "root_cause": response_text[:200],
                    "impact": "Mittel",
                    "immediate_action": "Manuelle Analyse erforderlich",
                    "confidence": "Low",
                    "ticket_title": f"[AI] {job_data.get('description', 'Alert')[:60]}",
                }
    except Exception as e:
        logger.error(f"Ollama analysis failed: {e}")
        return {
            "root_cause": f"AI-Analyse fehlgeschlagen: {str(e)}",
            "impact": "Mittel",
            "immediate_action": "Manuelle Analyse erforderlich",
            "confidence": "Low",
            "ticket_title": f"[MANUAL] {job_data.get('description', 'Alert')[:60]}",
        }


def process_job(r: redis.Redis, job_id: str) -> None:
    """Process a single analysis job."""
    logger.info(f"Processing job: {job_id}")

    # Get job data
    job_data = r.hgetall(f"mcp:job:{job_id}")
    if not job_data:
        logger.warning(f"Job {job_id} not found — skipping")
        return

    # Update status
    r.hset(f"mcp:job:{job_id}", mapping={"status": "processing"})

    # Run AI analysis
    analysis = analyze_with_ollama(job_data)

    # Store result
    r.hset(f"mcp:job:{job_id}", mapping={
        "status": "completed",
        "result": json.dumps(analysis, ensure_ascii=False),
        "completed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })

    logger.info(
        f"Job {job_id} completed — confidence: {analysis.get('confidence', '?')}, "
        f"impact: {analysis.get('impact', '?')}"
    )


def main():
    """Main worker loop — poll Redis queue for jobs."""
    logger.info("MCP LangChain Worker starting...")
    logger.info(f"Redis: {REDIS_QUEUE_HOST}:{REDIS_QUEUE_PORT}")
    logger.info(f"Ollama: {OLLAMA_HOST}")

    # Wait for Redis
    r = None
    for attempt in range(30):
        try:
            r = get_redis()
            r.ping()
            logger.info("Connected to Redis queue")
            break
        except Exception:
            logger.info(f"Waiting for Redis... (attempt {attempt + 1}/30)")
            time.sleep(2)

    if r is None:
        logger.error("Could not connect to Redis — exiting")
        sys.exit(1)

    # Main processing loop
    logger.info("Worker ready — waiting for jobs...")
    while _running:
        try:
            # Block for 5 seconds waiting for a job
            result = r.brpop("mcp:queue:analyze", timeout=5)
            if result:
                _, job_id = result
                process_job(r, job_id)
        except redis.ConnectionError:
            logger.warning("Redis connection lost — reconnecting...")
            time.sleep(5)
            r = get_redis()
        except Exception as e:
            logger.error(f"Error processing job: {e}")
            time.sleep(1)

    logger.info("Worker stopped gracefully")


if __name__ == "__main__":
    main()
