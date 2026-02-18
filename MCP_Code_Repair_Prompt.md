# Masdor-MCP v0.2 — Code-Reparatur-Prompt

> **Zweck:** Dieses Dokument beschreibt alle Fehler, die beim Deployment-Test v0.1 und v0.2 aufgetreten sind. Es dient als Anweisung für Claude Code, um den gesamten Quellcode so zu reparieren, dass ein sauberer Durchlauf aller Phasen möglich ist.
>
> **Projekt-Pfad:** `/opt/masdor/Masdor-MCP`  
> **Betriebssystem:** Debian 13 (Trixie), x86_64/amd64  
> **Docker:** 26.1.5, Compose 2.26.1

---

## Anweisung an Claude Code

Lies dieses Dokument komplett. Jeder Fehler hat drei Abschnitte:

1. **Was ist passiert** — der Fehler und seine Ursache
2. **Wie wurde lokal gefixt** — was der Tester manuell gemacht hat
3. **Was im Code zu fixen ist** — wo und wie du den Quellcode ändern musst

Arbeite alle Fehler der Reihe nach ab. Validiere am Ende jede Compose-Datei mit `docker-compose config`.

---

## FIX-001 — .env: ES_JAVA_OPTS ohne Anführungszeichen

**Was ist passiert:**  
Beim Starten der Ops-Compose erschien: `.env: line 91: -Xmx512m: command not found`. Bash interpretierte `-Xmx512m` als Kommando, weil der Wert nicht in Quotes steht.

**Wie wurde lokal gefixt:**  
Die Zeile in `.env` wurde korrigiert zu: `ES_JAVA_OPTS="-Xms512m -Xmx512m"`

**Was im Code zu fixen ist:**

- **Datei:** `.env.example`
- **Suche:** `ES_JAVA_OPTS=` Zeile
- **Ändere zu:**
  ```
  ES_JAVA_OPTS="-Xms512m -Xmx512m"
  ```
- **Regel:** Alle Werte in `.env.example`, die Leerzeichen oder Sonderzeichen enthalten, MÜSSEN in doppelten Anführungszeichen stehen.
- **Prüfe auch:** Alle anderen Zeilen in `.env.example` auf fehlende Quotes bei Werten mit Leerzeichen.

---

## FIX-002 — BookStack: APP_KEY fehlt

**Was ist passiert:**  
`mcp-bookstack` startete nicht. Log: `The application key is missing, halting init!`

**Wie wurde lokal gefixt:**  
APP_KEY manuell generiert und in `.env` eingetragen.

**Was im Code zu fixen ist:**

- **Datei:** `.env.example`
- **Füge hinzu** (falls nicht vorhanden):
  ```
  ## BookStack
  BOOKSTACK_APP_KEY=SomeKeyChangeMe
  ```
- **Datei:** `scripts/mcp-install.sh`
- **Füge hinzu** in der Pre-Flight/Setup-Phase (vor Phase 4 / Ops Stack):
  ```bash
  # Generate BookStack APP_KEY if placeholder
  if grep -q "BOOKSTACK_APP_KEY=SomeKeyChangeMe" .env 2>/dev/null; then
    NEW_KEY=$(openssl rand -base64 32)
    sed -i "s|BOOKSTACK_APP_KEY=SomeKeyChangeMe|BOOKSTACK_APP_KEY=base64:${NEW_KEY}|" .env
    echo "[INFO] BookStack APP_KEY generated"
  fi
  ```
- **Wichtig:** Der Installer muss den Key automatisch generieren. Der User darf nie manuell einen Key erzeugen müssen.

---

## FIX-003 — Vaultwarden: Healthcheck falscher Endpoint + falsches Tool

**Was ist passiert:**  
`mcp-vaultwarden` war dauerhaft `unhealthy`. Mehrere Ursachen:
1. Healthcheck nutzte `/alive` → Endpoint existiert nicht (404)
2. Healthcheck nutzte `wget` → `wget` ist im Vaultwarden-Image nicht installiert (Exit 127)
3. Vaultwarden gibt auf `/` keinen 200er, sondern 301/302

**Wie wurde lokal gefixt:**  
Healthcheck auf `curl` umgestellt mit toleranten Statuscodes.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Service:** `vaultwarden`
- **Ersetze den gesamten healthcheck-Block durch:**
  ```yaml
  healthcheck:
    test: ["CMD-SHELL", "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:80/ | grep -Eq '^(200|301|302|401|403|404)$'"]
    interval: 30s
    timeout: 5s
    retries: 10
    start_period: 60s
  ```
