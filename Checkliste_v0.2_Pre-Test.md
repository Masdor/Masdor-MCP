# Masdor-MCP v0.2 — Pre-Test Checkliste

**Zweck:** Alle Reparaturen aus Test v0.1 prüfen, bevor der nächste Testlauf gestartet wird.  
**Datum:** _______________  
**Geprüft von:** _______________

---

## 1. Kritische Fixes (MUSS vor Test v0.2)

### 1.1 Ops Compose YAML reparieren (P2-006)

- [ ] `compose/ops/docker-compose.yml` öffnen
- [ ] Kein doppeltes `services:` im File (nur 1x ganz oben)
- [ ] Kein doppeltes `networks:` im File (nur 1x ganz unten)
- [ ] Top-level `networks:` ist ein **Mapping** (nicht Liste):
  ```yaml
  networks:
    mcp-app-net:
      external: true
    mcp-data-net:
      external: true
  ```
- [ ] YAML validieren:
  ```bash
  docker-compose --env-file .env -f compose/ops/docker-compose.yml config >/dev/null && echo "OK"
  ```
- [ ] Ausgabe: `OK` (kein Fehler)

### 1.2 Zammad Netzwerk-Isolation fixen (P2-005)

- [ ] `zammad-rails` hat networks: `mcp-app-net` + `mcp-data-net`
- [ ] `zammad-websocket` hat networks: `mcp-app-net` + `mcp-data-net`
- [ ] `zammad-worker` hat networks: `mcp-app-net` + `mcp-data-net`
- [ ] `zammad-init` hat networks: `mcp-app-net` + `mcp-data-net`
- [ ] Prüfen: Redis-Alias erreichbar:
  ```bash
  docker exec mcp-zammad-rails ping -c1 redis
  ```

### 1.3 Zammad Puma PID-Pfad fixen (P2-004)

- [ ] Volume `zammad-tmp` in compose definiert:
  ```yaml
  volumes:
    zammad-tmp:
  ```
- [ ] Volume gemountet bei `zammad-rails`:
  ```yaml
  volumes:
    - zammad-tmp:/opt/zammad/tmp
  ```
- [ ] Volume gemountet bei `zammad-websocket`:
  ```yaml
  volumes:
    - zammad-tmp:/opt/zammad/tmp
  ```
- [ ] Alternativ: `mkdir -p /opt/zammad/tmp/pids` im command

### 1.4 Zammad Commands prüfen (P2-002)

- [ ] `zammad-init` command: `bundle exec rake db:migrate db:seed`
- [ ] `zammad-rails` command: `bundle exec rails server -b 0.0.0.0 -p 3000` (oder offizieller entrypoint)
- [ ] `zammad-websocket` command: `bundle exec script/websocket-server.rb start`
- [ ] `zammad-worker` command: `bundle exec script/background-worker.rb start`
- [ ] Alle 4 Services nutzen gleiches Image: `ghcr.io/zammad/zammad:6.4.1`

### 1.5 BookStack APP_KEY generieren (P2-003)

- [ ] Key generiert:
  ```bash
  docker run -it --rm --entrypoint /bin/bash lscr.io/linuxserver/bookstack:24.12.1 \
    -lc 'php -r "echo \"base64:\".base64_encode(random_bytes(32)).PHP_EOL;"'
  ```
- [ ] Key in `.env` eingetragen: `BOOKSTACK_APP_KEY=base64:...`
- [ ] `.env` Berechtigungen: `chmod 600 .env`

---

## 2. Warnungen beheben (SOLLTE vor Test v0.2)

### 2.1 Redis Sysctl-Warnung (P1-005)

- [ ] In `/etc/sysctl.conf` hinzufügen:
  ```
  vm.overcommit_memory = 1
  ```
- [ ] Aktivieren: `sysctl -p`
- [ ] Prüfen: `sysctl vm.overcommit_memory` → Ausgabe: `= 1`

### 2.2 PostgreSQL init-db.sh bereinigen (P1-004)

