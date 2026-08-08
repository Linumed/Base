# caddy: Reverse Proxy

## Problem

Dienste hinter einem Reverse Proxy zu betreiben, der TLS-Zertifikate automatisch besorgt
und erneuert (ACME/Let's Encrypt), erspart manuelles Zertifikatsmanagement - ein häufiger
Grund für abgelaufene Zertifikate und damit Ausfälle. Diese Rolle stellt Caddy als
Docker-Compose-Stack bereit und generiert die Konfiguration (Caddyfile) aus Ansible-Variablen.

## Variablen

Alle Variablen haben den Präfix `caddy_*` und stehen mit sinnvollen Defaults in
`ansible/roles/caddy/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `caddy_image` | `"caddy:2.9.1-alpine"` | Gepinntes Image, kein `latest` |
| `caddy_deploy_dir` | `/opt/linumed-os/caddy` | Zielverzeichnis auf dem Host für Caddyfile und docker-compose.yml |
| `caddy_http_port` / `caddy_https_port` | `80` / `443` | Host-Ports. Caddy braucht beide für ACME HTTP-01 und normalen Traffic - **nicht** auf `127.0.0.1` einschränken, wie es sonst bei rein internen Diensten auf dieser Maschine üblich ist |
| `caddy_email` | `""` (aus) | ACME-Account-E-Mail für Let's-Encrypt-Benachrichtigungen. Leer ist gültig, aber nicht empfohlen |
| `caddy_sites` | `[]` | Liste von `{domain, reverse_proxy, extra}` - siehe Beispiel unten. Leer = Caddy läuft, tut aber nichts |

Beispiel:

```yaml
caddy_email: "admin@klinik-beispiel.de"
caddy_sites:
  - domain: "shifts.klinik-beispiel.de"
    reverse_proxy: "127.0.0.1:8080"
```

## Was wird verändert

- `{{ caddy_deploy_dir }}/Caddyfile` (Template, mit Backup und Validierung vor dem
  Deployment - siehe unten).
- `{{ caddy_deploy_dir }}/docker-compose.yml` (Template).
- Der Compose-Stack wird über `community.docker.docker_compose_v2` hochgefahren.

## Voraussetzungen

- Docker Engine und Compose-Plugin - bereitgestellt durch die `docker`-Rolle (siehe
  [docker: Docker Engine](docker.md)), die in `playbooks/site.yml` vor `caddy` läuft.
  `caddy` prüft das per Preflight (`docker compose version`) und bricht mit einer klaren
  Meldung ab, falls die Voraussetzung fehlt - z. B. beim eigenständigen Ausführen ohne die
  `docker`-Rolle.
- Collection `community.docker` (siehe `ansible/requirements.yml`):
  `ansible-galaxy collection install -r ansible/requirements.yml`
- ufw-Regeln für Port 80/tcp und 443/tcp selbst setzen (`common_ufw_extra_rules` in der
  `common`-Rolle) - Caddy öffnet ufw nicht selbst.

## Verifikation

```bash
docker compose -f /opt/linumed-os/caddy/docker-compose.yml ps
```

Erwartete Ausgabe: Container `linumed-os-caddy` mit Status `healthy`.

```bash
docker exec linumed-os-caddy caddy validate --config /etc/caddy/Caddyfile
```

Zusätzlich von außen: `curl -I https://<domain>` muss ein gültiges Zertifikat liefern
(kein `-k`/`--insecure` nötig), sobald DNS auf den Host zeigt und Port 80/443 erreichbar
sind - ACME HTTP-01 scheitert sonst stumm im Hintergrund.

## Stolperfallen

- **HTTP-01-Challenge scheitert lautlos**, wenn Port 80 nicht von außen erreichbar ist
  (ufw-Regel vergessen, oder der Host sitzt hinter einem NAT ohne Portweiterleitung). Caddy
  versucht es automatisch erneut, aber ohne erreichbaren Port 80 nie erfolgreich - im
  Zweifel `docker logs linumed-os-caddy` auf ACME-Fehler prüfen.
- **Caddyfile-Änderung löst keinen Container-Neustart aus**, sondern ein `caddy reload`
  im laufenden Container (zero-downtime). Das ist beabsichtigt: `docker_compose_v2`
  erkennt reine Datei-Änderungen im Bind-Mount nicht als Service-Änderung. Ein Wechsel von
  `caddy_image` oder den Ports läuft dagegen über den normalen Compose-Apply und kann den
  Container neu erstellen.
- **Nicht auf `127.0.0.1` binden**: anders als bei rein internen Diensten auf der
  Linumed-Dev-Maschine (siehe deren eigene `CLAUDE.md`) ist der ganze Zweck von Caddy hier,
  von außen erreichbar zu sein. `caddy_http_port`/`caddy_https_port` binden bewusst auf
  alle Interfaces.
