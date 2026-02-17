# MCP v7 — Tipps & Fehlerbehebung

> **Dieses Dokument enthält alle Fehler, die während der Installation und Tests aufgetreten sind, mit Ursachen und Lösungen.**
> Jede KI und jeder Entwickler, der am Projekt arbeitet, MUSS diese Tipps kennen, um die gleichen Fehler nicht zu wiederholen.

---

## Fehlerübersicht (Schnellreferenz)

| #  | Phase | Fehler                               | Schwere    | Status   |
|----|-------|--------------------------------------|------------|----------|
| 1  | Pull  | Zabbix Image Tag nicht gefunden       | Blockierend| ✅ Gelöst |
| 2  | Pull  | MeshCentral Image Repo falsch         | Blockierend| ✅ Gelöst |
| 3  | 1     | n8n Healthcheck `Connection refused`  | Gate-Fail  | ✅ Gelöst |
| 4  | 1     | OpenBao Healthcheck HTTPS statt HTTP  | Gate-Fail  | ✅ Gelöst |
| 5  | 1     | Keycloak `UnknownHostException`       | CrashLoop  | ✅ Gelöst |
| 6  | 1     | n8n DB-Host `mcp-postgres` unbekannt  | Konfig     | ✅ Gelöst |
| 7  | 1     | KC_DB_URL in .env zeigt auf falschen Host | Konfig | ✅ Gelöst |
| 8  | 1     | nginx 502 — `mcp-*` Upstream-Namen    | Proxy-Fail | ✅ Gelöst |
| 9  | 2     | PostgreSQL `permission denied to create database` | Blockierend | ✅ Gelöst |
| 10 | 2     | PostgreSQL `database "mcp_admin" does not exist`  | Log-Spam   | ✅ Gelöst |
| 11 | 2     | Zammad-Init `exit 1`                  | Blockierend| ✅ Gelöst |
| 12 | 2     | Zammad Assets 404, Ladebildschirm hängt | UI-Fail  | ✅ Gelöst |
| 13 | 2     | Docker Compose Service-Name vs Container-Name | Verwechslung | ✅ Gelöst |
| 14 | 4     | Loki CrashLoop `compactor.delete-request-store` | CrashLoop | ✅ Gelöst |
| 15 | 4     | Zabbix `fe_sendauth: no password supplied` | Gate-Fail | ✅ Gelöst |
| 16 | 4     | Guacamole 404 auf `/`                 | Healthcheck| ✅ Gelöst |
| 17 | 4     | MeshCentral `Empty reply`             | Healthcheck| ✅ Gelöst |
| 18 | Alle  | Orphan Containers Warning             | Warnung    | ✅ Gelöst |
| 19 | 1     | WSL `/mnt/c` Berechtigungsprobleme    | Plattform  | ✅ Gelöst |
| 20 | 3     | n8n Workflows alle `active = false`   | Workflow   | ✅ Gelöst |
| 21 | Alle  | Ports offen auf `0.0.0.0`             | Sicherheit | ⚠️ Offen  |

---

## Fehler im Detail

---

### #1 — Zabbix Image Tag nicht gefunden

| Feld          | Wert |
|---------------|------|
| **Phase**     | Pull (Image-Download) |
| **Datei**     | `compose/telemetry/docker-compose.yml` |
| **Symptom**   | `docker.io/zabbix/zabbix-web-nginx-pgsql:7.0-alpine: not found` |
| **Ursache**   | Der Tag `7.0-alpine` existiert nicht auf Docker Hub. Zabbix verwendet das Format `7.0.0-alpine` (mit Patch-Version). |
| **Lösung**    | Tag in `.env` korrigieren |

```bash
# .env
ZABBIX_TAG=7.0.0-alpine
```

**Regel für die Zukunft:** Immer exakte Versionsnummern mit Patch-Level verwenden (z.B. `7.0.0-alpine`), nie Kurzformen wie `7.0-alpine`.

---

### #2 — MeshCentral Image Repository falsch

