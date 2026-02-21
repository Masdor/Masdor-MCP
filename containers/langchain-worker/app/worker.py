"""
MCP v7 — LangChain Worker
Verarbeitet AI-Analyse-Jobs aus der Redis-Queue.

Vollstaendige Pipeline:
    1. Job aus mcp:queue:analyze poppen
    2. RAG-Suche in pgvector fuer aehnliche Incidents
    3. Professionellen Prompt laden und befuellen
    4. LLM-Analyse via LiteLLM (Fallback: Ollama)
    5. Zammad-Ticket erstellen (bei hoher Severity + Confidence)
    6. ntfy-Benachrichtigung senden
    7. Ergebnis in Redis speichern + Embedding fuer zukuenftige RAG
"""

import json
import logging
import signal
import sys
import time

import redis

from app.config import settings
from app.prompts import build_prompt
from app.services.llm_client import llm_client
from app.services.ntfy_client import ntfy_client
from app.services.pgvector_service import pgvector_service
from app.services.zammad_client import zammad_client

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("mcp-langchain-worker")

# Graceful Shutdown
_running = True


def signal_handler(_sig, _frame):
    global _running
    logger.info("Shutdown-Signal empfangen — beende aktuellen Job...")
    _running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def get_redis() -> redis.Redis:
    """Redis-Verbindung erstellen."""
    return redis.Redis(
        host=settings.redis_queue_host,
        port=settings.redis_queue_port,
        password=settings.redis_queue_password or None,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=10,
        retry_on_timeout=True,
    )


def parse_llm_response(response_text: str) -> dict:
    """JSON aus LLM-Antwort extrahieren (mit Fallback)."""
    text = response_text.strip()

    # JSON aus Markdown-Codeblock extrahieren
    if "```json" in text:
        text = text.split("```json")[1].split("```")[0].strip()
    elif "```" in text:
        text = text.split("```")[1].split("```")[0].strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {
            "root_cause": response_text[:300],
            "impact": "Mittel",
            "affected_services": [],
            "immediate_action": "Manuelle Analyse erforderlich",
            "long_term_solution": "",
            "confidence": "Low",
            "confidence_reason": "JSON-Parsing fehlgeschlagen",
            "ticket_title": "[AI] Manuelle Analyse erforderlich",
            "ticket_priority": "2_normal",
        }


# Prioritaet-Mapping (konfigurierbar)
PRIORITY_MAPPING = {
    "4_urgent": 1,
    "3_high": 2,
    "2_normal": 3,
    "1_low": 4,
}


def map_priority(priority_str: str) -> int:
    """Ticket-Priority-String auf Zammad priority_id mappen."""
    return PRIORITY_MAPPING.get(priority_str, 3)


def should_create_ticket(analysis: dict, severity: str) -> bool:
    """Entscheiden ob ein Ticket erstellt werden soll."""
    confidence = analysis.get("confidence", "Low")
    impact = analysis.get("impact", "Gering")

    high_confidence = confidence in ("High", "Medium")
    high_severity = severity in ("critical", "high") or impact in ("Hoch", "Kritisch")

    return high_confidence and high_severity


