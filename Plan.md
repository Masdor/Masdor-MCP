# MCP v7 — Projektplan & Systemarchitektur

> **Dieses Dokument ist die zentrale Wahrheit des Projekts.**
> Jede KI (Claude, Copilot, etc.) die an diesem Projekt arbeitet, MUSS dieses Dokument zuerst lesen und verstehen, bevor Code geschrieben oder Änderungen vorgenommen werden.

---

## 1. Vision

MCP ist ein **vollständig lokales, KI-gestütztes IT-Operations-Center** — ein modernes, sicheres System, das jede Firma haben will. Kein Internet. Kein Cloud. Alles läuft auf einer einzigen Maschine. Die KI denkt mit, erkennt Probleme bevor sie passieren, erstellt automatisch Tickets und lernt aus jeder gelösten Störung.

**Kernprinzipien:**

- **100% Offline** — kein externer API-Call, kein Cloud-Dienst, kein Telemetrie-Abfluss
- **KI-First** — jedes Signal (Log, Metrik, Alert) fließt durch die lokale KI-Pipeline
- **Zero-Trust intern** — Netzwerksegmentierung, Secrets-Management, MFA
- **Human-in-the-Loop** — KI schlägt vor, Mensch entscheidet (konfigurierbar)
- **Ein Skript, ein Befehl** — Installation, Validierung und Betrieb über ein einziges intelligentes Skript

---

## 2. Ziel-Hardware

| Komponente     | Spezifikation                    | Zweck                                    |
|----------------|----------------------------------|------------------------------------------|
| **RAM**        | 32 GB                            | 32 Container parallel                    |
| **Storage**    | 500 GB SSD/HDD                   | OS + Container + Daten + KI-Modelle      |
| **GPU**        | NVIDIA RTX 4070 (12 GB VRAM)     | Lokale LLM-Inferenz (Ollama)             |
| **OS**         | Debian 12 / Ubuntu 24.04         | Docker Host                              |
| **Netzwerk**   | Statische lokale IP (z.B. `192.168.1.100`) | Alle Dienste über HTTP erreichbar |

### RAM-Verteilung (geschätzt)

| Stack        | Container | RAM (ca.) |
|--------------|-----------|-----------|
| Core         | 7         | ~4 GB     |
| Ops          | 6         | ~4 GB     |
| Telemetry    | 6         | ~3 GB     |
| Remote       | 3         | ~1 GB     |
| AI           | 5         | ~14 GB    |
| System/OS    | —         | ~4 GB     |
| **Reserve**  | —         | ~2 GB     |
| **Gesamt**   | **32**    | **~32 GB**|

### GPU-Nutzung

- **Ollama** mit NVIDIA Container Toolkit (`nvidia-docker`)
- Modell: `mistral:7b-instruct-v0.3` oder `llama3:8b` (passt in 12 GB VRAM)
- Quantisierung: Q4_K_M für optimale Geschwindigkeit/Qualität
- Fallback: CPU-Inferenz wenn GPU nicht verfügbar

---

## 3. Netzwerk-Architektur (5 isolierte Netze)