| Feld          | Wert |
|---------------|------|
| **Phase**     | Pull (Image-Download) |
| **Datei**     | `compose/remote/docker-compose.yml` |
| **Symptom**   | `pull access denied for meshcentral/meshcentral, repository does not exist` |
| **Ursache**   | Das Docker Hub Repository `meshcentral/meshcentral` existiert nicht. Auch `ylianst/meshcentral` existiert nicht auf Docker Hub. Das offizielle Image liegt auf GitHub Container Registry (GHCR). |
| **Lösung**    | Image-Quelle auf GHCR ändern |

```yaml
# compose/remote/docker-compose.yml — VORHER (falsch):
image: meshcentral/meshcentral:${MESHCENTRAL_TAG:-1.1.35}

# NACHHER (korrekt):
image: ghcr.io/ylianst/meshcentral:${MESHCENTRAL_TAG:-latest}
```

```bash
# .env
MESHCENTRAL_TAG=latest
```

**Regel für die Zukunft:** Vor dem Festlegen eines Image immer `docker pull <image>` testen. Nicht alle Projekte sind auf Docker Hub — GHCR, Quay.io und andere Registries prüfen.

---

### #3 — n8n Healthcheck `Connection refused`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `compose/core/docker-compose.yml` |
| **Symptom**   | Container-Status `unhealthy`, Log: `wget: can't connect to remote host: Connection refused` |
| **Ursache**   | Zwei Probleme: (1) Der Healthcheck verwendete `localhost` was auf IPv6 `::1` auflöst, aber n8n nur auf IPv4 hört. (2) Die `start_period` war zu kurz — n8n braucht Zeit für Datenbank-Migrationen. |
| **Lösung**    | IP explizit auf `127.0.0.1` setzen und `start_period` verlängern |

```yaml
# compose/core/docker-compose.yml — n8n healthcheck:
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:5678/healthz >/dev/null 2>&1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 120s    # ← Wichtig! n8n braucht Zeit für Migrationen
```

**Regel für die Zukunft:** IMMER `127.0.0.1` statt `localhost` in Healthchecks verwenden (IPv6-Problem). IMMER `start_period: 120s` für Services mit Datenbank-Migrationen.

---

### #4 — OpenBao Healthcheck HTTPS statt HTTP

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `compose/core/docker-compose.yml` |
| **Symptom**   | Container `unhealthy`, Log: `http: server gave HTTP response to HTTPS client` |
| **Ursache**   | OpenBao läuft im Dev-Mode mit TLS deaktiviert (HTTP), aber der Healthcheck versuchte eine HTTPS-Verbindung. |
| **Lösung**    | Healthcheck-Protokoll von HTTPS auf HTTP ändern |

```bash
# Korrektur im compose:
sed -i 's|https://127\.0\.0\.1:8200|http://127.0.0.1:8200|g' compose/core/docker-compose.yml
```

```yaml
# Korrekt:
healthcheck:
  test: ["CMD", "bao", "status", "-address=http://127.0.0.1:8200"]
```

**Regel für die Zukunft:** Protokoll (HTTP/HTTPS) bei jedem Service prüfen bevor Healthchecks geschrieben werden. Im Dev-Mode ist TLS meist deaktiviert.

---

### #5 — Keycloak `UnknownHostException: mcp-postgres`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `.env` + `compose/core/docker-compose.yml` |
| **Symptom**   | Keycloak in CrashLoop (`Restarting`), Log: `java.net.UnknownHostException: mcp-postgres` |
| **Ursache**   | Keycloak versuchte sich mit `mcp-postgres` als DB-Host zu verbinden, aber der Docker-Service heißt `postgres` (nicht `mcp-postgres`). Docker DNS kennt nur Service-Namen, nicht Container-Namen. |
| **Lösung**    | `KC_DB_URL` in `.env` korrigieren |

```bash
# .env — VORHER (falsch):
KC_DB_URL=jdbc:postgresql://mcp-postgres:5432/keycloak

# NACHHER (korrekt):
KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak
```

**Regel für die Zukunft:** In Docker Compose ist der **Service-Name** der DNS-Name (z.B. `postgres`), NICHT der Container-Name (z.B. `mcp-postgres-1`). Alle Host-Referenzen müssen Service-Namen verwenden.

---

