# MCP v7 — Vollständige Code-Analyse & Optimierungsplan

## 🔴 KRITISCH: Funktionen die NUR als Name existieren (ohne Implementierung)

### 1. AI Gateway — `/api/v1/search` (Zeile 223-238, `main.py`)
- **Status:** STUB — gibt nur Placeholder zurück
- **Code:** `"message": "RAG search — pgvector integration pending"`
- **Fehlt:** pgvector-Verbindung, Vektor-Suche, Embedding-Vergleich

### 2. AI Gateway — `/api/v1/embed` (Zeile 198-220, `main.py`)
- **Status:** HALBFERTIG — erzeugt Embeddings via Ollama, speichert sie aber NIRGENDS
- **Fehlt:** Speicherung in pgvector, Metadaten-Handling, Collection-Management

### 3. LangChain Worker — RAG-Pipeline (komplett fehlend)
- **Status:** NICHT IMPLEMENTIERT — trotz Name "LangChain Worker"
- **Worker** nutzt LangChain überhaupt NICHT (nur raw httpx)
- **Fehlt:** pgvector-Verbindung, Embedding-Suche, RAG-Context-Injection
- **Konfiguriert in** `rag-config.yml` aber NICHT im Code verwendet

### 4. LangChain Worker — Zammad Ticket-Erstellung (fehlend)
- **Status:** NICHT IMPLEMENTIERT
- **Beschrieben im Docstring** (Zeile 5: "Create ticket in Zammad") aber Code fehlt
- **Fehlt:** HTTP-Call zu Zammad API, Ticket-Mapping, Priority-Handling

### 5. LangChain Worker — ntfy Benachrichtigung (fehlend)
- **Status:** NICHT IMPLEMENTIERT
- **Beschrieben im Docstring** (Zeile 6: "Send notification via ntfy") aber Code fehlt
- **Fehlt:** ntfy POST-Request, Channel-Konfiguration, Severity-basiertes Routing

### 6. LangChain Worker — Professioneller Prompt nicht verwendet
- **Status:** IGNORIERT
- **Datei** `config/ai/prompts/alert-analysis.txt` enthält professionellen Prompt mit RAG-Slots
- **Worker** nutzt stattdessen einen simplen hardcodierten Prompt (Zeile 67-83)
- **Prompt-Datei** hat Felder für: `{rag_results}`, `{crowdsec_alerts}`, `{metrics}` — alle ungenutzt

### 7. LiteLLM — konfiguriert aber ungenutzt
- **Status:** VERSCHWENDUNG — Container läuft, wird aber nie angesprochen
- **Worker** spricht direkt mit Ollama statt über LiteLLM
- **LiteLLM** sollte als Model-Router fungieren (Failover, Load-Balancing)

---

## 🟡 Fehlende Service-Verbindungen (Service-Mesh-Lücken)

| Von → Nach | Status | Beschreibung |
|---|---|---|
| **Zabbix → AI Gateway** | ❌ FEHLT | Kein Webhook/Trigger konfiguriert. Zabbix-Alerts erreichen die AI nie |
| **CrowdSec → AI Gateway** | ❌ FEHLT | IDS-Daten werden nicht an AI weitergeleitet |
| **n8n → AI Gateway** | ❌ FEHLT | Keine Workflows definiert (leerer Ordner `config/n8n/workflows/`) |
| **n8n → Zabbix** | ❌ FEHLT | Keine Automatisierung |
| **n8n → Zammad** | ❌ FEHLT | Keine Automatisierung |
| **n8n → ntfy** | ❌ FEHLT | Keine Automatisierung |
| **AI Gateway → LiteLLM** | ❌ FEHLT | Gateway spricht nicht mit LiteLLM |
| **LangChain → pgvector** | ❌ FEHLT | Env-Vars konfiguriert aber kein Code |
| **LangChain → Zammad** | ❌ FEHLT | Docstring beschreibt es, Code fehlt |
| **LangChain → ntfy** | ❌ FEHLT | Docstring beschreibt es, Code fehlt |
| **Keycloak → alle Services** | ❌ FEHLT | SSO nirgends integriert |
| **OpenBao → alle Services** | ❌ FEHLT | Secrets werden per ENV verwaltet, nicht über Vault |
| **BookStack → RAG** | ❌ FEHLT | Wissensbasis wird nicht für RAG genutzt |
| **Grafana → AI Metrics** | ❌ FEHLT | Kein Dashboard für AI-Pipeline-Metriken |
| **Alloy → AI Logs** | ✅ OK | Docker-Logs werden via Alloy → Loki gesammelt |
| **Grafana → Loki** | ✅ OK | Datasource konfiguriert |
| **Grafana → Zabbix** | ✅ OK | Datasource konfiguriert |

---

## 🟢 Was funktioniert

- Docker-Compose-Architektur (5 Stacks, 5 Netzwerke)
- Nginx Reverse-Proxy mit 13 korrekten Proxy-Pfaden
- Dashboard HTML
- Redis-Queue + Deduplication in AI Gateway
- Ollama-Analyse (simpel aber funktional)
- Job-Queue-System (Redis LPUSH/BRPOP)
- Health-Checks für alle Container
- Alloy → Loki Log-Pipeline
- Grafana Datasource-Provisioning
- Security-Hardening (no-new-privileges, network isolation)
- Smoke/AI/Security Tests