```
┌─────────────────────────────────────────────────────────────┐
│                    PHYSISCHES NETZWERK                       │
│                   192.168.1.0/24 (LAN)                      │
│                                                             │
│  ┌─── HOST: 192.168.1.100 ──────────────────────────────┐  │
│  │                                                       │  │
│  │  ┌─ mcp-edge-net (172.20.0.0/24) ──────────────┐    │  │
│  │  │  nginx (Reverse Proxy + Dashboard)            │    │  │
│  │  │  Port 80/443 → 192.168.1.100                  │    │  │
│  │  └──────────────────────────────────────────────┘    │  │
│  │         │                                             │  │
│  │  ┌─ mcp-app-net (172.20.1.0/24) ──────────────┐     │  │
│  │  │  keycloak, n8n, zammad, bookstack,           │     │  │
│  │  │  vaultwarden, meshcentral, guacamole         │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-data-net (172.20.2.0/24) ─────────────┐     │  │
│  │  │  postgresql, redis, pgvector, elasticsearch  │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-sec-net (172.20.3.0/24) ──────────────┐     │  │
│  │  │  openbao (Secrets), Security-Tooling         │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-ai-net (172.20.4.0/24) ──────────────┐      │  │
│  │  │  ollama (GPU), litellm, langchain-worker,   │      │  │
│  │  │  ai-gateway, pgvector (RAG)                  │      │  │
│  │  │  ⚠ NIEMALS nach außen exponieren!            │      │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │                                                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Regel:** Nur `mcp-edge-net` ist vom LAN erreichbar. Alles andere ist intern.

---

## 4. Stack-Übersicht (32 Container)

### 4.1 Core Stack (Basis-Infrastruktur)

| Container          | Image                  | Aufgabe                        | Netzwerk(e)              |
|--------------------|------------------------|--------------------------------|--------------------------|
| mcp-postgres       | postgres:16            | Zentrale Datenbank             | mcp-data-net             |
| mcp-redis          | redis:7                | Cache & Queue                  | mcp-data-net             |
| mcp-pgvector       | pgvector/pgvector:pg16 | Vektor-DB für RAG              | mcp-data-net, mcp-ai-net|
| mcp-openbao        | openbao/openbao        | Secrets Management             | mcp-sec-net, mcp-app-net|
| mcp-nginx          | nginx:alpine           | Reverse Proxy + Dashboard      | mcp-edge-net, mcp-app-net|
| mcp-keycloak       | keycloak/keycloak      | Identity & MFA                 | mcp-app-net, mcp-data-net|
| mcp-n8n            | n8nio/n8n              | Workflow-Automatisierung       | mcp-app-net, mcp-data-net|

### 4.2 Ops Stack (Betrieb & Dokumentation)

| Container              | Image                    | Aufgabe                    | Netzwerk(e)              |
|------------------------|--------------------------|----------------------------|--------------------------|
| mcp-zammad-rails       | zammad/zammad            | Ticketsystem (Web)         | mcp-app-net, mcp-data-net|
| mcp-zammad-websocket   | zammad/zammad            | Ticketsystem (WebSocket)   | mcp-app-net              |
| mcp-zammad-worker      | zammad/zammad            | Ticketsystem (Background)  | mcp-app-net, mcp-data-net|
| mcp-elasticsearch      | elasticsearch:8          | Zammad Volltextsuche       | mcp-data-net             |
| mcp-bookstack          | lscr.io/linuxserver/bookstack | Wiki & Dokumentation | mcp-app-net, mcp-data-net|
| mcp-vaultwarden        | vaultwarden/server       | Passwort-Manager           | mcp-app-net              |

### 4.3 Telemetry Stack (Monitoring & Logging)

| Container          | Image                       | Aufgabe                          | Netzwerk(e)              |
|--------------------|-----------------------------|----------------------------------|--------------------------|
| mcp-zabbix-server  | zabbix/zabbix-server-pgsql  | Monitoring-Engine                | mcp-app-net, mcp-data-net|
| mcp-zabbix-web     | zabbix/zabbix-web-nginx-pgsql| Zabbix Web-UI                   | mcp-app-net              |
| mcp-grafana        | grafana/grafana             | Dashboards & Visualisierung      | mcp-app-net, mcp-data-net|
| mcp-loki           | grafana/loki                | Log-Aggregation                  | mcp-data-net             |
| mcp-alloy          | grafana/alloy               | Log/Metrik-Collector             | mcp-app-net, mcp-data-net|
| mcp-uptime-kuma    | louislam/uptime-kuma        | Verfügbarkeits-Monitoring        | mcp-app-net              |

### 4.4 Remote Stack (Fernwartung)

| Container          | Image                  | Aufgabe                        | Netzwerk(e)              |
|--------------------|------------------------|--------------------------------|--------------------------|
| mcp-meshcentral    | meshcentral/meshcentral| Remote Desktop & Management    | mcp-app-net              |
| mcp-guacamole      | guacamole/guacamole    | Web-basierter Remote-Zugang    | mcp-app-net              |
| mcp-guacd          | guacamole/guacd        | Guacamole Proxy Daemon         | mcp-app-net              |

### 4.5 AI Stack (Lokale KI-Engine)

| Container          | Image                  | Aufgabe                           | Netzwerk(e)              |
|--------------------|------------------------|-----------------------------------|--------------------------|
| mcp-ollama         | ollama/ollama          | LLM-Inferenz (GPU)               | mcp-ai-net               |
| mcp-litellm        | ghcr.io/berriai/litellm| KI-Gateway / Router              | mcp-ai-net, mcp-app-net  |
| mcp-langchain      | custom build           | KI-Pipeline Worker                | mcp-ai-net, mcp-data-net |
| mcp-ai-gateway     | custom build           | API für interne KI-Anfragen       | mcp-ai-net, mcp-app-net  |
| mcp-diun           | crazymax/diun          | Docker Image Update Watcher       | mcp-app-net              |

---

## 5. Datenfluss — Alles fließt zur KI

```
┌──────────────────────────────────────────────────────────────────┐
│                     SIGNALQUELLEN                                │
│                                                                  │
│  🖨️ Drucker ──┐                                                 │
│  🖥️ Server ───┤                                                 │
│  🌐 DNS ──────┤     ┌──────────┐     ┌──────────┐              │
│  📡 DHCP ─────┼────→│  Zabbix  │────→│   n8n    │              │
│  🔒 Security ─┤     │ (Monitor)│     │(Workflow)│              │
│  📊 Logs ─────┤     └──────────┘     └────┬─────┘              │
│  🔔 Alerts ───┘           │               │                     │
│                           │               ▼                     │
│                    ┌──────┴──────┐  ┌───────────┐               │
│                    │   Grafana   │  │ KI-Pipeline│               │
│                    │   + Loki    │  │ (LangChain)│               │
│                    │ (Dashboard) │  └─────┬─────┘               │
│                    └─────────────┘        │                     │
│                                          ▼                     │
│                              ┌─────────────────┐               │
│                              │  Ollama (RTX     │               │
│                              │  4070 / lokal)   │               │
│                              │                  │               │
│                              │ • Analyse        │               │
│                              │ • Root Cause     │               │
│                              │ • Ticket-Entwurf │               │
│                              │ • Vorhersage     │               │
│                              └────────┬────────┘               │
│                                       │                        │
│                    ┌──────────────────┬┘                        │
│                    ▼                  ▼                         │
│              ┌──────────┐     ┌────────────┐                   │
│              │  Zammad   │     │  pgvector   │                  │
│              │ (Tickets) │     │ (Wissen/RAG)│                  │
│              └──────────┘     └────────────┘                   │
└──────────────────────────────────────────────────────────────────┘
```

### 5.1 Praxis-Beispiel: Drucker-Überwachung

**Szenario:** Netzwerkdrucker `192.168.1.50` hat Papierstau

1. **Zabbix** erkennt SNMP-Trap oder Status-Änderung vom Drucker
2. **n8n** Workflow wird getriggert: „Drucker-Alert empfangen"
3. **Kontexterfassung**: n8n sammelt letzte Metriken, Toner-Status, Fehlerhistorie
4. **RAG-Abruf**: pgvector findet ähnliche Drucker-Incidents aus der Vergangenheit
5. **KI-Analyse**: Ollama bewertet → „Papierstau, Fach 2, wiederkehrend seit 3 Tagen"
6. **Ticket**: Zammad-Ticket wird automatisch erstellt:
   - Titel: `[DRUCKER] HP LaserJet 402 - Wiederkehrender Papierstau Fach 2`
   - Priorität: Mittel
   - Kategorie: Hardware → Drucker
   - Empfohlene Maßnahme: „Einzugsrolle Fach 2 prüfen/reinigen"
   - Historien-Referenz: Link zu letztem ähnlichen Incident
7. **Wissen**: Nach Lösung → Ticket wird in RAG-Datenbank eingespeist

### 5.2 Was wird überwacht?

| Bereich        | Was                                          | Wie                              | → KI-Aktion                        |
|----------------|----------------------------------------------|----------------------------------|-------------------------------------|
| **Drucker**    | Status, Toner, Papierstau, Seitenzähler      | SNMP über Zabbix                 | Ticket + Vorhersage Tonerwechsel    |
| **Security**   | Failed Logins, Port-Scans, Cert-Ablauf       | Zabbix + Logs → Loki            | Sicherheits-Ticket + Risikobewertung|
| **DNS intern** | Auflösung, Latenzen, Fehler                  | Zabbix DNS-Checks               | Alert bei Anomalien                  |
| **DHCP**       | Lease-Pool, Konflikte, unbekannte Geräte     | Zabbix + Log-Parsing            | Ticket bei Pool-Erschöpfung         |
| **Server**     | CPU, RAM, Disk, Services, Docker-Health       | Zabbix Agent + Alloy            | Proaktives Ticket vor Ausfall        |
| **Netzwerk**   | Ping, Bandbreite, Paketverlust               | Zabbix + Uptime-Kuma            | Eskalation bei Ausfall               |
| **Container**  | Health, Restart-Count, Logs, Resource-Usage   | Docker API + Alloy → Loki       | Auto-Restart oder Ticket             |
| **Zertifikate**| Ablaufdatum TLS/SSL                          | Zabbix + Uptime-Kuma            | Ticket 30/14/7 Tage vor Ablauf       |

---

## 6. Einheitliches Dashboard (HTTP)

### Zugang

```
http://192.168.1.100        → MCP Dashboard (Hauptseite)
http://192.168.1.100/grafana    → Grafana (Metriken & Logs)
http://192.168.1.100/tickets    → Zammad (Ticketsystem)
http://192.168.1.100/monitor    → Zabbix (Monitoring)
http://192.168.1.100/wiki       → BookStack (Dokumentation)
http://192.168.1.100/status     → Uptime-Kuma (Verfügbarkeit)
http://192.168.1.100/vault      → Vaultwarden (Passwörter)
http://192.168.1.100/auth       → Keycloak (Identity/SSO)
http://192.168.1.100/auto       → n8n (Automatisierung)
http://192.168.1.100/remote     → MeshCentral (Fernwartung)
http://192.168.1.100/guac       → Guacamole (Remote Desktop)
```

### Dashboard-Startseite

Die nginx-Startseite (`/`) zeigt ein einheitliches Dashboard mit:

- **System-Gesundheit**: alle 32 Container grün/gelb/rot
- **Letzte KI-Aktionen**: die letzten 10 KI-generierten Tickets
- **Aktive Alarme**: aus Zabbix + Uptime-Kuma
- **KI-Konfidenz-Übersicht**: High/Medium/Low Verteilung
- **Schnellzugriff**: Kacheln zu allen Diensten
- **Drucker-Status**: Live-Übersicht aller überwachten Drucker

---

## 7. Installations-Skript (`mcp-install.sh`)

### Philosophie

> **Ein Befehl. Alles läuft. Oder es stoppt sofort mit klarem Fehlerprotokoll.**

```bash
sudo bash scripts/mcp-install.sh
```

### Phasen-Modell (Gate-System)

Das Skript durchläuft **6 Phasen**. Jede Phase hat einen **Gate-Check**. Wenn ein Gate fehlschlägt, stoppt das Skript sofort und schreibt die letzten 100 Log-Zeilen in eine Fehlerdatei.

```
Phase 1: Preflight     →  Gate 1  →  ✅ oder ❌ STOP
Phase 2: Environment    →  Gate 2  →  ✅ oder ❌ STOP
Phase 3: Core Stack     →  Gate 3  →  ✅ oder ❌ STOP
Phase 4: Ops Stack      →  Gate 4  →  ✅ oder ❌ STOP
Phase 5: Telemetry      →  Gate 5  →  ✅ oder ❌ STOP
Phase 6: AI Stack       →  Gate 6  →  ✅ oder ❌ STOP
```

### Phase 1: Preflight-Checks

```
□ Docker Engine installiert und läuft
□ Docker Compose Plugin vorhanden (v2+)
□ NVIDIA-Treiber installiert (nvidia-smi funktioniert)
□ NVIDIA Container Toolkit installiert
□ Mindestens 28 GB RAM frei
□ Mindestens 100 GB Speicher frei
□ Benötigte Ports frei (80, 443, 5432, 6379, ...)
□ .env Datei vorhanden und valide
□ Alle Docker-Images lokal vorhanden (kein Pull nötig!)
□ GPU erkannt und nutzbar für Docker
```

### Phase 2: Environment-Setup

```
□ Docker-Netzwerke erstellt (5 Netze)
□ Docker-Volumes erstellt
□ Secrets generiert (Passwörter, API-Keys)
□ Konfigurationsdateien generiert
□ nginx-Konfiguration mit lokaler IP
□ SSL-Zertifikate generiert (Self-Signed für lokal)
□ /etc/hosts Einträge gesetzt
```

### Phase 3: Core Stack

```
□ PostgreSQL gestartet + Datenbanken erstellt
□ Redis gestartet + erreichbar
□ pgvector gestartet + Erweiterung geladen
□ OpenBao gestartet + initialized
□ nginx gestartet + alle Proxy-Pfade konfiguriert
□ Keycloak gestartet + Admin-Login funktioniert
□ n8n gestartet + Healthcheck OK
```

### Phase 4: Ops Stack

```
□ Elasticsearch gestartet + Cluster grün
□ Zammad (Rails/WebSocket/Worker) gestartet + UI lädt
□ BookStack gestartet + Login-Seite erreichbar
□ Vaultwarden gestartet + Web-Vault erreichbar
```

### Phase 5: Telemetry Stack

```
□ Zabbix Server gestartet + verbunden mit PostgreSQL
□ Zabbix Web gestartet + Login möglich
□ Grafana gestartet + Datasources konfiguriert
□ Loki gestartet + /ready = OK
□ Alloy gestartet + Logs fließen zu Loki
□ Uptime-Kuma gestartet + Dashboard erreichbar
```

### Phase 6: AI Stack

```
□ Ollama gestartet + GPU erkannt
□ KI-Modell geladen (z.B. mistral:7b)
□ LiteLLM Gateway gestartet + /health OK
□ LangChain Worker gestartet + verbunden mit pgvector
□ AI Gateway gestartet + Test-Prompt beantwortet
□ n8n KI-Workflows aktiviert
□ Ende-zu-Ende Test: Fake-Alert → KI-Analyse → Ticket erstellt
```

### Fehlerbehandlung

Wenn **irgendein Gate fehlschlägt**:

1. Skript stoppt **sofort** — kein Weiter zur nächsten Phase
2. Fehlerprotokoll wird geschrieben nach: `logs/mcp-install-error-<TIMESTAMP>.log`
3. Inhalt des Fehlerprotokolls:
   - Welche Phase fehlgeschlagen ist
   - Welcher Gate-Check fehlgeschlagen ist
   - Die letzten **100 Zeilen** aus den relevanten Container-Logs
   - Docker-Status aller Container (`docker ps -a`)
   - System-Resourcen (RAM, Disk, GPU)
   - Vorgeschlagene Lösung (wenn bekannt)
4. Zusammenfassung wird auf dem Terminal angezeigt:

```
╔══════════════════════════════════════════════════════════════╗
║  ❌  MCP INSTALLATION GESTOPPT                              ║
║                                                              ║
║  Phase:     4 — Ops Stack                                    ║
║  Gate:      Zammad UI lädt nicht                             ║
║  Ursache:   Assets 404 — RAILS_SERVE_STATIC_FILES fehlt     ║
║                                                              ║
║  Fehlerlog: logs/mcp-install-error-20260217-143022.log       ║
║  Container: docker logs mcp-zammad-rails --tail 100          ║
║                                                              ║
║  → Fehler korrigieren, dann erneut starten:                  ║
║    sudo bash scripts/mcp-install.sh --resume-from phase4     ║
╚══════════════════════════════════════════════════════════════╝
```

### Wiederaufnahme

```bash
# Ab der fehlgeschlagenen Phase weitermachen:
sudo bash scripts/mcp-install.sh --resume-from phase4