### #6 — n8n DB-Host `mcp-postgres` unbekannt

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `compose/core/docker-compose.yml` |
| **Symptom**   | n8n kann keine DB-Verbindung aufbauen |
| **Ursache**   | Gleiche Ursache wie #5: `DB_POSTGRESDB_HOST: mcp-postgres` statt `postgres` |
| **Lösung**    | Host in compose korrigieren |

```yaml
# compose/core/docker-compose.yml — VORHER:
DB_POSTGRESDB_HOST: mcp-postgres

# NACHHER:
DB_POSTGRESDB_HOST: postgres
```

---

### #7 — KC_DB_URL in .env zeigt auf falschen Host

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `.env` |
| **Symptom**   | Gleich wie #5, aber Ursache in `.env` statt in compose |
| **Ursache**   | Das Installationsskript generierte `KC_DB_URL` mit `mcp-postgres` als Host |
| **Lösung**    | |

```bash
sed -i 's|jdbc:postgresql://mcp-postgres:|jdbc:postgresql://postgres:|g' .env
```

**Regel für die Zukunft:** Das Installationsskript (`install.sh`) muss DB-Hosts konsistent mit Service-Namen generieren. Preflight-Check hinzufügen: alle `*_HOST` Variablen gegen Service-Namen validieren.

---

### #8 — nginx 502 — `mcp-*` Upstream-Namen

| Feld          | Wert |
|---------------|------|
| **Phase**     | 1 (Core Stack) |
| **Datei**     | `config/nginx/sites/*.conf` (alle Dateien) |
| **Symptom**   | Alle Proxy-Pfade geben `502 Bad Gateway` zurück. nginx error.log: `Host not found in upstream "mcp-n8n"` |
| **Ursache**   | Alle nginx-Konfigurationsdateien verwendeten Container-Namen (z.B. `http://mcp-n8n:5678`) statt Service-Namen (z.B. `http://n8n:5678`). Docker DNS kennt nur Service-Namen. |
| **Lösung**    | Alle `mcp-*` Upstream-Referenzen in nginx-Configs ersetzen |

```bash
# Automatische Korrektur aller nginx site-Configs:
sed -i -E 's|http://mcp-([a-zA-Z0-9_-]+):|http://\1:|g' config/nginx/sites/*.conf

# Danach:
docker exec -it mcp-nginx nginx -t && docker exec -it mcp-nginx nginx -s reload
```

**Betroffene Dateien:**
- `automation.conf`: `mcp-n8n` → `n8n`
- `tickets.conf`: `mcp-zammad-rails` → `zammad-rails`, `mcp-zammad-ws` → `zammad-ws`
- `vault.conf`: `mcp-vaultwarden` → `vaultwarden`
- `monitor.conf`: `mcp-grafana` → `grafana`
- `status.conf`: `mcp-uptime-kuma` → `uptime-kuma`
- `ai.conf`: `mcp-ai-gateway` → `ai-gateway`
- `identity.conf`: `mcp-keycloak` → `keycloak`
- `wiki.conf`: `mcp-bookstack` → `bookstack`

**Regel für die Zukunft:** nginx-Configs müssen Service-Namen verwenden, NICHT Container-Namen. Beim Generieren von Configs immer Docker-Service-Namen als Quelle nehmen.

---

### #9 — PostgreSQL `permission denied to create database`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 2 (Ops Stack) |
| **Datei**     | `scripts/init-db.sh` |
| **Symptom**   | `zammad-init` schlägt fehl mit `exit 1`. PostgreSQL Log: `ERROR: permission denied to create database` |
| **Ursache**   | Die Zammad DB-Rolle hat keine `CREATEDB`-Berechtigung. Zammad-Init versucht, die Datenbank selbst zu erstellen, benötigt dafür aber die Berechtigung. |
| **Lösung**    | Rolle in `init-db.sh` mit `CREATEDB`-Recht versehen |

```sql
-- In scripts/init-db.sh hinzufügen:
ALTER ROLE zammad CREATEDB;
```

```bash
# Oder manuell:
docker exec -it mcp-postgres bash -lc \
'psql -U mcp_admin -d postgres -c "ALTER ROLE zammad CREATEDB;"'
```

**Regel für die Zukunft:** Alle DB-Rollen die eine eigene Datenbank brauchen müssen in `init-db.sh` mit `CREATEDB` angelegt werden. Betroffene Rollen: `zammad`, `n8n`, `bookstack`, `keycloak`.

