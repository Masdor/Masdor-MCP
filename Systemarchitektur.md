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
| Core         | 8         | ~5 GB     |
| Ops          | 8         | ~4 GB     |
| Telemetry    | 8         | ~4 GB     |
| Remote       | 3         | ~1 GB     |
| AI           | 5         | ~12 GB    |
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
│  │  │  vaultwarden, meshcentral, guacamole,        │     │  │
│  │  │  portainer, ntfy, uptime-kuma                │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-data-net (172.20.2.0/24) ─────────────┐     │  │
│  │  │  postgresql, redis, pgvector, elasticsearch  │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-sec-net (172.20.3.0/24) ──────────────┐     │  │
│  │  │  openbao (Secrets), crowdsec (IDS)           │     │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │         │                                             │  │
│  │  ┌─ mcp-ai-net (172.20.4.0/24) ──────────────┐      │  │
│  │  │  ollama (GPU), litellm, langchain-worker,   │      │  │
│  │  │  ai-gateway, redis-queue, pgvector (RAG)    │      │  │
│  │  │  ⚠ NIEMALS nach außen exponieren!            │      │  │
│  │  └──────────────────────────────────────────────┘     │  │
│  │                                                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Regel:** Nur `mcp-edge-net` ist vom LAN erreichbar. Alles andere ist intern.

---

## 4. Stack-Übersicht (32 Container)

### 4.1 Core Stack — 8 Container (Basis-Infrastruktur)

| #  | Container          | Image                  | Aufgabe                        | Netzwerk(e)              |
|----|--------------------|------------------------|--------------------------------|--------------------------|
| 1  | mcp-postgres       | postgres:16            | Zentrale Datenbank             | mcp-data-net             |
| 2  | mcp-redis          | redis:7                | Cache & Queue                  | mcp-data-net             |
| 3  | mcp-pgvector       | pgvector/pgvector:pg16 | Vektor-DB für RAG              | mcp-data-net, mcp-ai-net|
| 4  | mcp-openbao        | openbao/openbao        | Secrets Management             | mcp-sec-net, mcp-app-net|
| 5  | mcp-nginx          | nginx:alpine           | Reverse Proxy + Dashboard      | mcp-edge-net, mcp-app-net|
| 6  | mcp-keycloak       | keycloak/keycloak      | Identity & MFA                 | mcp-app-net, mcp-data-net|
| 7  | mcp-n8n            | n8nio/n8n              | Workflow-Automatisierung       | mcp-app-net, mcp-data-net|
| 8  | mcp-ntfy           | binwiederhier/ntfy     | Lokale Push-Benachrichtigungen | mcp-app-net              |

> **Neu: mcp-ntfy** — Ohne Internet gibt es keinen E-Mail-Versand. ntfy ist ein lokaler Benachrichtigungsdienst: Zabbix-Alerts, KI-Ticket-Status und System-Warnungen werden als Push-Nachrichten an Browser/Mobile geliefert. Alle Dienste (n8n, Zabbix, Grafana) können über eine einfache HTTP-POST-API Nachrichten senden.

### 4.2 Ops Stack — 8 Container (Betrieb & Dokumentation)

| #  | Container              | Image                         | Aufgabe                    | Netzwerk(e)              |
|----|------------------------|-------------------------------|----------------------------|--------------------------|
| 9  | mcp-zammad-rails       | zammad/zammad                 | Ticketsystem (Web)         | mcp-app-net, mcp-data-net|
| 10 | mcp-zammad-websocket   | zammad/zammad                 | Ticketsystem (WebSocket)   | mcp-app-net              |
| 11 | mcp-zammad-worker      | zammad/zammad                 | Ticketsystem (Background)  | mcp-app-net, mcp-data-net|
| 12 | mcp-elasticsearch      | elasticsearch:8               | Zammad Volltextsuche       | mcp-data-net             |
| 13 | mcp-bookstack          | lscr.io/linuxserver/bookstack | Wiki & Dokumentation       | mcp-app-net, mcp-data-net|
| 14 | mcp-vaultwarden        | vaultwarden/server            | Passwort-Manager           | mcp-app-net              |
| 15 | mcp-portainer          | portainer/portainer-ce        | Docker-Management-UI       | mcp-app-net              |
| 16 | mcp-diun               | crazymax/diun                 | Docker Image Update Watcher| mcp-app-net              |