# Komplett neu starten:
sudo bash scripts/mcp-install.sh --clean

# Nur bestimmte Phase testen:
sudo bash scripts/mcp-install.sh --only phase6
```

---

## 8. Sicherheitsarchitektur

### Netzwerk-Segmentierung

```
Internet ──── ✘ BLOCKIERT ✘ ──── MCP Host
                                    │
LAN (192.168.1.0/24) ──── nur Port 80/443 ──── mcp-edge-net
                                                     │
                                              mcp-app-net (intern)
                                                     │
                                              mcp-data-net (DB only)
                                                     │
                                              mcp-sec-net (Secrets)
                                                     │
                                              mcp-ai-net (KI, isoliert)
```

### Zugriffskontrolle

| Ebene           | Maßnahme                                              |
|-----------------|-------------------------------------------------------|
| **Netzwerk**    | 5 isolierte Docker-Bridge-Netze, kein Internet-Zugang |
| **Identity**    | Keycloak SSO mit MFA für alle Web-Dienste             |
| **Secrets**     | OpenBao für alle Passwörter & API-Keys                |
| **Passwörter**  | Auto-generiert, 32+ Zeichen, nie im Klartext          |
| **TLS**         | Self-Signed intern, alle Dienste über HTTPS (nginx)   |
| **Container**   | Read-Only Filesystems wo möglich, no-new-privileges   |
| **Logs**        | Alle Zugriffe geloggt → Loki → KI-Analyse             |
| **KI-Gateway**  | Nur aus mcp-ai-net erreichbar, niemals öffentlich     |

### Was die KI sicherheitstechnisch überwacht

- Failed SSH/Login-Versuche → Ticket bei Schwellwert
- Neue/unbekannte Geräte im Netzwerk (DHCP) → Ticket
- DNS-Anomalien (ungewöhnliche Abfragen) → Ticket
- Zertifikate kurz vor Ablauf → Ticket mit Countdown
- Container-Neustarts (CrashLoop) → Analyse + Ticket
- Disk-/RAM-Trends → Vorhersage + proaktives Ticket
- Port-Scan-Erkennung → Sicherheits-Ticket sofort

---

## 9. KI-Konfiguration

### Modell-Strategie

```yaml
primary_model: "mistral:7b-instruct-v0.3-q4_K_M"
fallback_model: "llama3:8b-instruct-q4_K_M"
embedding_model: "nomic-embed-text"