def process_job(r: redis.Redis, job_id: str) -> None:
    """Einen Analyse-Job vollstaendig verarbeiten."""
    start_time = time.monotonic()
    logger.info("Verarbeite Job: %s", job_id)

    # 1. Job-Daten aus Redis holen
    job_data = r.hgetall(f"mcp:job:{job_id}")
    if not job_data:
        logger.warning("Job %s nicht gefunden — ueberspringe", job_id)
        return

    # Status aktualisieren
    r.hset(f"mcp:job:{job_id}", mapping={"status": "processing"})

    # 2. RAG-Suche: aehnliche Incidents finden
    rag_results = []
    try:
        description = job_data.get("description", "")
        if description and pgvector_service.health_check():
            query_embedding = llm_client.embed(description)
            if query_embedding:
                rag_results = pgvector_service.search_similar(
                    query_embedding, limit=settings.rag_top_k
                )
                if rag_results:
                    logger.info(
                        "RAG: %d aehnliche Incidents gefunden (beste Aehnlichkeit: %.2f)",
                        len(rag_results),
                        rag_results[0]["similarity"],
                    )
    except Exception as e:
        logger.warning("RAG-Suche fehlgeschlagen, fahre ohne Kontext fort: %s", e)

    # 3. Professionellen Prompt laden und befuellen
    prompt = build_prompt(job_data, rag_results)

    # 4. LLM-Analyse (LiteLLM-First, Ollama-Fallback)
    try:
        llm_result = llm_client.generate(prompt)
        response_text = llm_result.get("response", "")
        model_used = llm_result.get("model", settings.primary_model)
        via = llm_result.get("via", "unknown")
        logger.info("LLM-Antwort erhalten via %s (%s)", via, model_used)
    except Exception as e:
        logger.error("LLM-Analyse fehlgeschlagen: %s", e, exc_info=True)
        r.hset(f"mcp:job:{job_id}", mapping={
            "status": "failed",
            "error": str(e)[:500],
            "completed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        })
        return

    # 5. JSON aus Antwort parsen
    analysis = parse_llm_response(response_text)

    elapsed_ms = int((time.monotonic() - start_time) * 1000)

    # 6. Zammad-Ticket erstellen (bei hoher Severity + Confidence)
    ticket_id = None
    severity = job_data.get("severity", "warning")
    if should_create_ticket(analysis, severity):
        ticket_title = analysis.get("ticket_title", f"[AI] {job_data.get('description', 'Alert')[:60]}")
        ticket_body = (
            f"<h2>{ticket_title}</h2>"
            f"<p><strong>Root Cause:</strong> {analysis.get('root_cause', 'N/A')}</p>"
            f"<p><strong>Impact:</strong> {analysis.get('impact', 'N/A')}</p>"
            f"<p><strong>Betroffene Services:</strong> {', '.join(analysis.get('affected_services', []))}</p>"
            f"<h3>Sofortmassnahme</h3><p>{analysis.get('immediate_action', 'N/A')}</p>"
            f"<h3>Langfristige Loesung</h3><p>{analysis.get('long_term_solution', 'N/A')}</p>"
            f"<hr><p><em>AI Confidence: {analysis.get('confidence', 'N/A')} — "
            f"Job: {job_id} — Modell: {model_used}</em></p>"
        )
        priority_id = map_priority(analysis.get("ticket_priority", "2_normal"))
        ticket = zammad_client.create_ticket(
            title=ticket_title,
            body=ticket_body,
            priority_id=priority_id,
            tags=f"ai-generated,{job_data.get('source', 'unknown')}",
        )
        if ticket:
            ticket_id = str(ticket.get("id"))

    # 7. ntfy-Benachrichtigung senden
    impact = analysis.get("impact", "Mittel")
    ntfy_title = analysis.get("ticket_title", f"MCP Alert: {job_data.get('host', 'unknown')}")
    ntfy_message = (
        f"Host: {job_data.get('host', 'unknown')}\n"
        f"Impact: {impact}\n"
        f"Ursache: {analysis.get('root_cause', 'N/A')}\n"
        f"Massnahme: {analysis.get('immediate_action', 'N/A')}"
    )
    if ticket_id:
        ntfy_message += f"\nTicket: #{ticket_id}"

    ntfy_client.send_notification(
        title=ntfy_title,
        message=ntfy_message[:settings.ntfy_max_message_length],
        severity=impact,
        tags=["warning", job_data.get("source", "mcp")],
    )

    # 8. Ergebnis in Redis speichern
    result_data = {
        "status": "completed",
        "result": json.dumps(analysis, ensure_ascii=False),
        "model_used": model_used,
        "processing_time_ms": str(elapsed_ms),
        "rag_context_used": str(len(rag_results) > 0),
        "ticket_id": ticket_id or "",
        "completed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    r.hset(f"mcp:job:{job_id}", mapping=result_data)

    # TTL setzen: Job-Daten nach 7 Tagen automatisch loeschen
    r.expire(f"mcp:job:{job_id}", 604800)

    # 9. Analyse-Ergebnis in pgvector speichern (fuer zukuenftige RAG-Suche)
    try:
        if pgvector_service.health_check():
            summary = (
                f"Alert von {job_data.get('source', 'unknown')} auf {job_data.get('host', 'unknown')}: "
                f"{job_data.get('description', '')} — "
                f"Ursache: {analysis.get('root_cause', 'N/A')} — "
                f"Massnahme: {analysis.get('immediate_action', 'N/A')}"
            )
            embedding = llm_client.embed(summary)
            if embedding:
                pgvector_service.store_embedding(
                    content=summary,
                    embedding=embedding,
                    source_type="analysis",
                    source_id=job_id,
                    metadata={
                        "source": job_data.get("source"),
                        "host": job_data.get("host"),
                        "severity": severity,
                        "impact": impact,
                        "confidence": analysis.get("confidence"),
                        "ticket_id": ticket_id,
                    },
                )

            confidence_score = {"High": 0.9, "Medium": 0.6, "Low": 0.3}.get(
                analysis.get("confidence", "Low"), 0.3
            )
            pgvector_service.log_analysis(
                event_source=job_data.get("source", "unknown"),
                event_data=job_data,
                analysis_result=analysis,
                confidence_score=confidence_score,
                ticket_id=ticket_id,
                model_used=model_used,
                processing_time_ms=elapsed_ms,
            )
    except Exception as e:
        logger.warning("pgvector-Speicherung fehlgeschlagen (nicht kritisch): %s", e)

    logger.info(
        "Job %s abgeschlossen — Confidence: %s, Impact: %s, Ticket: %s, Dauer: %dms",
        job_id,
        analysis.get("confidence", "?"),
        analysis.get("impact", "?"),
        ticket_id or "keins",
        elapsed_ms,
    )


def main():
    """Hauptschleife — wartet auf Jobs in der Redis-Queue."""
    logger.info("MCP LangChain Worker startet...")
    logger.info("Redis: %s:%s", settings.redis_queue_host, settings.redis_queue_port)
    logger.info("LiteLLM: %s (Fallback: %s)", settings.litellm_host, settings.ollama_host)
    logger.info("pgvector: %s:%s", settings.pgvector_host, settings.pgvector_port)

    # Redis-Verbindung herstellen (mit konfigurierbarem Retry)
    r = None
    for attempt in range(settings.redis_max_connect_retries):
        try:
            r = get_redis()
            r.ping()
            logger.info("Redis-Queue verbunden")
            break
        except Exception:
            logger.info("Warte auf Redis... (Versuch %d/%d)", attempt + 1, settings.redis_max_connect_retries)
            time.sleep(2)

    if r is None:
        logger.error("Redis nicht erreichbar — beende")
        sys.exit(1)

    # pgvector-Verbindung herstellen (nicht-kritisch)
    try:
        pgvector_service.connect()
    except Exception as e:
        logger.warning("pgvector nicht erreichbar (Worker laeuft ohne RAG): %s", e)

    # Hauptverarbeitungsschleife
    logger.info("Worker bereit — warte auf Jobs...")
    reconnect_backoff = settings.redis_reconnect_delay
    while _running:
        try:
            result = r.brpop("mcp:queue:analyze", timeout=5)
            if result:
                _, job_id = result
                process_job(r, job_id)
            reconnect_backoff = settings.redis_reconnect_delay
        except redis.ConnectionError:
            logger.warning("Redis-Verbindung verloren — Reconnect in %ds...", reconnect_backoff)
            time.sleep(reconnect_backoff)
            reconnect_backoff = min(reconnect_backoff * 2, 60)
            try:
                r = get_redis()
            except Exception:
                pass
        except Exception as e:
            logger.error("Fehler bei Job-Verarbeitung: %s", e, exc_info=True)
            time.sleep(1)

    # Aufraumen
    pgvector_service.close()
    logger.info("Worker ordnungsgemaess beendet")


if __name__ == "__main__":
    main()
