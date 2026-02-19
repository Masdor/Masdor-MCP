"""MCP v7 — Zammad Ticket-Client (synchron, fuer den Worker)."""

import logging

import httpx

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class ZammadClient:
    """Synchroner Zammad-Client fuer Ticket-Erstellung."""

    def create_ticket(
        self,
        title: str,
        body: str,
        group: str = "Users",
        priority_id: int = 3,
        tags: str = "",
    ) -> dict | None:
        """Neues Ticket in Zammad erstellen."""
        if not settings.zammad_token:
            logger.warning("ZAMMAD_TOKEN nicht konfiguriert — Ticket-Erstellung uebersprungen")
            return None

        try:
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(
                    f"{settings.zammad_url}/api/v1/tickets",
                    headers={
                        "Authorization": f"Token token={settings.zammad_token}",
                        "Content-Type": "application/json",
                    },
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
        except Exception as e:
            logger.error("Zammad-Ticket-Erstellung fehlgeschlagen: %s", e)
            return None


zammad_client = ZammadClient()