> **Neu: mcp-portainer** — Bei 32 Containern ist ein visuelles Docker-Management unverzichtbar. Portainer zeigt Container-Status, Logs, Ressourcenverbrauch, Netzwerke und Volumes in einer Web-UI. Erreichbar über `/portainer` im Dashboard.

> **Verschoben: mcp-diun** — War fälschlicherweise im AI Stack. Diun überwacht Docker-Images auf neue Versionen — das ist eine Betriebsaufgabe, keine KI-Funktion. Im Offline-Betrieb prüft Diun gegen eine optionale lokale Registry.

### 4.3 Telemetry Stack — 8 Container (Monitoring, Logging & Sicherheitserkennung)

| #  | Container              | Image                          | Aufgabe                          | Netzwerk(e)              |
|----|------------------------|--------------------------------|----------------------------------|--------------------------|
| 17 | mcp-zabbix-server      | zabbix/zabbix-server-pgsql     | Monitoring-Engine                | mcp-app-net, mcp-data-net|
| 18 | mcp-zabbix-web         | zabbix/zabbix-web-nginx-pgsql  | Zabbix Web-UI                    | mcp-app-net              |
| 19 | mcp-grafana            | grafana/grafana                | Dashboards & Visualisierung      | mcp-app-net, mcp-data-net|
| 20 | mcp-loki               | grafana/loki                   | Log-Aggregation                  | mcp-data-net             |
| 21 | mcp-alloy              | grafana/alloy                  | Log/Metrik-Collector             | mcp-app-net, mcp-data-net|
| 22 | mcp-uptime-kuma        | louislam/uptime-kuma           | Verfügbarkeits-Monitoring        | mcp-app-net              |
| 23 | mcp-crowdsec           | crowdsecurity/crowdsec         | Intrusion Detection (IDS)        | mcp-sec-net, mcp-app-net|
| 24 | mcp-grafana-renderer   | grafana/grafana-image-renderer | PDF/Bild-Export für Berichte     | mcp-app-net              |

> **Neu: mcp-crowdsec** — Lokale Intrusion Detection. CrowdSec analysiert Logs (nginx, SSH, Zabbix) und erkennt Angriffsmuster: Brute-Force, Port-Scans, SQL-Injection-Versuche. Im Offline-Modus arbeitet es mit lokalen Szenarien (keine Cloud-Blocklisten). Erkannte Bedrohungen werden an die KI-Pipeline weitergeleitet → automatisches Sicherheits-Ticket.

> **Neu: mcp-grafana-renderer** — Generiert PDF- und PNG-Exports von Grafana-Dashboards. Nützlich für automatisierte Tagesberichte, die per ntfy oder Zammad verteilt werden. Ohne Renderer kann Grafana keine Bilder für Benachrichtigungen erzeugen.

### 4.4 Remote Stack — 3 Container (Fernwartung)

| #  | Container          | Image                  | Aufgabe                        | Netzwerk(e)              |
|----|--------------------|------------------------|--------------------------------|--------------------------|
| 25 | mcp-meshcentral    | meshcentral/meshcentral| Remote Desktop & Management    | mcp-app-net              |
| 26 | mcp-guacamole      | guacamole/guacamole    | Web-basierter Remote-Zugang    | mcp-app-net              |
| 27 | mcp-guacd          | guacamole/guacd        | Guacamole Proxy Daemon         | mcp-app-net              |

### 4.5 AI Stack — 5 Container (Lokale KI-Engine)

| #  | Container          | Image                  | Aufgabe                           | Netzwerk(e)              |
|----|--------------------|------------------------|-----------------------------------|--------------------------|
| 28 | mcp-ollama         | ollama/ollama          | LLM-Inferenz (GPU)               | mcp-ai-net               |
| 29 | mcp-litellm        | ghcr.io/berriai/litellm| KI-Gateway / Router              | mcp-ai-net, mcp-app-net  |
| 30 | mcp-langchain      | custom build           | KI-Pipeline Worker                | mcp-ai-net, mcp-data-net |
| 31 | mcp-ai-gateway     | custom build           | API für interne KI-Anfragen       | mcp-ai-net, mcp-app-net  |
| 32 | mcp-redis-queue    | redis:7-alpine         | Dedizierte Job-Queue für KI       | mcp-ai-net               |

