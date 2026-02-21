"""MCP v7 — LLM Client mit LiteLLM-First und Ollama-Fallback."""

import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class LLMClient:
    """Synchroner LLM-Client: versucht LiteLLM, faellt auf Ollama zurueck."""

    def __init__(self):
        self._litellm_client = httpx.Client(
            base_url=settings.litellm_host,
            timeout=120.0,
        )
        self._ollama_client = httpx.Client(
            base_url=settings.ollama_host,
            timeout=120.0,
        )
        self._embed_client = httpx.Client(
            base_url=settings.ollama_host,
            timeout=30.0,
        )

    def generate(self, prompt: str, system: str | None = None) -> dict:
        """LLM-Anfrage mit LiteLLM-First, Ollama-Fallback."""
        # Versuch 1: LiteLLM (OpenAI-kompatibles Format)
        try:
            result = self._call_litellm(prompt, system)
            if result:
                return result
        except Exception as e:
            logger.warning("LiteLLM nicht erreichbar, Fallback auf Ollama: %s", e)

        # Versuch 2: Ollama direkt
        return self._call_ollama(prompt, system)

    def _call_litellm(self, prompt: str, system: str | None = None) -> dict | None:
        """LLM-Aufruf ueber LiteLLM (OpenAI-kompatibles API) mit Retry."""
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        for attempt in range(2):
            try:
                start = time.monotonic()
                resp = self._litellm_client.post(
                    "/chat/completions",
                    json={
                        "model": settings.primary_model,
                        "messages": messages,
                        "temperature": 0.1,
                        "max_tokens": 2048,
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                elapsed_ms = int((time.monotonic() - start) * 1000)

                content = data["choices"][0]["message"]["content"]
                return {
                    "response": content,
                    "model": data.get("model", settings.primary_model),
                    "latency_ms": elapsed_ms,
                    "via": "litellm",
                }
            except Exception as e:
                if attempt == 0:
                    logger.warning("LiteLLM Versuch 1 fehlgeschlagen: %s — Retry", e)
                    time.sleep(2)
                else:
                    raise
        return None

    def _call_ollama(self, prompt: str, system: str | None = None) -> dict:
        """Direkter LLM-Aufruf an Ollama (Fallback)."""
        payload = {
            "model": settings.primary_model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.1, "num_predict": 2048},
        }
        if system:
            payload["system"] = system

        for attempt in range(3):
            try:
                start = time.monotonic()
                resp = self._ollama_client.post("/api/generate", json=payload)
                resp.raise_for_status()
                data = resp.json()
                elapsed_ms = int((time.monotonic() - start) * 1000)

                return {
                    "response": data.get("response", ""),
                    "model": settings.primary_model,
                    "latency_ms": elapsed_ms,
                    "via": "ollama",
                }
            except Exception as e:
                wait = 2 ** (attempt + 1)
                logger.warning(
                    "Ollama Versuch %d fehlgeschlagen: %s — Retry in %ds",
                    attempt + 1, e, wait,
                )
                if attempt == 2:
                    raise
                time.sleep(wait)
        return {"response": "", "model": settings.primary_model, "latency_ms": 0, "via": "error"}

    def close(self):
        """Alle HTTP-Clients schliessen."""
        self._litellm_client.close()
        self._ollama_client.close()
        self._embed_client.close()

    def embed(self, text: str) -> list[float]:
        """Embedding-Vektor generieren via Ollama mit Retry."""
        for attempt in range(3):
            try:
                resp = self._embed_client.post(
                    "/api/embed",
                    json={"model": settings.embedding_model, "input": text},
                )
                resp.raise_for_status()
                data = resp.json()
                embeddings = data.get("embeddings", [[]])
                return embeddings[0] if embeddings else []
            except Exception as e:
                wait = 2 ** (attempt + 1)
                logger.warning("Embedding Versuch %d fehlgeschlagen: %s", attempt + 1, e)
                if attempt == 2:
                    logger.error("Embedding endgueltig fehlgeschlagen nach 3 Versuchen")
                    return []
                time.sleep(wait)
        return []


llm_client = LLMClient()
