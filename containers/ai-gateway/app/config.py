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

    @property
    def pgvector_dsn(self) -> str:
        return (
            f"postgresql://{self.pgvector_user}:{self.pgvector_password}"
            f"@{self.pgvector_host}:{self.pgvector_port}/{self.pgvector_db}"
        )


settings = Settings()