> **Neu: mcp-redis-queue** — Separater Redis speziell für die KI-Job-Queue. Isoliert KI-Workloads vom Haupt-Redis (mcp-redis), damit KI-Batch-Verarbeitung den Cache der Kernservices nicht beeinträchtigt. Speichert: Pending-Alerts, Analyse-Ergebnisse, RAG-Anfragen in der Warteschlange.

### Container-Gesamtübersicht

```
┌───────────────────────────────────────────────────────────┐
│  STACK          │  CONTAINER  │  RAM (ca.)  │  NUMMERN    │
├───────────────────────────────────────────────────────────┤
│  Core           │     8       │    ~5 GB    │   #1 – #8   │
│  Ops            │     8       │    ~4 GB    │   #9 – #16  │
│  Telemetry      │     8       │    ~4 GB    │  #17 – #24  │
│  Remote         │     3       │    ~1 GB    │  #25 – #27  │
│  AI             │     5       │   ~12 GB    │  #28 – #32  │
├───────────────────────────────────────────────────────────┤
│  System/OS      │     —       │    ~4 GB    │      —      │
│  Reserve        │     —       │    ~2 GB    │      —      │
├───────────────────────────────────────────────────────────┤
│  GESAMT         │    32       │   ~32 GB    │   #1 – #32  │
└───────────────────────────────────────────────────────────┘
```

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
│  🛡️ CrowdSec ─────────────┘               │                     │
│                                           ▼                     │
│                    ┌─────────────┐  ┌───────────┐               │
│                    │   Grafana   │  │ KI-Pipeline│               │
│                    │   + Loki    │  │ (LangChain)│               │
│                    │ (Dashboard) │  └─────┬─────┘               │
│                    └─────────────┘        │                     │
│                                    ┌─────┴──────┐              │
│                                    │ redis-queue │              │
│                                    │ (Job-Queue) │              │
│                                    └─────┬──────┘              │
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
│                    ┌──────────┬───────┴──────┐                 │
│                    ▼          ▼              ▼                  │
│              ┌──────────┐ ┌────────────┐ ┌───────┐             │
│              │  Zammad   │ │  pgvector   │ │  ntfy │             │
│              │ (Tickets) │ │ (Wissen/RAG)│ │(Push) │             │
│              └──────────┘ └────────────┘ └───────┘             │
└──────────────────────────────────────────────────────────────────┘
```

### 5.1 Praxis-Beispiel: Drucker-Überwachung

**Szenario:** Netzwerkdrucker `192.168.1.50` hat Papierstau

1. **Zabbix** erkennt SNMP-Trap oder Status-Änderung vom Drucker
2. **n8n** Workflow wird getriggert: „Drucker-Alert empfangen"
3. **Kontexterfassung**: n8n sammelt letzte Metriken, Toner-Status, Fehlerhistorie
4. **Job-Queue**: Alert wird in `mcp-redis-queue` eingestellt zur KI-Verarbeitung
5. **RAG-Abruf**: pgvector findet ähnliche Drucker-Incidents aus der Vergangenheit
6. **KI-Analyse**: Ollama bewertet → „Papierstau, Fach 2, wiederkehrend seit 3 Tagen"
7. **Ticket**: Zammad-Ticket wird automatisch erstellt:
   - Titel: `[DRUCKER] HP LaserJet 402 - Wiederkehrender Papierstau Fach 2`
   - Priorität: Mittel
   - Kategorie: Hardware → Drucker
   - Empfohlene Maßnahme: „Einzugsrolle Fach 2 prüfen/reinigen"
   - Historien-Referenz: Link zu letztem ähnlichen Incident
8. **Benachrichtigung**: ntfy sendet Push-Nachricht an zuständigen Techniker
9. **Wissen**: Nach Lösung → Ticket wird in RAG-Datenbank eingespeist

### 5.2 Was wird überwacht?

| Bereich        | Was                                          | Wie                              | → KI-Aktion                        |
|----------------|----------------------------------------------|----------------------------------|-------------------------------------|
| **Drucker**    | Status, Toner, Papierstau, Seitenzähler      | SNMP über Zabbix                 | Ticket + Vorhersage Tonerwechsel    |
| **Security**   | Failed Logins, Port-Scans, Cert-Ablauf       | CrowdSec + Zabbix + Loki        | Sicherheits-Ticket + Risikobewertung|
| **DNS intern** | Auflösung, Latenzen, Fehler                  | Zabbix DNS-Checks               | Alert bei Anomalien                  |
| **DHCP**       | Lease-Pool, Konflikte, unbekannte Geräte     | Zabbix + Log-Parsing            | Ticket bei Pool-Erschöpfung         |
| **Server**     | CPU, RAM, Disk, Services, Docker-Health       | Zabbix Agent + Alloy            | Proaktives Ticket vor Ausfall        |
| **Netzwerk**   | Ping, Bandbreite, Paketverlust               | Zabbix + Uptime-Kuma            | Eskalation bei Ausfall               |
| **Container**  | Health, Restart-Count, Logs, Resource-Usage   | Portainer + Alloy → Loki        | Auto-Restart oder Ticket             |
| **Zertifikate**| Ablaufdatum TLS/SSL                          | Zabbix + Uptime-Kuma            | Ticket 30/14/7 Tage vor Ablauf       |
| **Intrusion**  | Brute-Force, Scans, Anomalien                | CrowdSec → Loki → KI            | Sofort-Ticket + IP-Block             |

---

## 6. Einheitliches Dashboard (HTTP)

### Zugang

```
http://192.168.1.100            → MCP Dashboard (Hauptseite)
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
http://192.168.1.100/portainer  → Portainer (Docker-Management)
http://192.168.1.100/notify     → ntfy (Benachrichtigungen)
```

### Dashboard-Startseite

Die nginx-Startseite (`/`) zeigt ein einheitliches Dashboard mit:

- **System-Gesundheit**: alle 32 Container grün/gelb/rot (Daten von Portainer API)
- **Letzte KI-Aktionen**: die letzten 10 KI-generierten Tickets
- **Aktive Alarme**: aus Zabbix + Uptime-Kuma + CrowdSec
- **KI-Konfidenz-Übersicht**: High/Medium/Low Verteilung
- **Schnellzugriff**: Kacheln zu allen 13 Diensten
- **Drucker-Status**: Live-Übersicht aller überwachten Drucker
- **Sicherheitslage**: CrowdSec-Zusammenfassung (blockierte IPs, Angriffsmuster)
- **Letzte Benachrichtigungen**: ntfy-Feed der letzten Push-Nachrichten

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
□ nginx-Konfiguration mit lokaler IP + alle 13 Proxy-Pfade
□ SSL-Zertifikate generiert (Self-Signed für lokal)
□ /etc/hosts Einträge gesetzt
```