- **Begründung:** Vaultwarden hat kein `wget`, nur `curl`. Der Root-Pfad gibt je nach Config einen Redirect (301/302). Wir akzeptieren alle HTTP-Antworten als "Service lebt".

---

## FIX-004 — Portainer: Healthcheck scheitert (kein /bin/sh im Image)

**Was ist passiert:**  
`mcp-portainer` war dauerhaft `unhealthy`. Das Portainer-CE-Image enthält kein `/bin/sh`, daher kann `CMD-SHELL` nicht ausgeführt werden: `exec: "/bin/sh": stat /bin/sh: no such file or directory`.

**Wie wurde lokal gefixt:**  
Healthcheck wurde entfernt bzw. auf ein funktionierendes Setup umgestellt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Service:** `portainer`
- **Ersetze den gesamten healthcheck-Block durch:**
  ```yaml
  healthcheck:
    test: ["CMD", "/portainer", "--help"]
    interval: 30s
    timeout: 5s
    retries: 5
    start_period: 30s
  ```
- **Alternative (wenn --help nicht mit Exit 0 endet):** Healthcheck komplett entfernen:
  ```yaml
  healthcheck:
    test: ["NONE"]
  ```
- **Datei:** `scripts/mcp-install.sh`
- **Ändere** die Gate-Check-Logik: Portainer soll nicht auf `healthy` geprüft werden, sondern nur auf `running`:
  ```bash
  # Portainer has no shell, check running state instead of health
  if docker ps --filter "name=mcp-portainer" --filter "status=running" -q | grep -q .; then
    echo "[OK] mcp-portainer is running"
  fi
  ```

---

## FIX-005 — Zabbix-Web: PostgreSQL nicht erreichbar (falsches Netzwerk)

**Was ist passiert:**  
`mcp-zabbix-web` war `unhealthy` mit: `PostgreSQL server is not available`. Der Container war nur in `mcp-app-net`, aber PostgreSQL (`mcp-postgres`) läuft in `mcp-data-net`.

**Wie wurde lokal gefixt:**  
`mcp-data-net` bei `zabbix-web` hinzugefügt und `DB_SERVER_HOST=mcp-postgres` gesetzt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/telemetry/docker-compose.yml`
- **Service:** `zabbix-web`
  - **networks:** Füge `mcp-data-net` hinzu:
    ```yaml
    networks:
      - mcp-app-net
      - mcp-data-net
    ```
  - **environment:** Setze DB-Host auf den Container-Namen:
    ```yaml
    DB_SERVER_HOST: mcp-postgres
    ```
- **Service:** `zabbix-server`
  - **networks:** Prüfe, dass auch `mcp-data-net` enthalten ist
  - **environment:** Prüfe, dass `DB_SERVER_HOST: mcp-postgres` gesetzt ist
- **Service:** `grafana` (falls DB-Datasource konfiguriert)
  - **networks:** Prüfe, dass auch `mcp-data-net` enthalten ist
- **Top-level networks:** Stelle sicher, dass `mcp-data-net` als external deklariert ist:
  ```yaml
  networks:
    mcp-app-net:
      external: true
    mcp-data-net:
      external: true
  ```

---

## FIX-006 — CrowdSec: Pflicht-Volume fehlt

**Was ist passiert:**  
`mcp-crowdsec` crashte sofort mit:
```
No volume mounted for /var/lib/crowdsec/data
It is mandatory to mount a volume to this directory
Exiting...
```

**Wie wurde lokal gefixt:**  
Volume manuell in compose hinzugefügt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/telemetry/docker-compose.yml`
- **Service:** `crowdsec`
- **Füge bei volumes hinzu:**
  ```yaml
  volumes:
    - ../../config/crowdsec/acquis.yml:/etc/crowdsec/acquis.yaml:ro
    - /var/log:/var/log:ro
    - mcp-crowdsec-data:/var/lib/crowdsec/data
  ```
- **Top-level volumes:** Füge hinzu:
  ```yaml
  volumes:
    mcp-crowdsec-data:
      external: true
  ```
- **Datei:** `scripts/mcp-install.sh`
- **Füge hinzu** bei Volume-Erstellung (Pre-Flight oder vor Phase 5):
  ```bash
  docker volume create mcp-crowdsec-data 2>/dev/null || true
  ```