inference:
  device: "cuda"          # RTX 4070
  gpu_layers: 35          # Alle Layer auf GPU
  context_window: 8192
  temperature: 0.1        # Niedrig für konsistente Analysen
  max_tokens: 2048

rag:
  vector_db: "pgvector"
  chunk_size: 512
  chunk_overlap: 50
  top_k: 5                # Top 5 ähnliche Dokumente
  similarity_threshold: 0.7
```

### Prompt-Architektur

Jeder KI-Aufruf folgt einem strukturierten Prompt-Template:

```
SYSTEM: Du bist ein IT-Operations-Analyst. Analysiere den folgenden
        Alert und erstelle einen strukturierten Incident-Bericht.
        Antworte auf Deutsch. Sei präzise und technisch korrekt.

KONTEXT:
- Alert-Typ: {alert_type}
- Quelle: {source}
- Zeitstempel: {timestamp}
- Aktuelle Metriken: {metrics}
- Letzte 10 Log-Zeilen: {logs}

HISTORISCH (RAG):
- Ähnliche Incidents: {rag_results}

AUFGABE:
1. Root-Cause-Analyse (1-2 Sätze)
2. Auswirkung (Gering/Mittel/Hoch/Kritisch)
3. Empfohlene Maßnahme (konkrete Schritte)
4. Konfidenz (High/Medium/Low)