- [ ] `scripts/init-db.sh` öffnen
- [ ] `CREATE EXTENSION vector` entfernen (läuft nur auf pgvector-Container)
- [ ] Prüfen: Keine vector-Referenz mehr in init-db.sh

### 2.3 REDIS_PASSWORD rotieren

- [ ] Neues Passwort generiert
- [ ] In `.env` aktualisiert: `REDIS_PASSWORD=neues_passwort`
- [ ] Altes Passwort war in Logs sichtbar → Logs bereinigen:
  ```bash
  docker logs mcp-redis 2>&1 | head -5  # nach Neustart keine alten Logs
  ```

### 2.4 nginx Config modularisieren (P1-002)

- [ ] `config/nginx/conf.d/` prüfen — Upstreams nur für gestartete Stacks
- [ ] Option A: Pro Phase eigene `.conf`-Dateien
- [ ] Option B: Upstream-Blöcke mit `resolver` und `set $upstream` (lazy DNS)
- [ ] nginx startet ohne Fehler auch wenn Grafana/Zabbix noch nicht laufen

---

## 3. Pre-Flight vor Teststart

### 3.1 Alle Volumes vorhanden

```bash
for v in \
  mcp-postgres-data mcp-redis-data mcp-pgvector-data mcp-openbao-data \
  mcp-keycloak-data mcp-n8n-data mcp-ntfy-data mcp-nginx-data \
  mcp-portainer-data mcp-vaultwarden-data mcp-zammad-data \
  mcp-elasticsearch-data mcp-bookstack-data mcp-bookstack-mariadb-data \
  mcp-diun-data zammad-tmp; do
  docker volume inspect "$v" >/dev/null 2>&1 && echo "OK: $v" || echo "FEHLT: $v"
done
```

- [ ] Alle Volumes zeigen `OK`

### 3.2 Alle Netzwerke vorhanden

```bash
for n in mcp-edge-net mcp-app-net mcp-data-net mcp-sec-net mcp-ai-net; do
  docker network inspect "$n" >/dev/null 2>&1 && echo "OK: $n" || echo "FEHLT: $n"
done
```

- [ ] Alle Netzwerke zeigen `OK`

### 3.3 Compose-Dateien validieren

```bash
for f in core ops telemetry remote ai; do
  echo "--- $f ---"
  docker-compose --env-file .env -f compose/$f/docker-compose.yml config >/dev/null 2>&1 \
    && echo "OK" || echo "FEHLER"
done
```

- [ ] Alle 5 Stacks zeigen `OK`

### 3.4 .env vollständig

- [ ] `POSTGRES_PASSWORD` gesetzt
- [ ] `REDIS_PASSWORD` gesetzt (neues Passwort!)
- [ ] `KEYCLOAK_ADMIN_PASSWORD` gesetzt
- [ ] `BOOKSTACK_APP_KEY` gesetzt
- [ ] `N8N_ENCRYPTION_KEY` gesetzt
- [ ] `chmod 600 .env` bestätigt

### 3.5 System-Ressourcen

```bash
free -h | grep Mem
df -h / /var /home
docker system df
```

- [ ] RAM: min. 16 GB frei
- [ ] Disk /var: min. 10 GB frei
- [ ] Docker: keine verwaisten Images/Container

### 3.6 Alte Container aufräumen

```bash
docker ps -a --filter "status=exited" --format "{{.Names}}"
docker system prune -f
```

- [ ] Keine alten mcp-* Container im Status `Exited` oder `Restarting`

---

## 4. Test v0.2 Startfreigabe

| Prüfpunkt | Status |
|---|---|
| Alle kritischen Fixes (Abschnitt 1) erledigt | ☐ |
| Alle Warnungen (Abschnitt 2) behoben | ☐ |
| Pre-Flight (Abschnitt 3) bestanden | ☐ |
| .env gesichert / Backup erstellt | ☐ |
| Git commit mit allen Fixes gepusht | ☐ |

**Freigabe:** ☐ Ja / ☐ Nein

**Unterschrift:** _______________  **Datum:** _______________

---

*Generiert am 18.02.2026 — Masdor-MCP Test Report v0.1*
