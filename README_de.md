<p align="center">
  <img src="docs/assets/mcp-logo.png" alt="MCP Logo" width="180"/>
</p>

<h1 align="center">MCP – Managed Control Platform</h1>

<p align="center">
  <strong>KI-gestütztes IT-Operations-Center</strong><br/>
  <em>Lokal. Sicher. Automatisiert. Entwickelt für MSP-tauglichen Betrieb.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-7.x-blue?style=flat-square" alt="Version"/>
  <img src="https://img.shields.io/badge/Status-Beta-orange?style=flat-square" alt="Status"/>
  <img src="https://img.shields.io/badge/Container-32-green?style=flat-square" alt="Container"/>
  <img src="https://img.shields.io/badge/KI-Ollama%20%2B%20RAG-purple?style=flat-square" alt="KI"/>
  <img src="https://img.shields.io/badge/Betrieb-100%25%20Self--Hosted-black?style=flat-square" alt="Self-hosted"/>
  <img src="https://img.shields.io/badge/Lizenz-Proprietär-lightgrey?style=flat-square" alt="Lizenz"/>
</p>

<p align="center">
  🇬🇧 <a href="README.md">English</a> · 🇩🇪 <strong>Deutsch</strong> · 🇸🇦 <a href="README_ar.md">العربية</a>
</p>

> **Projektstatus:** MCP v7 befindet sich im **Beta-Stadium**. Die Plattform ist funktionsfähig und wird aktiv in Lab-Umgebungen validiert. Produktiveinsatz erfordert eine individuelle Bewertung und schriftliche Lizenzvereinbarung.

---

## Was ist MCP?

**MCP (Managed Control Platform)** ist eine vollständig selbst gehostete IT-Operations-Plattform, die Monitoring-Signale, Logs und Sicherheitsbefunde in **umsetzbare Incident-Tickets** verwandelt – automatisch.

MCP v7 läuft als **containerisierte Plattform (32 Container)** über **5 isolierte Docker-Netzwerke** und kombiniert bewährte Open-Source-Betriebstools (Monitoring, Logging, Ticketing, Wiki, Fernwartung) mit einem **lokalen KI-Stack** (Ollama + RAG + pgvector), der folgende Aufgaben übernimmt:

- Event-Korrelation (Metriken + Logs + Historien)
- Ursachenhypothesen-Generierung (Root Cause Analysis)
- Auswirkungs- und Risikoanalyse
- Professionelle Ticket-Erstellung (Human-in-the-Loop)
- Predictive Maintenance & Trend-Warnungen
- KI-gestützte Interpretation von Sicherheitsbefunden

**Keine Cloud-Abhängigkeiten für die KI erforderlich.** Die Daten bleiben auf Ihrer Infrastruktur.

---

## Design-Prinzipien

MCP basiert auf fünf Kernprinzipien, die jede Architektur- und Betriebsentscheidung leiten:

- **Secure-by-Design** – Sicherheit ist kein Add-on, sondern Architekturgrundlage
- **Netzwerk-Segmentierung** – 5 isolierte Netzwerke begrenzen den Blast-Radius
- **Human-in-the-Loop** – KI schlägt vor, der Mensch entscheidet
- **Lokale KI** – Datenhoheit ohne Cloud-Abhängigkeit
- **Auditierbare Betriebsabläufe** – Nachvollziehbarkeit in jeder Phase

---

## Für wen ist MCP gedacht?

MCP wurde entwickelt für:

- **Managed Service Provider (MSPs)**, die mandantenfähige Betriebsumgebungen betreiben
- **IT-Abteilungen**, die konsistente Incident-Qualität und operative Dokumentation benötigen
- **Regulierte Umgebungen**, in denen lokale Verarbeitung und strenge Zugriffskontrolle gefordert sind. MCP ist so konzipiert, dass es regulierte Umgebungen *unterstützt* – die Verantwortung für die Compliance-Bewertung liegt beim Betreiber.
- Teams, die „Alert Fatigue" reduzieren und die *Qualität* der Reaktionsmaßnahmen steigern möchten

---

## Zentrale Ergebnisse (der geschäftliche Mehrwert)

MCP konzentriert sich auf messbare operative Ergebnisse:

- **Weniger manuelle Tickets**: Alarme werden automatisch zu strukturierten Incident-Entwürfen
- **Schnellere Triage**: korrelierter Kontext wird jedem Incident beigefügt
- **Bessere Konsistenz**: standardisiertes Ticket-Format + empfohlene Maßnahmen
- **Wissensaufbau**: gelöste Tickets werden zum durchsuchbaren Kontext (RAG)
- **Frühzeitige Warnungen**: trendbasierte Vorhersagen vor Ausfällen

---

## Plattformübersicht