### Phase 3: Core Stack (8 Container: #1–#8)

```
□ PostgreSQL gestartet + Datenbanken erstellt
□ Redis gestartet + erreichbar
□ pgvector gestartet + Erweiterung geladen
□ OpenBao gestartet + initialized + unsealed
□ nginx gestartet + alle 13 Proxy-Pfade konfiguriert
□ Keycloak gestartet + Admin-Login funktioniert
□ n8n gestartet + Healthcheck OK
□ ntfy gestartet + Test-Nachricht gesendet + empfangen
```

### Phase 4: Ops Stack (8 Container: #9–#16)

```
□ Elasticsearch gestartet + Cluster grün
□ Zammad (Rails/WebSocket/Worker) gestartet + UI lädt
□ BookStack gestartet + Login-Seite erreichbar
□ Vaultwarden gestartet + Web-Vault erreichbar
□ Portainer gestartet + Docker-API verbunden + UI erreichbar
□ Diun gestartet + Container-Liste erkannt
```

### Phase 5: Telemetry Stack (8 Container: #17–#24)

```
□ Zabbix Server gestartet + verbunden mit PostgreSQL
□ Zabbix Web gestartet + Login möglich
□ Grafana gestartet + Datasources konfiguriert (Loki, Zabbix, PostgreSQL)
□ Loki gestartet + /ready = OK
□ Alloy gestartet + Logs fließen zu Loki
□ Uptime-Kuma gestartet + Dashboard erreichbar
□ CrowdSec gestartet + Szenarien geladen + nginx-Bouncer aktiv
□ Grafana-Renderer gestartet + Test-Render erfolgreich
```

### Phase 6: AI Stack (5 Container: #28–#32)