FORMAT: JSON
```

### Konfidenz-Matrix

| Konfidenz | KI-Aktion                    | Mensch                   |
|-----------|------------------------------|--------------------------|
| **High**  | Ticket erstellen + zuweisen  | Wird benachrichtigt      |
| **Medium**| Ticket-Entwurf erstellen     | Muss prüfen & freigeben  |
| **Low**   | Nur Alert senden             | Übernimmt komplett       |

---

## 10. Offline-Betrieb — Kein Internet

### Was bedeutet „kein Internet"?

- **Keine Docker-Pulls** zur Laufzeit → alle Images vorher lokal gespeichert
- **Keine externen APIs** → Ollama ersetzt OpenAI/Claude
- **Keine Cloud-Datenbanken** → PostgreSQL + pgvector lokal
- **Keine externen NTP** → lokaler NTP oder Host-Zeit
- **Keine Update-Checks** → Diun nur für lokale Registry (optional)
- **Keine Telemetrie** → kein Abfluss an Dritte

### Vorbereitung für Offline-Deployment

```bash
# 1. Auf einer Maschine MIT Internet alle Images pullen:
bash scripts/mcp-pull-images.sh

# 2. Images als tar exportieren:
bash scripts/mcp-export-images.sh → images/mcp-images-v7.tar.gz

