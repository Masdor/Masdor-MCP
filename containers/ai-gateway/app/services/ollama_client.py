"""MCP v7 — Async Ollama HTTP Client mit Retry-Logik."""

import asyncio
import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger("mcp-ai-gateway")


class OllamaClient:
    """Asynchroner Ollama-Client fuer LLM-Inference und Embeddings."""

    def __init__(self):
        self.base_url = settings.ollama_host
        self.client = httpx.AsyncClient(base_url=self.base_url, timeout=120.0)

    async def generate(
        self,
        prompt: str,
        model: str | None = None,
        system: str | None = None,
        temperature: float = 0.3,
    ) -> dict:
        """LLM-Completion mit Retry-Logik (3 Versuche)."""
        model = model or settings.default_model
        payload = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": temperature},
        }
        if system:
            payload["system"] = system

        for attempt in range(3):
            try:
                start = time.monotonic()
                resp = await self.client.post("/api/generate", json=payload)
                resp.raise_for_status()
                elapsed_ms = int((time.monotonic() - start) * 1000)
                data = resp.json()
                data["latency_ms"] = elapsed_ms
                return data
            except (httpx.HTTPStatusError, httpx.ConnectError, httpx.ReadTimeout) as e:
                wait = 2 ** (attempt + 1)
                logger.warning(
                    "Ollama Versuch %d fehlgeschlagen: %s — Retry in %ds",
                    attempt + 1, e, wait,
                )
                if attempt == 2:
                    raise
                await asyncio.sleep(wait)
        return {}

    async def embed(self, text: str, model: str | None = None) -> list[float]:
        """Embedding-Vektor generieren."""
        model = model or settings.embedding_model
        resp = await self.client.post(
            "/api/embed",
            json={"model": model, "input": text},
        )
        resp.raise_for_status()
        data = resp.json()
        embeddings = data.get("embeddings", [[]])
        return embeddings[0] if embeddings else []

    async def list_models(self) -> list[dict]:
        """Verfuegbare Ollama-Modelle auflisten."""
        try:
            resp = await self.client.get("/api/tags")
            resp.raise_for_status()
            data = resp.json()
            return data.get("models", [])
        except Exception as e:
            logger.error("Modell-Liste fehlgeschlagen: %s", e)
            return []

    async def health_check(self) -> bool:
        """Ollama-Erreichbarkeit pruefen."""
        try:
            resp = await self.client.get("/api/tags")
            return resp.status_code == 200
        except Exception:
            return False

    async def close(self):
        await self.client.aclose()


ollama_client = OllamaClient()