---

### #10 — PostgreSQL `database "mcp_admin" does not exist`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 2 (Ops Stack) |
| **Datei**     | `scripts/init-db.sh` |
| **Symptom**   | Log-Spam: `FATAL: database "mcp_admin" does not exist` (hunderte Male) |
| **Ursache**   | Ein Client (Portainer, Grafana oder ein anderer Service) versucht sich auf die Datenbank `mcp_admin` zu verbinden, die nicht existiert. `POSTGRES_DB=mcp_core` erstellt nur `mcp_core`. |
| **Lösung**    | Datenbank `mcp_admin` in `init-db.sh` erstellen |

```sql
-- In scripts/init-db.sh:
CREATE DATABASE mcp_admin OWNER mcp_admin;
```

**Regel für die Zukunft:** Jede Datenbank, die von einem Service referenziert wird, MUSS in `init-db.sh` erstellt werden. Preflight-Check: alle `*_DB` Variablen aus `.env` gegen tatsächlich existierende Datenbanken prüfen.

---

### #11 — Zammad-Init `exit 1`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 2 (Ops Stack) |
| **Datei**     | `compose/ops/docker-compose.yml` |
| **Symptom**   | `service "zammad-init" didn't complete successfully: exit 1` |
| **Ursache**   | Kombination aus #9 (keine CREATEDB-Berechtigung) und falschen DB-Host-Namen. Zammad-Init konnte weder die Datenbank erstellen noch sich verbinden. |
| **Lösung**    | Fehler #9 und #5/#6 zuerst beheben, dann Zammad-Init neu starten |

```bash
# 1. Fehler #9 beheben (CREATEDB)
# 2. Alte Container entfernen:
docker ps -a --format '{{.Names}}' | grep -E '^mcp-zammad' | xargs -r docker rm -f
# 3. Ops Stack neu starten:
docker compose --env-file .env -f compose/ops/docker-compose.yml up -d
```

---

### #12 — Zammad Assets 404, Ladebildschirm hängt

| Feld          | Wert |
|---------------|------|
| **Phase**     | 2 (Ops Stack) |
| **Datei**     | `compose/ops/docker-compose.yml` |
| **Symptom**   | Zammad-UI zeigt nur Ladebildschirm. Browser-Console: `404 Not Found` für alle `/assets/*` Dateien. Log: `ActionController::RoutingError` |
| **Ursache**   | Die Umgebungsvariable `RAILS_SERVE_STATIC_FILES` fehlt. Ohne diese Variable liefert der Rails-Server keine statischen Assets aus. |
| **Lösung**    | Variable in compose hinzufügen |

```yaml
# compose/ops/docker-compose.yml — bei zammad-rails:
environment:
  RAILS_SERVE_STATIC_FILES: "true"    # ← KRITISCH! Ohne das keine Assets
```

**Regel für die Zukunft:** Bei jedem Rails-basierten Container immer `RAILS_SERVE_STATIC_FILES=true` setzen wenn kein separater Asset-Server (z.B. nginx) vor dem Rails-Prozess steht.

---

### #13 — Docker Compose Service-Name vs Container-Name Verwechslung

| Feld          | Wert |
|---------------|------|
| **Phase**     | Alle |
| **Datei**     | Alle `docker-compose.yml` |
| **Symptom**   | `no such service: mcp-zammad-init` beim Versuch `docker compose up -d mcp-zammad-init` |
| **Ursache**   | Verwechslung zwischen Service-Name und Container-Name. In Docker Compose v2 heißt der Container `mcp-zammad-init` (Projektname + Service), aber der Service heißt `zammad-init`. |
| **Lösung**    | Richtige Syntax verwenden |

```bash
# FALSCH (Container-Name):
docker compose up -d mcp-zammad-init

# RICHTIG (Service-Name):
docker compose up -d zammad-init

# Container-Name für Logs verwenden:
docker logs mcp-zammad-init          # ← OK für Logs
docker exec -it mcp-zammad-init ...  # ← OK für exec
```

