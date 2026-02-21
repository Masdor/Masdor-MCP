"""MCP v7 — Pydantic Request/Response Models fuer den AI Gateway."""

from typing import Any

from pydantic import BaseModel, Field, field_validator


# ---------------------------------------------------------------------------
# Analyze (Queue-basiert)
# ---------------------------------------------------------------------------
class AnalyzeRequest(BaseModel):
    source: str = Field(..., min_length=1, max_length=50, description="Event-Quelle: zabbix, loki, crowdsec, etc.")
    severity: str = Field(default="warning", description="Schweregrad: info, warning, high, critical")
    host: str = Field(default="unknown", max_length=255, description="Betroffener Host/Service")
    description: str = Field(..., min_length=1, max_length=4000, description="Event-Beschreibung")
    metrics: dict[str, Any] = Field(default_factory=dict, description="Zugehoerige Metriken")
    logs: str = Field(default="", max_length=10000, description="Letzte Log-Zeilen")
    crowdsec_alerts: str = Field(default="", max_length=10000, description="IDS-Daten von CrowdSec")

    @field_validator("severity")
    @classmethod
    def validate_severity(cls, v: str) -> str:
        allowed = {"info", "warning", "high", "critical"}
        if v not in allowed:
            v = "warning"
        return v

    @field_validator("metrics")
    @classmethod
    def validate_metrics_size(cls, v: dict) -> dict:
        if len(v) > 50:
            raise ValueError("Maximal 50 Metriken erlaubt")
        return v


class AnalyzeResponse(BaseModel):
    status: str
    job_id: str
    message: str


# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------
class JobStatus(BaseModel):
    id: str
    status: str
    source: str = ""
    severity: str = ""
    host: str = ""
    description: str = ""
    created_at: str = ""
    completed_at: str = ""
    result: dict[str, Any] | None = None
    model_used: str = ""
    processing_time_ms: int = 0
    ticket_id: str = ""


class JobListResponse(BaseModel):
    jobs: list[JobStatus]
    total: int
    offset: int
    limit: int


# ---------------------------------------------------------------------------
# Embed
# ---------------------------------------------------------------------------
class EmbedRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=50000, description="Text fuer Embedding")
    source_type: str = Field(default="manual", max_length=50, description="Quelltyp: ticket, wiki, log, manual")
    source_id: str | None = Field(default=None, max_length=255, description="Quell-ID")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Zusaetzliche Metadaten")


class EmbedResponse(BaseModel):
    status: str
    embedding_id: int | None = None
    dimensions: int
    stored: bool
    model_used: str


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------
class SearchResult(BaseModel):
    id: int
    content: str
    similarity: float
    source_type: str = ""
    metadata: dict[str, Any] = Field(default_factory=dict)


class SearchResponse(BaseModel):
    status: str
    query: str
    results: list[SearchResult]
    total: int


# ---------------------------------------------------------------------------
# Ingest
# ---------------------------------------------------------------------------
class IngestRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=500000, description="Dokument-Text fuer RAG-Aufnahme")
    source_type: str = Field(default="document", max_length=50, description="Quelltyp: wiki, ticket, document")
    source_id: str | None = Field(default=None, max_length=255, description="Quell-ID")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Metadaten")
    chunk_size: int = Field(default=512, ge=10, le=10000, description="Chunk-Groesse")
    chunk_overlap: int = Field(default=50, ge=0, description="Chunk-Ueberlappung")

    @field_validator("chunk_overlap")
    @classmethod
    def validate_overlap(cls, v: int, info) -> int:
        chunk_size = info.data.get("chunk_size", 512)
        if v >= chunk_size:
            raise ValueError("chunk_overlap muss kleiner als chunk_size sein")
        return v


class IngestResponse(BaseModel):
    status: str
    chunks_created: int
    source_type: str
    source_id: str | None


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class ModelInfo(BaseModel):
    name: str
    size: str | None = None
    modified_at: str | None = None


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------
class HealthResponse(BaseModel):
    status: str
    redis: str
    ollama: str
    litellm: str
    pgvector: str
    zammad: str
    ntfy: str
    uptime_seconds: int
    version: str = "2.0.0"