---

## FIX-007 — LiteLLM: Falsches Platform-Image (arm64 auf amd64)

**Was ist passiert:**  
Beim Starten der AI-Phase erschien:
```
The requested image's platform (linux/arm64/v8) does not match the detected host platform (linux/amd64/v4)
```
LiteLLM-Image ist für ARM64, der Server ist AMD64.

**Wie wurde lokal gefixt:**  
Noch nicht gefixt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ai/docker-compose.yml`
- **Service:** `litellm`
- **Füge hinzu:**
  ```yaml
  platform: linux/amd64
  ```
- **Oder:** Verwende ein Multi-Arch-Image. Prüfe auf Docker Hub, ob eine amd64-Variante verfügbar ist.
- **Prüfe auch alle anderen Services** in `compose/ai/docker-compose.yml` auf platform-Kompatibilität.

---

## FIX-008 — Ollama: unhealthy blockiert AI-Stack

**Was ist passiert:**  
`mcp-ollama` wurde als `unhealthy` gemeldet, was den Start von `mcp-ai-gateway` und `mcp-langchain` blockierte (`dependency failed to start: container mcp-ollama is unhealthy`).

**Wie wurde lokal gefixt:**  
Noch nicht gefixt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ai/docker-compose.yml`
- **Service:** `ollama`
- **Prüfe den Healthcheck:** Ollama braucht Zeit zum Starten (besonders nach Model-Pull). Erhöhe Timeouts:
  ```yaml
  healthcheck:
    test: ["CMD-SHELL", "curl -sf http://127.0.0.1:11434/ || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 15
    start_period: 120s
  ```
- **Prüfe depends_on:** Andere AI-Services sollten `condition: service_started` statt `service_healthy` nutzen, falls Ollama keine schnelle Healthcheck-Antwort liefert:
  ```yaml
  depends_on:
    ollama:
      condition: service_started
  ```

---

## FIX-009 — Orphan-Container-Warnungen bei jeder Phase

**Was ist passiert:**  
Bei jedem `docker-compose up` erschien: `Found orphan containers ([mcp-...]) for this project`. Das liegt daran, dass verschiedene Compose-Dateien verschiedene Projektnamen haben.

**Wie wurde lokal gefixt:**  
Wurde ignoriert (nicht blockierend).

**Was im Code zu fixen ist:**

- **Datei:** `scripts/mcp-install.sh`
- **Bei jedem docker-compose Aufruf** füge `--project-name mcp` hinzu:
  ```bash
  docker-compose --project-name mcp --env-file .env -f compose/core/docker-compose.yml up -d
  docker-compose --project-name mcp --env-file .env -f compose/ops/docker-compose.yml up -d
  docker-compose --project-name mcp --env-file .env -f compose/telemetry/docker-compose.yml up -d
  docker-compose --project-name mcp --env-file .env -f compose/ai/docker-compose.yml up -d
  ```
- **Alternativ:** Erstelle eine `.env`-Datei oder `docker-compose.override.yml` im Projektroot mit:
  ```
  COMPOSE_PROJECT_NAME=mcp
  ```

---

## FIX-010 — Zammad: Netzwerk-Isolation (Redis nicht erreichbar) — aus v0.1

**Was ist passiert:**  
Zammad-Services (rails, websocket, worker) konnten Redis nicht erreichen: `Redis: Name or service not known`. Zammad war nur in `mcp-app-net`, Redis in `mcp-data-net`.

**Wie wurde lokal gefixt:**  
`mcp-data-net` bei allen Zammad-Services hinzugefügt.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Services:** `zammad-rails`, `zammad-websocket`, `zammad-worker`, `zammad-init`
- **Bei jedem dieser Services:** Füge `mcp-data-net` zu networks hinzu:
  ```yaml
  networks:
    - mcp-app-net
    - mcp-data-net
  ```
- **Top-level networks:** Stelle sicher:
  ```yaml
  networks:
    mcp-app-net:
      external: true
    mcp-data-net:
      external: true
  ```

---

## FIX-011 — Zammad: puma.pid Pfad fehlt — aus v0.1

**Was ist passiert:**  
`mcp-zammad-rails` crashte mit: `No such file or directory @ rb_sysopen - /opt/zammad/tmp/pids/puma.pid (Errno::ENOENT)`