---

## 🟠 Fehlende Dateien (im Makefile referenziert)

- `scripts/mcp-backup.sh` — existiert NICHT
- `scripts/mcp-restore.sh` — existiert NICHT
- `scripts/mcp-pull-images.sh` — existiert NICHT

---

## 📊 Zusammenfassung der Lücken

| Kategorie | Anzahl |
|---|---|
| Stub/Placeholder Endpoints | 2 |
| Fehlende Kernfunktionen im Worker | 4 |
| Ungenutzte Services | 2 (LiteLLM, OpenBao) |
| Fehlende Service-Verbindungen | 12 |
| Fehlende Dateien | 3 |
| **Gesamt** | **23 Lücken** |

---
---
---

# 🤖 Claude Code Prompt — MCP v7 Vollständige Optimierung

Kopiere den folgenden Prompt in Claude Code und führe ihn aus:

---

```
Du bist der Programmier-Assistent für das Masdor MCP v7 Projekt (GitHub Repo).
Ich bin Moustafa, der Admin.

## KONTEXT
MCP v7 ist eine AI-powered IT Operations Platform mit 33 Containern in 5 Docker-Compose-Stacks.
Die Architektur steht, aber viele Funktionen sind nur als Name/Stub implementiert.
Ich brauche dich, um ALLE folgenden Lücken systematisch zu schließen.

## REGELN
- Arbeite Phase für Phase, commit nach jeder Phase
- Teste jede Änderung bevor du weitergehst
- Bestehenden funktionierenden Code NICHT brechen
- Deutsche Kommentare im Code, deutsche AI-Prompts
- Alle Konfiguration über Environment-Variablen
- Keine hartcodierten Secrets im Code

## PHASE 1: LangChain Worker komplett neu implementieren
Datei: `containers/langchain-worker/app/worker.py`

### 1.1 pgvector-Integration einbauen
- Verbindung zu pgvector herstellen (Env-Vars sind schon in docker-compose)
- Tabelle `mcp_knowledge` erstellen: id, embedding vector(768), text, metadata jsonb, created_at
- Bei jedem Job: RAG-Suche mit Embedding-Vergleich (top_k=5, threshold=0.7)
- Konfiguration aus `config/ai/rag-config.yml` laden

### 1.2 Professionellen Prompt verwenden
- Prompt aus `config/ai/prompts/alert-analysis.txt` laden statt hardcoded
- Alle Platzhalter befüllen: {alert_type}, {source}, {hostname}, {severity}, {timestamp}, {description}, {metrics}, {logs}, {crowdsec_alerts}, {rag_results}
- RAG-Ergebnisse als Kontext einsetzen

### 1.3 LiteLLM statt direkt Ollama verwenden
- Worker soll über LiteLLM (http://litellm:4000) statt direkt über Ollama kommunizieren
- OpenAI-kompatibles API-Format verwenden (LiteLLM bietet das)
- Failover-Logik: wenn LiteLLM nicht erreichbar → Fallback auf Ollama direkt

### 1.4 Zammad Ticket-Erstellung implementieren
- Nach erfolgreicher Analyse: Ticket in Zammad erstellen via REST API
- POST zu http://zammad-rails:3000/api/v1/tickets
- Token aus ZAMMAD_TOKEN env var (wird über AI Gateway weitergereicht)
- Ticket-Felder: title, group, priority (aus AI-Analyse), note (AI-Bericht)
- Job-ID als Referenz im Ticket

### 1.5 ntfy Benachrichtigung implementieren
- Nach Ticket-Erstellung: Push-Notification über ntfy
- POST zu http://ntfy:80/mcp-alerts
- Severity → Priority-Mapping: Kritisch=5, Hoch=4, Mittel=3, Gering=2
- Inhalt: Ticket-Titel, Impact, Sofortmaßnahme, Link zum Ticket

### 1.6 LangChain tatsächlich verwenden
- LangChain Chains für die RAG-Pipeline nutzen
- LangChain pgvector VectorStore einbinden
- LangChain Prompt Templates verwenden

## PHASE 2: AI Gateway Endpoints fertigstellen
Datei: `containers/ai-gateway/app/main.py`

### 2.1 `/api/v1/search` — RAG-Suche implementieren
- pgvector-Verbindung herstellen (psycopg2 + pgvector Extension)
- Query-Text → Embedding via Ollama
- Vektor-Ähnlichkeitssuche in pgvector
- Ergebnisse mit Score zurückgeben
- Parameter: query, top_k, similarity_threshold

### 2.2 `/api/v1/embed` — Speicherung ergänzen
- Nach Embedding-Erstellung: in pgvector speichern
- Metadaten als JSONB speichern
- Duplikat-Check via Text-Hash
- Response: embedding_id, dimensions, stored=true

### 2.3 Neue Endpoints hinzufügen
- `GET /api/v1/jobs/{job_id}` — Job-Status abfragen
- `GET /api/v1/jobs` — Alle Jobs listen (mit Pagination)
- `POST /api/v1/ingest` — Dokument für RAG aufnehmen (Chunking + Embedding)
- `GET /api/v1/models` — Verfügbare Modelle anzeigen (via LiteLLM)
- `DELETE /api/v1/knowledge/{id}` — RAG-Eintrag löschen

### 2.4 Metriken erweitern
- Prometheus-Format für `/metrics` (nicht nur JSON)
- Zähler: requests_total, analyses_completed, tickets_created, rag_searches, embeddings_stored
- Histogramm: analysis_duration_seconds
- Gauge: queue_length, active_jobs

### 2.5 Health-Check erweitern
- Prüfe alle Abhängigkeiten: Redis, Ollama, LiteLLM, pgvector, Zammad, ntfy
- Jede Komponente einzeln mit Status

## PHASE 3: n8n Workflows erstellen
Verzeichnis: `config/n8n/workflows/`

Erstelle JSON-Workflow-Dateien für:

### W1: Zabbix → AI Gateway
- Trigger: Zabbix Webhook empfangen
- Transform: Zabbix-Alert-Format → AI Gateway AnalyzeRequest
- Action: POST an http://ai-gateway:8000/api/v1/analyze
- Error-Handling: Retry 3x, dann ntfy-Alert

### W2: CrowdSec → AI Gateway
- Trigger: CrowdSec Alert via HTTP
- Transform: CrowdSec-Daten → crowdsec_alerts Feld
- Action: POST an AI Gateway mit Security-Severity

### W3: BookStack → RAG Ingestion
- Trigger: Webhook bei neuer/geänderter BookStack-Seite
- Action: Text extrahieren, POST an /api/v1/ingest
- Damit wird die Wissensbasis automatisch befüllt

### W4: Periodischer Health-Report
- Trigger: Cron (täglich 8:00)
- Sammle: Uptime Kuma Status, Zabbix Probleme, offene Tickets
- Generiere: AI-Zusammenfassung
- Sende: ntfy Daily Report

## PHASE 4: Service-Integrationen verbessern

### 4.1 Grafana Dashboard für AI-Pipeline
- Erstelle JSON-Dashboard-Datei: `config/grafana/dashboards/ai-pipeline.json`
- Panels: Queue-Länge, Analyse-Dauer, Tickets erstellt, Konfidenz-Verteilung
- Datenquelle: AI Gateway /metrics + Loki Logs

### 4.2 Grafana Dashboard Provisioning
- Erstelle `config/grafana/dashboard-provider.yml` für automatisches Dashboard-Loading

### 4.3 pgvector Initialisierung
- Erweitere `scripts/init-db.sh` um pgvector-Setup:
  - CREATE EXTENSION vector;
  - CREATE TABLE mcp_knowledge (id, embedding, text, metadata, created_at)
  - CREATE INDEX für Vektor-Ähnlichkeitssuche (ivfflat oder hnsw)

## PHASE 5: Fehlende Scripts erstellen

### 5.1 `scripts/mcp-backup.sh`
- Backup aller Docker-Volumes
- PostgreSQL pg_dump für alle DBs
- pgvector Daten
- Komprimiertes tar.gz mit Timestamp

### 5.2 `scripts/mcp-restore.sh`
- Interaktiv: Backup-Datei auswählen
- Restore-Reihenfolge: DB → Volumes → Verify

### 5.3 `scripts/mcp-pull-images.sh`
- Alle Images aus docker-compose Dateien extrahieren
- Parallel pullen mit Progress

## PHASE 6: Container-Optimierungen

### 6.1 Dockerfiles verbessern
- Multi-stage Builds für kleinere Images
- Non-root User
- Health-Check in Dockerfile
- .dockerignore Dateien erstellen

### 6.2 requirements.txt aufräumen
- Ungenutzte Packages entfernen
- Version-Pinning überprüfen

## ABSCHLUSS
- Alle Tests (make test) müssen bestehen
- `make status` muss alle Container als healthy zeigen
- Dokumentation in README aktualisieren
- CHANGELOG.md erstellen

Beginne mit Phase 1. Zeige mir zuerst den Plan für die worker.py Neuimplementierung, dann implementiere sie Schritt für Schritt.
```

---

# Zusammenfassung der 6 Phasen

| Phase | Beschreibung | Dateien | Priorität |
|---|---|---|---|
| **Phase 1** | LangChain Worker komplett | `worker.py` | 🔴 Kritisch |
| **Phase 2** | AI Gateway Endpoints | `main.py` | 🔴 Kritisch |
| **Phase 3** | n8n Workflows | `config/n8n/workflows/` | 🟡 Hoch |
| **Phase 4** | Grafana + pgvector Init | `config/grafana/`, `init-db.sh` | 🟡 Hoch |
| **Phase 5** | Fehlende Scripts | `scripts/` | 🟠 Mittel |
| **Phase 6** | Container-Optimierungen | `Dockerfile`, `requirements.txt` | 🟠 Mittel |