### Stacks (5 Compose-Schichten)

MCP ist in funktionale Stacks gegliedert:

1. **Core** – Datenbanken, Reverse Proxy, Identity, Secrets, Automatisierungs-Grundlage  
2. **Ops** – Ticketing + Wiki + Passwort-Manager + Image-Update-Watcher  
3. **Telemetry** – Monitoring + Dashboards + Log-Aggregation  
4. **Remote** – sichere Fernwartungs-Tools  
5. **AI** – lokale Modelle + KI-Gateway + Processing-Worker + Alerting

### Netzwerke (Defense-in-Depth)

MCP nutzt **5 isolierte Bridge-Netzwerke**, um den Blast-Radius zu minimieren und Segmentierung durchzusetzen:

- `mcp-edge-net` – nur Ingress (Reverse Proxy)
- `mcp-app-net` – interner Anwendungstraffic
- `mcp-data-net` – Datenbanken, eingeschränkte Clients
- `mcp-sec-net` – reserviert für Security-Tooling / SIEM-Erweiterung
- `mcp-ai-net` – KI-Stack (nur intern)

---

## Der KI-Workflow (wie Tickets erstellt werden)

MCP wandelt Signale über eine Gate-gesteuerte Pipeline in Tickets um:

1. **Event-Eingang** (Monitoring/Logs/Sicherheitstool → Automatisierung)
2. **Deduplizierung** (wiederholte Meldungen vermeiden)
3. **Kontexterfassung** (aktuelle Metriken, Logs, Container-Status, historische Treffer)
4. **RAG-Abruf** (ähnliche Incidents & bekannte Lösungen via pgvector)
5. **LLM-Analyse** (lokales Modell, strukturierte Prompts)
6. **Ticket-Entwurf** (strukturierter Incident mit empfohlenen Maßnahmen)
7. **Human-in-the-Loop** (Prüfung/Freigabe, insbesondere in der Anfangsphase)
8. **Wissenserfassung** (gelöste Incidents werden zum durchsuchbaren Kontext)

### Konfidenzmodell (Human-in-the-Loop by Design)

MCP weist jedem Analyseergebnis eine Konfidenzstufe zu:

- **Hohe Konfidenz** → Ticket automatisch erstellt + optionale Automatisierung (richtliniengesteuert)
- **Mittlere Konfidenz** → Ticket-Entwurf + obligatorische manuelle Prüfung
- **Niedrige Konfidenz** → nur Alarm, Mensch übernimmt

Dies verhindert, dass „KI-Halluzinationen" zu Produktionsmaßnahmen werden.

---

## Schnellstart (lokales Lab / Entwicklung)

> **Hinweis:** MCP ist ressourcenintensiv. Lokales Testen dient der Validierung und Entwicklung, nicht dem Produktivbetrieb.

### Voraussetzungen

| Profil | CPU | RAM | Disk | GPU | Hinweis |
|---|---|---|---|---|---|
| **Core only** (ohne KI-Stack) | 4 Kerne | 16 GB | 60 GB | – | Monitoring, Ticketing, Wiki funktionsfähig |
| **Full stack** (mit KI) | 8+ Kerne | 32 GB+ | 120 GB+ | optional (NVIDIA empfohlen) | Alle 32 Container inkl. Ollama + RAG |

Weitere Voraussetzungen:
- Linux oder WSL2 (empfohlen) / macOS (Best Effort)
- Docker Engine ≥ 24.x + Docker Compose Plugin ≥ 2.20

### 1) Repository klonen & Umgebung vorbereiten
```bash
git clone <your-repo-url>
cd <repo-root>

cp .env.example .env
# .env bearbeiten und starke Passwörter setzen (NIEMALS .env committen)
```

### 2) Lokale Hostnamen (empfohlen)

MCP verwendet lokal typischerweise Subdomains wie:
`tickets.localhost`, `wiki.localhost`, `monitor.localhost`, ...

Diese in die Hosts-Datei eintragen:

**Linux/WSL:** `/etc/hosts`  
**Windows:** `C:\Windows\System32\drivers\etc\hosts`

Beispiel:

```
127.0.0.1 tickets.localhost
127.0.0.1 wiki.localhost
127.0.0.1 monitor.localhost
127.0.0.1 automation.localhost
127.0.0.1 identity.localhost
127.0.0.1 vault.localhost
127.0.0.1 status.localhost
```

### 3) MCP starten

**Option A – Orchestrierungsskript** (falls vorhanden):

```bash
bash scripts/mcp-start.sh
```

**Option B – Docker Compose direkt:**