# 3. Auf Zielmaschine (OHNE Internet) importieren:
bash scripts/mcp-import-images.sh images/mcp-images-v7.tar.gz

# 4. KI-Modelle separat exportieren:
bash scripts/mcp-export-models.sh → models/ollama-models.tar.gz

# 5. Dann Installation starten:
sudo bash scripts/mcp-install.sh
```

---

## 11. Dateistruktur

```
mcp-v7/
├── plan.md                          ← DIESES DOKUMENT
├── README.md                        ← Englische Projektbeschreibung
├── README.de.md                     ← Deutsche Projektbeschreibung
├── SECURITY.md                      ← Sicherheitsrichtlinie
├── .env.example                     ← Vorlage für Umgebungsvariablen
├── .env                             ← Lokale Konfiguration (NICHT committen!)
├── Makefile                         ← Shortcuts (make up, make down, etc.)
│
├── compose/
│   ├── core/
│   │   └── docker-compose.yml       ← PostgreSQL, Redis, pgvector, OpenBao, nginx, Keycloak, n8n
│   ├── ops/
│   │   └── docker-compose.yml       ← Zammad, Elasticsearch, BookStack, Vaultwarden
│   ├── telemetry/
│   │   └── docker-compose.yml       ← Zabbix, Grafana, Loki, Alloy, Uptime-Kuma
│   ├── remote/
│   │   └── docker-compose.yml       ← MeshCentral, Guacamole
│   └── ai/
│       └── docker-compose.yml       ← Ollama, LiteLLM, LangChain, AI-Gateway
│
├── config/
│   ├── nginx/
│   │   ├── nginx.conf               ← Haupt-Konfiguration
│   │   ├── conf.d/                   ← Proxy-Configs pro Dienst
│   │   └── dashboard/               ← HTML/CSS/JS für Startseite
│   ├── grafana/
│   │   ├── datasources.yml
│   │   └── dashboards/
│   ├── loki/
│   │   └── loki-config.yml
│   ├── zabbix/
│   │   └── zabbix_agent2.conf
│   ├── alloy/
│   │   └── config.alloy
│   ├── keycloak/
│   │   └── realm-export.json
│   ├── n8n/
│   │   └── workflows/               ← KI-Pipeline Workflows
│   └── ai/
│       ├── prompts/                  ← Strukturierte Prompt-Templates
│       ├── models.yml                ← LiteLLM Modell-Routing
│       └── rag-config.yml            ← RAG-Pipeline Konfiguration
│
├── scripts/
│   ├── mcp-install.sh               ← Haupt-Installationsskript
│   ├── mcp-start.sh                 ← Orchestrierung (Start aller Stacks)
│   ├── mcp-stop.sh                  ← Geordnetes Herunterfahren
│   ├── mcp-status.sh                ← Status aller Container
│   ├── mcp-pull-images.sh           ← Alle Images pullen (online)
│   ├── mcp-export-images.sh         ← Images als tar exportieren
│   ├── mcp-import-images.sh         ← Images aus tar importieren
│   ├── mcp-export-models.sh         ← KI-Modelle exportieren
│   ├── mcp-backup.sh                ← Vollständiges Backup
│   ├── mcp-restore.sh               ← Wiederherstellung aus Backup
│   └── init-db.sh                   ← PostgreSQL Datenbank-Initialisierung
│
├── tests/
│   ├── smoke-test.sh                ← Basis-Gesundheitscheck
│   ├── ai-pipeline-test.sh          ← KI Ende-zu-Ende Test
│   └── security-test.sh             ← Sicherheits-Validierung
│
├── logs/                             ← Fehlerprotokolle
│   └── mcp-install-error-*.log
│
├── images/                           ← Exportierte Docker-Images (für Offline)
│   └── mcp-images-v7.tar.gz
│
├── models/                           ← Exportierte KI-Modelle (für Offline)
│   └── ollama-models.tar.gz
│
└── docs/
    ├── assets/
    │   └── mcp-logo.png
    ├── architektur.md
    ├── deployment-runbook.md
    └── troubleshooting.md