**Referenz:**
- `docker compose up/down/restart` → **Service-Name** (ohne Prefix)
- `docker logs / exec / inspect` → **Container-Name** (mit Prefix `mcp-`)
- Service-Namen anzeigen: `docker compose -f <file> config --services`

---

### #14 — Loki CrashLoop `compactor.delete-request-store`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 4 (Telemetry Stack) |
| **Datei**     | `config/loki/loki-config.yml` |
| **Symptom**   | Loki-Container startet neu (CrashLoop). Log: `compactor.delete-request-store` Fehler |
| **Ursache**   | Retention war aktiviert ohne korrekte Compactor-Konfiguration. Im Offline-Betrieb brauchen wir keine Log-Retention mit Compactor. |
| **Lösung**    | Retention deaktivieren |

```yaml
# config/loki/loki-config.yml:
compactor:
  working_directory: /tmp/loki/compactor

limits_config:
  retention_period: 0           # ← Retention deaktiviert
  # retention_enabled: false    # ← Alternative (je nach Loki-Version)
```

**Regel für die Zukunft:** Bei Loki im Offline-/Single-Node-Betrieb: Retention nur aktivieren wenn Compactor korrekt konfiguriert ist. Im Zweifel `retention_period: 0` setzen.

---

### #15 — Zabbix `fe_sendauth: no password supplied`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 4 (Telemetry Stack) |
| **Datei**     | `compose/telemetry/docker-compose.yml` |
| **Symptom**   | Zabbix-Server kann sich nicht mit PostgreSQL verbinden. Log: `fe_sendauth: no password supplied` |
| **Ursache**   | Ein Bind-Mount für eine Konfigurationsdatei überschreibt die Umgebungsvariablen des Containers. Zabbix braucht die DB-Zugangsdaten als Umgebungsvariablen, aber der Bind-Mount setzt eigene Werte (oder leere Werte). |
| **Lösung**    | Config-Bind-Mount entfernen |

```yaml
# compose/telemetry/docker-compose.yml — ENTFERNEN:
# volumes:
#   - ./config/zabbix/zabbix_server.conf:/etc/zabbix/zabbix_server.conf   ← ENTFERNEN!

# Stattdessen NUR Umgebungsvariablen verwenden:
environment:
  DB_SERVER_HOST: postgres
  POSTGRES_USER: ${ZABBIX_DB_USER}
  POSTGRES_PASSWORD: ${ZABBIX_DB_PASSWORD}
  POSTGRES_DB: ${ZABBIX_DB_NAME}
```

**Regel für die Zukunft:** Kein Bind-Mount für Konfigurationsdateien bei Services die Umgebungsvariablen für DB-Verbindungen benötigen — Bind-Mounts überschreiben alles.

---

### #16 — Guacamole 404 auf `/`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 4 (Remote Stack) |
| **Datei**     | `tests/smoke-test.sh` |
| **Symptom**   | Healthcheck auf `http://guacamole:8080/` gibt 404 |
| **Ursache**   | Guacamole's Web-Interface liegt unter `/guacamole/`, nicht unter `/`. |
| **Lösung**    | URL im Smoke-Test und Healthcheck korrigieren |

```bash
# FALSCH:
curl http://guacamole:8080/

# RICHTIG:
curl http://guacamole:8080/guacamole/
```

```yaml
# nginx-Konfiguration für Guacamole:
location / {
    return 302 /guacamole/;    # ← Redirect auf richtigen Pfad
}
location /guacamole/ {
    proxy_pass http://guacamole:8080/guacamole/;
}
```

**Regel für die Zukunft:** Context-Pfade prüfen (in der Dokumentation des jeweiligen Projekts) BEVOR Healthchecks geschrieben werden.

---

### #17 — MeshCentral `Empty reply from server`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 4 (Remote Stack) |
| **Datei**     | `tests/smoke-test.sh` |
| **Symptom**   | `curl: (52) Empty reply from server` beim Healthcheck |
| **Ursache**   | MeshCentral lauscht auf HTTPS (Port 4430), nicht auf HTTP. Der Healthcheck verwendete `http://` statt `https://`. |
| **Lösung**    | Protokoll auf HTTPS ändern |

```bash
# FALSCH:
curl http://meshcentral:4430/

# RICHTIG:
curl -k https://meshcentral:443/
```

