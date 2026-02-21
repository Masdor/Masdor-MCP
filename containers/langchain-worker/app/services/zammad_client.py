"""MCP v7 — Zammad Ticket-Client (synchron, fuer den Worker) mit Retry."""

import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class ZammadClient:
    """Synchroner Zammad-Client fuer Ticket-Erstellung mit Retry-Logik."""

    def __init__(self):
        self._client = httpx.Client(
            base_url=settings.zammad_url,
            timeout=15.0,
            headers={
                "Authorization": f"Token token={settings.zammad_token}",
                "Content-Type": "application/json",
            },
        )

    def create_ticket(
        self,
        title: str,
        body: str,
        group: str = "Users",
        priority_id: int = 3,
        tags: str = "",
    ) -> dict | None:
        """Neues Ticket in Zammad erstellen (3 Versuche)."""
        if not settings.zammad_token:
            logger.warning("ZAMMAD_TOKEN nicht konfiguriert — Ticket-Erstellung uebersprungen")
            return None

        for attempt in range(3):
            try:
                resp = self._client.post(
                    "/api/v1/tickets",
                    json={
                        "title": title,
                        "group": group,
                        "article": {
                            "subject": title,
                            "body": body,
                            "type": "note",
                            "internal": False,
                            "content_type": "text/html",
                        },
                        "priority_id": priority_id,
                        "tags": tags,
                    },
                )
                resp.raise_for_status()
                ticket = resp.json()
                logger.info("Zammad-Ticket #%s erstellt: %s", ticket.get("id"), title)
                return ticket
            except httpx.TimeoutException as e:
                wait = 2 ** (attempt + 1)
                logger.warning("Zammad Timeout Versuch %d: %s — Retry in %ds", attempt + 1, e, wait)
                if attempt == 2:
                    logger.error("Zammad-Ticket-Erstellung endgueltig fehlgeschlagen nach 3 Versuchen")
                    return None
                time.sleep(wait)
            except httpx.HTTPStatusError as e:
                logger.error("Zammad HTTP-Fehler %d: %s", e.response.status_code, e)
                return None
            except Exception as e:
                logger.error("Zammad-Ticket-Erstellung fehlgeschlagen: %s", e)
                return None
        return None


zammad_client = ZammadClient()