**Wie wurde lokal gefixt:**  
Volume-Mount versucht, aber nicht final gelöst.

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Service:** `zammad-rails`
  ```yaml
  volumes:
    - zammad-tmp:/opt/zammad/tmp
  ```
- **Service:** `zammad-websocket`
  ```yaml
  volumes:
    - zammad-tmp:/opt/zammad/tmp
  ```
- **Top-level volumes:** Füge hinzu:
  ```yaml
  volumes:
    zammad-tmp:
  ```
- **Zusätzlich** als Sicherheit im command/entrypoint:
  ```yaml
  command: ["sh", "-c", "mkdir -p /opt/zammad/tmp/pids && bundle exec rails server -b 0.0.0.0 -p 3000"]
  ```

---

## FIX-012 — Zammad: Falscher Command ("zammad run rake" existiert nicht) — aus v0.1

**Was ist passiert:**  
`mcp-zammad-init` crashed mit Exit 127: `exec: zammad: not found`. Das Zammad 6.4.1 Image hat kein `zammad` Binary.

**Wie wurde lokal gefixt:**  
Command auf `bundle exec rake` umgestellt. Init lief dann mit Exited (0).

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Service:** `zammad-init` — Command ändern:
  ```yaml
  command: ["bundle", "exec", "rake", "db:migrate", "db:seed"]
  ```
- **Service:** `zammad-rails` — Command ändern:
  ```yaml
  command: ["sh", "-c", "mkdir -p /opt/zammad/tmp/pids && bundle exec rails server -b 0.0.0.0 -p 3000"]
  ```
- **Service:** `zammad-websocket` — Command ändern:
  ```yaml
  command: ["sh", "-c", "mkdir -p /opt/zammad/tmp/pids && bundle exec script/websocket-server.rb start"]
  ```
- **Service:** `zammad-worker` — Command ändern:
  ```yaml
  command: ["bundle", "exec", "script/background-worker.rb", "start"]
  ```
- **Alle 4 Services** müssen dasselbe Image nutzen: `ghcr.io/zammad/zammad:6.4.1`

---

## FIX-013 — nginx: Upstream-Abhängigkeit (Grafana nicht da) — aus v0.1

**Was ist passiert:**  
`mcp-nginx` crashte beim Start: `upstream "grafana" not found`. nginx.conf referenziert Grafana (Phase 5), die in Phase 1 noch nicht existiert.

**Was im Code zu fixen ist:**

- **Datei:** `config/nginx/nginx.conf` (oder `config/nginx/conf.d/*.conf`)
- **Lösung A (empfohlen):** Verwende `resolver` mit Variablen statt statischer Upstreams:
  ```nginx
  # Statt:
  upstream grafana { server grafana:3000; }
  
  # Verwende:
  location /grafana {
      resolver 127.0.0.11 valid=30s;
      set $upstream_grafana grafana:3000;
      proxy_pass http://$upstream_grafana;
  }
  ```
  Dadurch startet nginx auch wenn der Upstream noch nicht existiert.
- **Lösung B:** Trenne die nginx-Configs in separate Dateien pro Phase und inkludiere nur die verfügbaren.
- **Datei:** `scripts/mcp-install.sh`
- **In Phase 1:** nginx erst starten NACHDEM die Phase-abhängigen Upstreams geklärt sind, oder nginx mit einer Minimal-Config starten.

---

## FIX-014 — PostgreSQL: CREATE EXTENSION vector auf falschem Container — aus v0.1

**Was im Code zu fixen ist:**

- **Datei:** `scripts/init-db.sh`
- **Entferne** die Zeile `CREATE EXTENSION IF NOT EXISTS vector;` aus dem Block, der auf `mcp-postgres` läuft.
- Die pgvector-Extension gehört NUR auf den `mcp-pgvector` Container.

---

## FIX-015 — Redis: vm.overcommit_memory Warnung — aus v0.1

**Was im Code zu fixen ist:**

- **Datei:** `scripts/mcp-install.sh`
- **Füge hinzu** in der Pre-Flight-Phase (Phase 0):
  ```bash
  # Redis optimization
  if [ "$(sysctl -n vm.overcommit_memory 2>/dev/null)" != "1" ]; then
    sysctl -w vm.overcommit_memory=1
    echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
    echo "[INFO] Set vm.overcommit_memory=1 for Redis"
  fi
  ```

---

