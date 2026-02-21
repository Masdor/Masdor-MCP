"""MCP v7 — LangChain Worker Konfiguration (aus Environment-Variablen)."""

import os


class Settings:
    """Worker-Konfiguration aus Environment-Variablen."""

    # Redis Queue
    redis_queue_host: str = os.getenv("REDIS_QUEUE_HOST", "redis-queue")
    redis_queue_port: int = int(os.getenv("REDIS_QUEUE_PORT", "6379"))

    # Ollama (Fallback)
    ollama_host: str = os.getenv("OLLAMA_HOST", "http://ollama:11434")

    # LiteLLM (primaer)
    litellm_host: str = os.getenv("LITELLM_HOST", "http://litellm:4000")

    # Modelle
    primary_model: str = os.getenv("PRIMARY_MODEL", "mistral:7b")
    embedding_model: str = os.getenv("EMBEDDING_MODEL", "nomic-embed-text")

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
    ntfy_max_message_length: int = int(os.getenv("NTFY_MAX_MSG_LEN", "4000"))

    # Redis-Retry-Konfiguration
    redis_max_connect_retries: int = int(os.getenv("REDIS_MAX_RETRIES", "30"))
    redis_reconnect_delay: int = int(os.getenv("REDIS_RECONNECT_DELAY", "2"))

    # Redis Queue Passwort
    redis_queue_password: str = os.getenv("REDIS_QUEUE_PASSWORD", "")

    # RAG-Konfiguration
    rag_top_k: int = int(os.getenv("RAG_TOP_K", "5"))
    rag_similarity_threshold: float = float(os.getenv("RAG_SIMILARITY_THRESHOLD", "0.7"))

    # Pfade
    prompt_file: str = os.getenv("PROMPT_FILE", "/app/config/prompts/alert-analysis.txt")
    rag_config_file: str = os.getenv("RAG_CONFIG_FILE", "/app/config/rag-config.yml")

    @property
    def pgvector_dsn(self) -> str:
        return (
            f"host={self.pgvector_host} port={self.pgvector_port} "
            f"user={self.pgvector_user} password={self.pgvector_password} "
            f"dbname={self.pgvector_db}"
        )


settings = Settings()