```bash
# Core-Stack
docker compose -f docker-compose.core.yml up -d

# Operations-Stack
docker compose -f docker-compose.ops.yml up -d

# Telemetry-Stack
docker compose -f docker-compose.telemetry.yml up -d

# Remote-Stack
docker compose -f docker-compose.remote.yml up -d

# AI-Stack (erfordert ≥32 GB RAM)
docker compose -f docker-compose.ai.yml up -d
```

**Option C – Makefile** (falls vorhanden):

```bash
make up
```

### 4) Validierung (Gate-Checks)

```bash
# Smoke-Tests (falls vorhanden)
bash tests/smoke-test.sh

# KI-Pipeline-Test (falls vorhanden)
bash tests/ai-pipeline-test.sh

# Minimaler Health-Check
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -c "Up"
```

---

## Produktions-Deployment (Debian-Zielsystem)

Das MCP-Produktions-Deployment basiert auf **Phasen + Gates**. Gates dürfen nicht übersprungen werden.

**Empfohlene Produktions-Baseline:**

* Dedizierter Host oder VPS
* Gehärteter SSH-Zugang (nur Schlüssel)
* Eingeschränkte Firewall
* TLS durchgesetzt
* VPN (WireGuard) für Admin-Zugriff
* Segmentierte Netzwerke explizit erstellt

> **Einstiegspunkt:** Siehe [`docs/deployment-runbook.md`](docs/deployment-runbook.md) für das vollständige Phasen-basierte Deployment-Handbuch.

---

## Sicherheit & Datenschutz

MCP ist mit „Secure-by-Design"-Defaults aufgebaut:

* **Segmentierung zuerst** (5 Netzwerke)
* **Identity & MFA** (Keycloak)
* **Secrets-Management** (OpenBao / `.env`-Richtlinie)
* **TLS überall** (Reverse Proxy + Zertifikatsautomatisierung)
* **Lokale KI** (standardmäßig verlassen keine Daten Ihre Infrastruktur)

### Kritische Regel

**Das KI-Gateway niemals öffentlich im Internet exponieren.**
Es muss intern in den Plattform-Netzwerken verbleiben.

Vollständige Sicherheitsrichtlinie und verantwortungsvolle Offenlegung:

* Siehe [`SECURITY.md`](SECURITY.md)

---

## Betrieb (Day-2)

MCP unterstützt wiederkehrende Betriebsroutinen:

* Automatisierte Backups & Wiederherstellungsübungen
* Geplante Schwachstellenscans → KI-Interpretation → Tickets
* Zertifikatserneuerungs-Prüfungen
* Täglicher KI-Gesundheitsbericht
* Predictive Scans (trendbasiert)
* Kapazitätsplanungs-Bericht

---

## Versionierung & Support-Richtlinie

* **7.x** – aktiv gepflegt (Beta)
* **6.x** – nur Sicherheitspatches
* **≤5.x** – nicht mehr unterstützt

(Details in `SECURITY.md`.)

---

## Roadmap (High-Level)

Geplante Weiterentwicklung (Änderungen basierend auf Praxiserfahrung vorbehalten):

* KI-gestützte Auto-Remediation (richtliniengesteuert)
* Kundenportal
* Multi-Model-Routing
* Multi-Node-Architektur (dedizierter KI-Host / GPU)
* Fine-Tuning auf interner Ticket-Wissensbasis
* Sprach-/Statusinterface

---

## Lizenzierung

**MCP ist proprietäre Software.**
Copyright © <Inhaber/Unternehmen>. Alle Rechte vorbehalten.

| Nutzungsart | Bedingungen |
|---|---|
| **Evaluation** (Lab/Test) | Nur nach schriftlicher Genehmigung des Inhabers. Kein Produktivbetrieb. |
| **Kommerzielle Lizenz** | Individuelle Lizenzvereinbarung erforderlich. |
| **Produktiveinsatz** | Ohne gültige Lizenz ausdrücklich untersagt. |

**Drittanbieter-Komponenten**, die über Container-Images eingebunden sind, unterliegen weiterhin ihren jeweiligen Lizenzen und Markenrechten. MCP erhebt keinen Eigentumsanspruch auf diese Projekte.

Für Lizenzierung, Partnerschaften oder Evaluierungszugang:

* **security@<your-domain>** – Sicherheitsfragen & verantwortungsvolle Offenlegung
* **contact@<your-domain>** – Kommerziell / Lizenzierung / Partnerschaften

---

## Haftungsausschluss

MCP ist eine technische Plattform. Sie muss in einer Laborumgebung validiert und mit angemessenen Sicherheitsmaßnahmen deployt werden.
Die Projektdokumentation bietet operative Orientierung, stellt jedoch keine Rechts- oder Compliance-Beratung dar.

---

<p align="center">
  <strong>MCP – Managed Control Platform</strong><br/>
  <em>Lokal. Sicher. Automatisiert.</em>
</p>