## FIX-016 — Alle externen Volumes fehlen bei frischer Installation — aus v0.1

**Was im Code zu fixen ist:**

- **Datei:** `scripts/mcp-install.sh`
- **Füge hinzu** in Phase 0 (Pre-Flight), BEVOR irgendein Compose-Stack startet:
  ```bash
  echo "[INFO] Creating external volumes..."
  for v in \
    mcp-postgres-data mcp-redis-data mcp-pgvector-data mcp-openbao-data \
    mcp-keycloak-data mcp-n8n-data mcp-ntfy-data mcp-nginx-data \
    mcp-portainer-data mcp-vaultwarden-data mcp-zammad-data \
    mcp-elasticsearch-data mcp-bookstack-data mcp-bookstack-mariadb-data \
    mcp-diun-data mcp-crowdsec-data zammad-tmp; do
    docker volume create "$v" 2>/dev/null || true
  done
  echo "[INFO] Creating external networks..."
  for n in mcp-edge-net mcp-app-net mcp-data-net mcp-sec-net mcp-ai-net; do
    docker network create "$n" 2>/dev/null || true
  done
  ```
- **Wichtig:** Dieser Block muss IDEMPOTENT sein (darf bei erneutem Lauf nicht fehlschlagen).

---

## FIX-017 — YAML-Struktur in Ops-Compose — aus v0.1

**Was im Code zu fixen ist:**

- **Datei:** `compose/ops/docker-compose.yml`
- **Prüfe und stelle sicher:**
  1. Es gibt NUR EIN `services:` Schlüsselwort (ganz oben)
  2. Es gibt NUR EIN `networks:` Schlüsselwort (ganz unten, top-level)
  3. Es gibt NUR EIN `volumes:` Schlüsselwort (ganz unten, top-level)
  4. Top-level `networks:` ist ein Mapping (NICHT Liste):
     ```yaml
     # RICHTIG:
     networks:
       mcp-app-net:
         external: true
       mcp-data-net:
         external: true
     
     # FALSCH:
     networks:
       - mcp-app-net
       - mcp-data-net
     ```
  5. Service-level `networks:` ist eine Liste:
     ```yaml
     # RICHTIG (innerhalb service):
     services:
       zammad-rails:
         networks:
           - mcp-app-net
           - mcp-data-net
     ```
- **Validiere** nach jeder Änderung:
  ```bash
  docker-compose --env-file .env -f compose/ops/docker-compose.yml config >/dev/null && echo "OK"
  ```

---

## Validierung nach allen Fixes

Führe diese Befehle aus, um zu bestätigen, dass alle Compose-Dateien korrekt sind:

```bash
cd /opt/masdor/Masdor-MCP

echo "=== Validiere alle Compose-Dateien ==="
for f in core ops telemetry remote ai; do
  echo -n "$f: "
  docker-compose --env-file .env -f compose/$f/docker-compose.yml config >/dev/null 2>&1 \
    && echo "OK" || echo "FEHLER"
done

echo ""
echo "=== Prüfe .env auf unquoted Werte ==="
grep -nE '^[A-Z_]+=.*\s.*[^"]$' .env | grep -v '^#' || echo "OK: keine unquoted Werte mit Leerzeichen"

echo ""
echo "=== Prüfe doppelte YAML-Keys ==="
for f in compose/*/docker-compose.yml; do
  DUPS=$(grep -c "^services:" "$f")
  [ "$DUPS" -gt 1 ] && echo "FEHLER: $f hat $DUPS x 'services:'" || echo "OK: $f"
done
```

---

## Zusammenfassung aller betroffenen Dateien

| Datei | Fixes |
|---|---|
| `.env.example` | FIX-001, FIX-002 |
| `scripts/mcp-install.sh` | FIX-002, FIX-004, FIX-006, FIX-009, FIX-015, FIX-016 |
| `scripts/init-db.sh` | FIX-014 |
| `compose/ops/docker-compose.yml` | FIX-003, FIX-004, FIX-010, FIX-011, FIX-012, FIX-017 |
| `compose/telemetry/docker-compose.yml` | FIX-005, FIX-006 |
| `compose/ai/docker-compose.yml` | FIX-007, FIX-008 |
| `config/nginx/nginx.conf` oder `conf.d/` | FIX-013 |

---

*Generiert am 18.02.2026 aus Test v0.1 + v0.2 Ergebnissen*