```yaml
# nginx Reverse Proxy für MeshCentral:
location / {
    proxy_pass https://meshcentral;    # ← HTTPS!
    proxy_ssl_verify off;
}
```

**Regel für die Zukunft:** Protokoll (HTTP vs HTTPS) und Port bei jedem Service prüfen. MeshCentral verwendet standardmäßig HTTPS.

---

### #18 — Orphan Containers Warning

| Feld          | Wert |
|---------------|------|
| **Phase**     | Alle |
| **Datei**     | `.env` |
| **Symptom**   | `WARN[0000] Found orphan containers for this project` bei jedem `docker compose up` |
| **Ursache**   | Mehrere `docker-compose.yml` Dateien ohne einheitlichen Projektnamen. Docker Compose erkennt Container anderer Stacks als "verwaist". |
| **Lösung**    | `COMPOSE_PROJECT_NAME` in `.env` setzen |

```bash
# In .env:
COMPOSE_PROJECT_NAME=mcp
```

```bash
# Oder automatisch hinzufügen:
grep -q '^COMPOSE_PROJECT_NAME=' .env || echo 'COMPOSE_PROJECT_NAME=mcp' >> .env
```

**Regel für die Zukunft:** `COMPOSE_PROJECT_NAME=mcp` MUSS in jeder `.env` und `.env.example` stehen. Ohne dies funktioniert das Multi-Compose-Setup nicht sauber.

---

### #19 — WSL `/mnt/c` Berechtigungsprobleme

| Feld          | Wert |
|---------------|------|
| **Phase**     | Alle (WSL-spezifisch) |
| **Datei**     | Projekt-Verzeichnis |
| **Symptom**   | `chmod +x` funktioniert nicht, Scripts haben `\r\n` Zeilenenden, Docker-Volumes haben Berechtigungsprobleme |
| **Ursache**   | Das Windows-Dateisystem (`/mnt/c/`) unterstützt keine Unix-Berechtigungen. CRLF-Zeilenenden aus Windows brechen Shell-Scripts. |
| **Lösung**    | Projekt in WSL-eigenes Dateisystem kopieren |

```bash
# Projekt nach WSL kopieren:
mkdir -p ~/masdor
cp -a /mnt/c/masdor/Masdor-main/Masdor-main ~/masdor/Masdor-main
cd ~/masdor/Masdor-main

# Zeilenenden korrigieren:
sed -i 's/\r$//' *.sh scripts/*.sh

# Ausführbar machen:
chmod +x scripts/*.sh local-test.sh install.sh
```

**Regel für die Zukunft:** Auf WSL IMMER im Linux-Dateisystem (`~/...`) arbeiten, NICHT auf `/mnt/c/`. Die Performance ist besser und Berechtigungsprobleme entfallen.

---

### #20 — n8n Workflows alle `active = false`

| Feld          | Wert |
|---------------|------|
| **Phase**     | 3 (Workflow Import) |
| **Datei**     | `config/n8n/workflows/` |
| **Symptom**   | Nach dem Import sind alle 8 Workflows (W1–W8) deaktiviert. Webhooks werden nicht registriert. |
| **Ursache**   | n8n importiert Workflows standardmäßig als `inactive`. Webhooks werden erst bei Aktivierung registriert. |
| **Lösung**    | Workflows per SQL oder API aktivieren |

```bash
# Per SQL (direkt nach Import):
docker exec -it mcp-postgres bash -lc \
'psql -U mcp_admin -d n8n -c "UPDATE workflow_entity SET active = true WHERE active = false;"'

# Danach n8n neu starten damit Webhooks registriert werden:
docker restart mcp-n8n
```

**Erwartete Webhooks nach Aktivierung:**
| Webhook-Pfad        | Workflow |
|---------------------|----------|
| `/webhook/zabbix-alert`    | W1 — Alert AI Analysis |
| `/webhook/loki-alert`      | W2 — Log Anomaly Ticket |
| `/webhook/security-finding`| W3 — Security Finding |
| `/webhook/ticket-closed`   | W5 — Ticket Close Knowledge |
| `/webhook/network-anomaly` | W6 — Network Anomaly |

