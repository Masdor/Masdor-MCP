"""MCP v7 — LLM Client mit LiteLLM-First und Ollama-Fallback."""

import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger("mcp-langchain-worker")


class LLMClient:
    """Synchroner LLM-Client: versucht LiteLLM, faellt auf Ollama zurueck."""

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
        """LLM-Aufruf ueber LiteLLM (OpenAI-kompatibles API)."""
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        start = time.monotonic()
        with httpx.Client(timeout=120.0) as client:
            resp = client.post(
                f"{settings.litellm_host}/chat/completions",
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
                with httpx.Client(timeout=120.0) as client:
                    resp = client.post(
                        f"{settings.ollama_host}/api/generate",
                        json=payload,
                    )
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

    def embed(self, text: str) -> list[float]:
        """Embedding-Vektor generieren via Ollama."""
        try:
            with httpx.Client(timeout=30.0) as client:
                resp = client.post(
                    f"{settings.ollama_host}/api/embed",
                    json={"model": settings.embedding_model, "input": text},
                )
                resp.raise_for_status()
                data = resp.json()
                embeddings = data.get("embeddings", [[]])
                return embeddings[0] if embeddings else []
        except Exception as e:
            logger.error("Embedding fehlgeschlagen: %s", e)
            return []


llm_client = LLMClient()
