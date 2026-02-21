"""MCP v7 — ntfy Push-Notification Client mit Retry."""

import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")

# Severity → ntfy Priority Mapping
SEVERITY_PRIORITY = {
    "Kritisch": 5,
    "critical": 5,
    "Hoch": 4,
    "high": 4,
    "Mittel": 3,
    "warning": 3,
    "medium": 3,
    "Gering": 2,
    "low": 2,
    "info": 1,
}


class NtfyClient:
    """Push-Benachrichtigungen ueber ntfy senden mit Retry-Logik."""

    def send_notification(
        self,
        title: str,
        message: str,
        severity: str = "Mittel",
        tags: list[str] | None = None,
        click_url: str | None = None,
    ) -> bool:
        """Benachrichtigung an ntfy/mcp-alerts senden (2 Versuche)."""
        priority = SEVERITY_PRIORITY.get(severity, 3)
        ntfy_tags = ",".join(tags) if tags else "robot"

        headers = {
            "Title": title[:200],
            "Priority": str(priority),
            "Tags": ntfy_tags,
        }
        if click_url:
            headers["Click"] = click_url

        for attempt in range(2):
            try:
                with httpx.Client(timeout=10.0) as client:
                    resp = client.post(
                        f"{settings.ntfy_url}/mcp-alerts",
                        content=message[:4000],
                        headers=headers,
                    )
                    resp.raise_for_status()
                    logger.info("ntfy-Benachrichtigung gesendet: %s (Prioritaet: %d)", title, priority)
                    return True
            except Exception as e:
                if attempt == 0:
                    logger.warning("ntfy Versuch 1 fehlgeschlagen: %s — Retry", e)
                    time.sleep(2)
                else:
                    logger.error("ntfy-Benachrichtigung endgueltig fehlgeschlagen: %s", e)
                    return False
        return False


ntfy_client = NtfyClient()
