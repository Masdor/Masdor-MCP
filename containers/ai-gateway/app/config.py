"""MCP v7 — AI Gateway Konfiguration (aus Environment-Variablen)."""

import os


class Settings:
    """Gateway-Konfiguration aus Environment-Variablen."""

    # Auth
    ai_gateway_secret: str = os.getenv("AI_GATEWAY_SECRET", "")

    # Ollama
    ollama_host: str = os.getenv("OLLAMA_HOST", "http://ollama:11434")
    default_model: str = os.getenv("PRIMARY_MODEL", "mistral:7b-instruct-v0.3-q4_K_M")
    embedding_model: str = os.getenv("EMBEDDING_MODEL", "nomic-embed-text")

    # LiteLLM
    litellm_host: str = os.getenv("LITELLM_HOST", "http://litellm:4000")

    # Redis
    redis_queue_host: str = os.getenv("REDIS_QUEUE_HOST", "redis-queue")
    redis_queue_port: int = int(os.getenv("REDIS_QUEUE_PORT", "6379"))
    redis_queue_password: str = os.getenv("REDIS_QUEUE_PASSWORD", "")
    redis_pool_max: int = int(os.getenv("REDIS_POOL_MAX", "20"))

    # pgvector
    pgvector_host: str = os.getenv("PGVECTOR_HOST", "pgvector")
    pgvector_port: int = int(os.getenv("PGVECTOR_PORT", "5432"))
    pgvector_user: str = os.getenv("PGVECTOR_USER", "pgvector")
    pgvector_password: str = os.getenv("PGVECTOR_PASSWORD", "")
    pgvector_db: str = os.getenv("PGVECTOR_DB", "mcp_vectors")

    # Zammad
    zammad_url: str = os.getenv("ZAMMAD_URL", "http://zammad-rails:3000")
    zammad_token: str = os.getenv("ZAMMAD_TOKEN", "")

    # ntfy
    ntfy_url: str = os.getenv("NTFY_URL", "http://ntfy:80")

    # AI-Einstellungen
    confidence_threshold: float = float(os.getenv("CONFIDENCE_THRESHOLD", "0.75"))

    # Deduplizierung
    dedup_ttl_seconds: int = int(os.getenv("DEDUP_TTL_SECONDS", "900"))

    # Validierungsgrenzen
    max_description_length: int = int(os.getenv("MAX_DESCRIPTION_LENGTH", "4000"))
    max_search_top_k: int = int(os.getenv("MAX_SEARCH_TOP_K", "100"))
    max_chunk_size: int = int(os.getenv("MAX_CHUNK_SIZE", "10000"))
    max_ingest_text_length: int = int(os.getenv("MAX_INGEST_TEXT_LENGTH", "500000"))

    # Embedding-Validierung
    expected_embedding_dimensions: int = int(os.getenv("EXPECTED_EMBEDDING_DIMENSIONS", "768"))

    @property
    def pgvector_dsn(self) -> str:
        return (
            f"postgresql://{self.pgvector_user}:{self.pgvector_password}"
            f"@{self.pgvector_host}:{self.pgvector_port}/{self.pgvector_db}"
        )


settings = Settings()