```
□ Redis-Queue gestartet + erreichbar auf mcp-ai-net
□ Ollama gestartet + GPU erkannt (nvidia-smi im Container)
□ KI-Modell geladen (z.B. mistral:7b)
□ LiteLLM Gateway gestartet + /health OK
□ LangChain Worker gestartet + verbunden mit pgvector + redis-queue
□ AI Gateway gestartet + Test-Prompt beantwortet
□ n8n KI-Workflows aktiviert
□ Ende-zu-Ende Test: Fake-Alert → redis-queue → KI-Analyse → Ticket in Zammad → ntfy-Push
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
                                              mcp-sec-net (Secrets + IDS)
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
| **IDS**         | CrowdSec analysiert Logs lokal, erkennt Angriffsmuster|
| **KI-Gateway**  | Nur aus mcp-ai-net erreichbar, niemals öffentlich     |

### Was die KI sicherheitstechnisch überwacht

- Failed SSH/Login-Versuche → CrowdSec-Alert → KI-Analyse → Ticket bei Schwellwert
- Neue/unbekannte Geräte im Netzwerk (DHCP) → Ticket
- DNS-Anomalien (ungewöhnliche Abfragen) → Ticket
- Zertifikate kurz vor Ablauf → Ticket mit Countdown
- Container-Neustarts (CrashLoop) → Portainer-Daten → Analyse + Ticket
- Disk-/RAM-Trends → Vorhersage + proaktives Ticket
- Port-Scan-Erkennung → CrowdSec → Sicherheits-Ticket sofort
- Brute-Force-Angriffe → CrowdSec → automatisches IP-Banning via nginx-Bouncer

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

queue:
  broker: "mcp-redis-queue"   # Dedizierte KI-Queue (nicht mcp-redis!)
  port: 6379
  db: 0
  max_concurrent_jobs: 3      # Max 3 parallele KI-Analysen
  job_timeout: 120            # 2 Minuten pro Analyse
  retry_on_failure: true
  max_retries: 2
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
- IDS-Daten: {crowdsec_alerts}

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

| Konfidenz | KI-Aktion                    | Mensch                   | Benachrichtigung        |
|-----------|------------------------------|--------------------------|-------------------------|
| **High**  | Ticket erstellen + zuweisen  | Wird benachrichtigt      | ntfy Push (Info)        |
| **Medium**| Ticket-Entwurf erstellen     | Muss prüfen & freigeben  | ntfy Push (Aktion nötig)|
| **Low**   | Nur Alert senden             | Übernimmt komplett       | ntfy Push (Dringend)    |

---

## 10. Offline-Betrieb — Kein Internet

### Was bedeutet „kein Internet"?

- **Keine Docker-Pulls** zur Laufzeit → alle Images vorher lokal gespeichert
- **Keine externen APIs** → Ollama ersetzt OpenAI/Claude
- **Keine Cloud-Datenbanken** → PostgreSQL + pgvector lokal
- **Keine externen NTP** → lokaler NTP oder Host-Zeit
- **Keine Update-Checks** → Diun nur für lokale Registry (optional)
- **Keine Telemetrie** → kein Abfluss an Dritte
- **Keine Cloud-Blocklisten** → CrowdSec arbeitet mit lokalen Szenarien
- **Keine E-Mail** → ntfy ersetzt E-Mail-Benachrichtigungen lokal

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

# 5. CrowdSec-Szenarien lokal exportieren:
bash scripts/mcp-export-crowdsec.sh → config/crowdsec/scenarios/

# 6. Dann Installation starten:
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
│   │   └── docker-compose.yml       ← #1–#8:  PostgreSQL, Redis, pgvector, OpenBao, nginx, Keycloak, n8n, ntfy
│   ├── ops/
│   │   └── docker-compose.yml       ← #9–#16: Zammad, Elasticsearch, BookStack, Vaultwarden, Portainer, Diun
│   ├── telemetry/
│   │   └── docker-compose.yml       ← #17–#24: Zabbix, Grafana, Loki, Alloy, Uptime-Kuma, CrowdSec, Grafana-Renderer
│   ├── remote/
│   │   └── docker-compose.yml       ← #25–#27: MeshCentral, Guacamole, Guacd
│   └── ai/
│       └── docker-compose.yml       ← #28–#32: Ollama, LiteLLM, LangChain, AI-Gateway, Redis-Queue
│
├── config/
│   ├── nginx/
│   │   ├── nginx.conf               ← Haupt-Konfiguration
│   │   ├── conf.d/                   ← 13 Proxy-Configs (grafana.conf, tickets.conf, portainer.conf, ...)
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
│   ├── ntfy/
│   │   └── server.yml               ← ntfy-Konfiguration (Topics, Auth)
│   ├── crowdsec/
│   │   ├── acquis.yml               ← Log-Quellen (nginx, SSH, etc.)
│   │   └── scenarios/               ← Lokale Erkennungsregeln
│   ├── portainer/
│   │   └── portainer-data/          ← Portainer Persistenz
│   └── ai/
│       ├── prompts/                  ← Strukturierte Prompt-Templates
│       ├── models.yml                ← LiteLLM Modell-Routing
│       └── rag-config.yml            ← RAG-Pipeline Konfiguration
│
├── scripts/
│   ├── mcp-install.sh               ← Haupt-Installationsskript (6 Phasen + Gates)
│   ├── mcp-start.sh                 ← Orchestrierung (Start aller 5 Stacks in Reihenfolge)
│   ├── mcp-stop.sh                  ← Geordnetes Herunterfahren (AI → Remote → Telemetry → Ops → Core)
│   ├── mcp-status.sh                ← Status aller 32 Container (tabellarisch)
│   ├── mcp-pull-images.sh           ← Alle 32 Images pullen (online)
│   ├── mcp-export-images.sh         ← Images als tar exportieren
│   ├── mcp-import-images.sh         ← Images aus tar importieren
│   ├── mcp-export-models.sh         ← KI-Modelle exportieren
│   ├── mcp-export-crowdsec.sh       ← CrowdSec-Szenarien exportieren
│   ├── mcp-backup.sh                ← Vollständiges Backup
│   ├── mcp-restore.sh               ← Wiederherstellung aus Backup
│   └── init-db.sh                   ← PostgreSQL Datenbank-Initialisierung
│
├── tests/
│   ├── smoke-test.sh                ← Basis-Gesundheitscheck (alle 32 Container)
│   ├── ai-pipeline-test.sh          ← KI Ende-zu-Ende Test (Alert → Queue → Analyse → Ticket → Push)
│   └── security-test.sh             ← Sicherheits-Validierung (CrowdSec + Netzwerktrennung)
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
7. **Separate Redis-Instanzen** — mcp-redis für Cache, mcp-redis-queue für KI-Jobs
8. **CrowdSec ohne Internet** — `online_client.enabled: false` in config setzen

---

## 13. Erfolgskriterien

Das System gilt als **produktionsreif** wenn:

- [ ] Alle 32 Container laufen mit STATUS=healthy
- [ ] Kein Container startet neu (0 Restarts in 1 Stunde)
- [ ] Dashboard unter `http://<IP>` erreichbar und zeigt alle 13 Dienste
- [ ] Alle 13 Proxy-Pfade in nginx funktionieren (/grafana, /tickets, /portainer, ...)
- [ ] Portainer zeigt alle 32 Container mit korrektem Status
- [ ] Zabbix überwacht mindestens ein Gerät (Drucker/Server)
- [ ] KI-Pipeline funktioniert: Fake-Alert → redis-queue → Analyse → Ticket in Zammad
- [ ] ntfy-Benachrichtigung wird bei Ticket-Erstellung empfangen
- [ ] RAG funktioniert: Gelöstes Ticket wird bei ähnlichem Alert gefunden
- [ ] CrowdSec erkennt simulierten Brute-Force-Angriff
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
11. **32 Container** — genau 32, nummeriert #1–#32, aufgeteilt in 5 Stacks (8+8+8+3+5)
12. **Zwei Redis** — mcp-redis (#2, Cache) und mcp-redis-queue (#32, KI-Jobs) niemals verwechseln
13. **CrowdSec offline** — `online_client.enabled: false`, nur lokale Szenarien
14. **ntfy statt E-Mail** — alle Benachrichtigungen über ntfy, niemals SMTP konfigurieren

---

<p align="center">
  <strong>MCP v7 — Managed Control Platform</strong><br/>
  <em>Lokal. Sicher. Automatisiert. Intelligent.</em><br/><br/>
  <code>sudo bash scripts/mcp-install.sh</code>
</p>