```

---

## 12. Bekannte Fehlermuster & Lösungen

> Aus Phase 2 und Phase 4 Installationstests dokumentiert.

| # | Problem | Ursache | Lösung | Datei |
|---|---------|---------|--------|-------|
| 1 | PostgreSQL: `permission denied to create database` | Rolle ohne CREATEDB | `ALTER ROLE zammad CREATEDB;` in init-db.sh | scripts/init-db.sh |
| 2 | PostgreSQL: `database "mcp_admin" does not exist` | DB fehlt | `CREATE DATABASE mcp_admin OWNER mcp_admin;` | scripts/init-db.sh |
| 3 | Zammad: Assets 404, Ladebildschirm hängt | `RAILS_SERVE_STATIC_FILES` fehlt | In compose/ops env hinzufügen | compose/ops/docker-compose.yml |
| 4 | Loki: CrashLoop `compactor.delete-request-store` | Retention ohne Compactor-Config | `retention_enabled: false` | config/loki/loki-config.yml |
| 5 | Zabbix: `fe_sendauth: no password supplied` | Bind-Mount überschreibt env-Vars | Config-Bind-Mount entfernen | compose/telemetry/docker-compose.yml |
| 6 | n8n: Healthcheck `Connection refused` | localhost → IPv6, start_period zu kurz | `127.0.0.1`, start_period 120s | compose/core/docker-compose.yml |
| 7 | Guacamole: 404 auf `/` | Context-Path ist `/guacamole/` | URL korrigieren | tests/smoke-test.sh |
| 8 | MeshCentral: Empty reply | HTTPS auf Port 4430, nicht HTTP | `https://` verwenden | tests/smoke-test.sh |
| 9 | Orphan Containers Warning | Kein einheitlicher Projektname | `COMPOSE_PROJECT_NAME=mcp` | .env |