**Regel für die Zukunft:** Das Installationsskript muss nach dem Import der Workflows automatisch alle aktivieren und prüfen ob die Webhooks registriert sind.

---

### #21 — Ports offen auf `0.0.0.0` (Sicherheit)

| Feld          | Wert |
|---------------|------|
| **Phase**     | Alle |
| **Datei**     | `compose/core/docker-compose.yml` |
| **Symptom**   | Interne Services sind direkt vom Netzwerk erreichbar (n8n `:5678`, Keycloak `:8080`, PostgreSQL `:5432`, Redis `:6379`) |
| **Ursache**   | `ports:` Definitionen exponieren Services auf `0.0.0.0` (alle Interfaces) statt nur intern |
| **Lösung**    | Ports entfernen oder auf `127.0.0.1` binden |

```yaml
# FALSCH (offen für alle):
ports:
  - "5678:5678"

# RICHTIG (nur lokal, für Entwicklung):
ports:
  - "127.0.0.1:5678:5678"

# BEST (kein externer Zugang, nur über nginx):
# ports: entfernen, nur expose: verwenden
expose:
  - "5678"
```

**Regel für die Zukunft:** Im Produktionsbetrieb: NUR nginx auf Port 80/443 exponieren. Alle anderen Services verwenden `expose:` statt `ports:` und sind nur über nginx Reverse Proxy erreichbar.

---

## Allgemeine Design-Patterns

> Diese Patterns verhindern 90% der oben dokumentierten Fehler.

### 1. Service-Namen statt Container-Namen

```
Docker DNS = Service-Name (z.B. "postgres")
Container-Name = Projektname + Service (z.B. "mcp-postgres-1")

→ In allen Configs, .env, nginx: NUR Service-Namen verwenden
→ Container-Namen nur für: docker logs, docker exec, docker inspect
```

### 2. Healthcheck-Regeln

```
1. Immer 127.0.0.1 statt localhost (IPv6-Problem)
2. Immer HTTP/HTTPS prüfen (nicht raten)
3. Immer Context-Pfad prüfen (z.B. /guacamole/ nicht /)
4. start_period: 120s für Services mit DB-Migrationen
5. Werkzeug im Container prüfen (wget vs curl)
```

### 3. Datenbank-Initialisierung

```
init-db.sh MUSS enthalten:
1. Alle Rollen mit CREATEDB: zammad, n8n, bookstack, keycloak, grafana
2. Alle Datenbanken: mcp_core, mcp_admin, zammad, n8n, bookstack, keycloak
3. Alle Grants: CONNECT, ALL PRIVILEGES auf jeweilige DB
```

### 4. Offline-Vorbereitung

```
1. Alle Images vorher pullen + als .tar exportieren
2. Exakte Tags verwenden (7.0.0-alpine NICHT 7.0-alpine)
3. Registry prüfen (Docker Hub vs GHCR vs Quay)
4. KI-Modelle separat exportieren
```

### 5. COMPOSE_PROJECT_NAME

```
IMMER in .env setzen: COMPOSE_PROJECT_NAME=mcp
Sonst: Orphan-Warnings, inkonsistente Container-Namen
```

---

## Checkliste vor jedem Deployment

```
□ .env enthält COMPOSE_PROJECT_NAME=mcp
□ Alle Image-Tags sind exakte Versionen (nicht :latest im Prod)
□ Alle DB-Hosts in .env und compose verwenden Service-Namen
□ Alle nginx-Configs verwenden Service-Namen (nicht mcp-*)
□ init-db.sh erstellt alle Datenbanken und Rollen mit CREATEDB
□ Healthchecks verwenden 127.0.0.1 und korrektes Protokoll
□ Zammad hat RAILS_SERVE_STATIC_FILES=true
□ Loki hat retention_period: 0 (oder Compactor konfiguriert)
□ Keine ports: auf 0.0.0.0 (nur nginx 80/443)
□ WSL: Projekt liegt auf ~/... nicht auf /mnt/c/
```

---

<p align="center">
  <em>Zuletzt aktualisiert: Februar 2026 — Phase 1–4 WSL Tests</em><br/>
  <strong>MCP v7 — Lokal. Sicher. Automatisiert.</strong>
</p>
