"""MCP v7 — Prompt-Management: laedt und befuellt den Alert-Analyse-Prompt."""

import logging
import os

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")

# Cache fuer geladenen Prompt
_prompt_template: str | None = None

# Fallback-Prompt falls Datei nicht verfuegbar
FALLBACK_PROMPT = """Du bist ein IT-Operations-Analyst fuer die Managed Control Platform (MCP).
Analysiere den folgenden Alert und erstelle einen strukturierten Incident-Bericht.
Antworte auf Deutsch. Sei praezise und technisch korrekt.

KONTEXT:
- Alert-Typ: {alert_type}
- Quelle: {source}
- Host: {hostname}
- Schweregrad: {severity}
- Zeitstempel: {timestamp}
- Beschreibung: {description}
- Aktuelle Metriken: {metrics}
- Letzte 10 Log-Zeilen: {logs}
- IDS-Daten: {crowdsec_alerts}

HISTORISCH (RAG):
- Aehnliche Incidents: {rag_results}

AUFGABE:
1. Root-Cause-Analyse (1-2 Saetze)
2. Auswirkung (Gering/Mittel/Hoch/Kritisch)
3. Betroffene Dienste/Kunden
4. Empfohlene Sofortmassnahme (konkrete Schritte)
5. Langfristige Loesung (Praevention)
6. Konfidenz (High/Medium/Low) mit Begruendung

FORMAT: JSON
{{
  "root_cause": "",
  "impact": "Gering|Mittel|Hoch|Kritisch",
  "affected_services": [],
  "immediate_action": "",
  "long_term_solution": "",
  "confidence": "High|Medium|Low",
  "confidence_reason": "",
  "ticket_title": "",
  "ticket_priority": "1_low|2_normal|3_high|4_urgent"
}}"""


def load_prompt_template() -> str:
    """Prompt-Template aus Datei laden (mit Fallback)."""
    global _prompt_template
    if _prompt_template is not None:
        return _prompt_template

    prompt_path = settings.prompt_file
    if os.path.exists(prompt_path):
        try:
            with open(prompt_path, "r", encoding="utf-8") as f:
                _prompt_template = f.read()
            logger.info("Prompt-Template geladen: %s", prompt_path)
            return _prompt_template
        except Exception as e:
            logger.warning("Prompt-Datei konnte nicht geladen werden: %s — verwende Fallback", e)

    logger.info("Verwende Fallback-Prompt (Datei nicht gefunden: %s)", prompt_path)
    _prompt_template = FALLBACK_PROMPT
    return _prompt_template


def build_prompt(job_data: dict, rag_results: list[dict] | None = None) -> str:
    """Prompt mit Job-Daten und RAG-Ergebnissen befuellen."""
    template = load_prompt_template()

    # RAG-Ergebnisse formatieren
    rag_text = "Keine aehnlichen Incidents gefunden."
    if rag_results:
        entries = []
        for r in rag_results:
            sim = r.get("similarity", 0)
            content = r.get("content", "")[:300]
            entries.append(f"  - [Aehnlichkeit: {sim:.2f}] {content}")
        rag_text = "\n".join(entries)

    # Platzhalter befuellen
    import time
    prompt = template.format(
        alert_type=job_data.get("source", "unknown"),
        source=job_data.get("source", "unknown"),
        hostname=job_data.get("host", "unknown"),
        severity=job_data.get("severity", "warning"),
        timestamp=job_data.get("created_at", time.strftime("%Y-%m-%dT%H:%M:%SZ")),
        description=job_data.get("description", "Keine Beschreibung"),
        metrics=job_data.get("metrics", "{}"),
        logs=job_data.get("logs", "keine"),
        crowdsec_alerts=job_data.get("crowdsec_alerts", "keine"),
        rag_results=rag_text,
    )
    return prompt