### Design-Patterns (Fehler vermeiden)

1. **Kein Bind-Mount für Configs die env-Vars brauchen** — Bind-Mounts überschreiben alles
2. **Immer `127.0.0.1` statt `localhost`** in Healthchecks (IPv6-Problem)
3. **`start_period: 120s`** für Services mit Datenbank-Migrationen
4. **Context-Pfade prüfen** bevor Healthchecks geschrieben werden
5. **Protokoll prüfen** (HTTP vs HTTPS) bei jedem Service
6. **`COMPOSE_PROJECT_NAME=mcp`** immer in .env setzen

---

## 13. Erfolgskriterien

Das System gilt als **produktionsreif** wenn:

- [ ] Alle 32 Container laufen mit STATUS=healthy
- [ ] Kein Container startet neu (0 Restarts in 1 Stunde)
- [ ] Dashboard unter `http://<IP>` erreichbar und zeigt alle Dienste
- [ ] Zabbix überwacht mindestens ein Gerät (Drucker/Server)
- [ ] KI-Pipeline funktioniert: Fake-Alert → Analyse → Ticket in Zammad
- [ ] RAG funktioniert: Gelöstes Ticket wird bei ähnlichem Alert gefunden
- [ ] Kein einziger ausgehender Netzwerk-Request (verifiziert via tcpdump)
- [ ] Keycloak SSO funktioniert für Grafana + Zammad
- [ ] Backup + Restore erfolgreich getestet
- [ ] Installationsskript läuft fehlerfrei durch alle 6 Phasen

---

## 14. Regeln für KI-Assistenten

> **Wenn du (Claude, GPT, Copilot) an diesem Projekt arbeitest, halte dich an diese Regeln:**

1. **Lies `plan.md` zuerst** — immer. Vor jedem Code.
2. **Kein Internet-Zugriff** — schreibe keinen Code der externe APIs, CDNs oder Paketmanager braucht
3. **Docker-only** — alles läuft in Containern, kein `apt install` auf dem Host (außer Docker/NVIDIA)
4. **GPU beachten** — Ollama MUSS die RTX 4070 nutzen, kein CPU-Fallback im Normalbetrieb
5. **Gate-System respektieren** — wenn ein Test fehlschlägt, nicht weitermachen
6. **Fehlerlog schreiben** — immer die letzten 100 Zeilen bei Fehler
7. **Deutsch** — Tickets, Logs und KI-Ausgaben auf Deutsch
8. **Sicherheit** — keine Secrets in Code, keine Ports nach außen, kein Root wo nicht nötig
9. **Compose-Struktur** — 5 separate docker-compose.yml in compose/, nicht eine riesige Datei
10. **Testen** — jede Änderung muss durch den relevanten Gate-Check validiert werden

---

<p align="center">
  <strong>MCP v7 — Managed Control Platform</strong><br/>
  <em>Lokal. Sicher. Automatisiert. Intelligent.</em><br/><br/>
  <code>sudo bash scripts/mcp-install.sh</code>
</p>
