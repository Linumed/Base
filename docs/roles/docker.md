# docker: Docker Engine

## Problem

Jede Docker-basierte Rolle in diesem Repo (caddy, künftig mirth-connect und monitoring)
braucht Docker Engine und das Compose-Plugin (`docker compose`) auf dem Zielhost. Ohne
eine gemeinsame Rolle würde jede von ihnen entweder Docker selbst installieren
(Code-Duplikation) oder mit einer unklaren Fehlermeldung abbrechen, wenn es fehlt - genau
das war bei `caddy` zunächst der Fall (Issue #17). Diese Rolle installiert Docker aus dem
offiziellen Docker-Apt-Repository und läuft in `playbooks/site.yml` vor jeder Rolle, die
Docker Compose braucht.

## Variablen

Alle Variablen haben den Präfix `docker_*` und stehen mit sinnvollen Defaults in
`ansible/roles/docker/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `docker_apt_release` | `{{ ansible_distribution_release }}` | Codename der Debian-Version für die Docker-Repo-Zeile |
| `docker_apt_release_fallback` | `"bookworm"` | Fallback, falls Docker noch kein Repo für `docker_apt_release` veröffentlicht hat (siehe unten) |
| `docker_packages` | docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin | Installierte Pakete |
| `docker_users` | `[]` | Benutzer, die der `docker`-Gruppe hinzugefügt werden (Root-äquivalenter Zugriff auf den Docker-Socket - bewusst leer per Default) |
| `docker_log_max_size` / `docker_log_max_file` | `"10m"` / `"3"` | Log-Rotation für Container-Logs über `/etc/docker/daemon.json` |

## Warum das offizielle Docker-Repo, nicht `docker.io`

Debians eigenes `docker.io`-Paket hinkt Docker-Releases hinterher und liefert auf manchen
Releases kein Compose v2 (`docker compose`, das dieses Repo als Standard voraussetzt),
sondern nur das veraltete Python-basierte `docker-compose` v1 oder gar nichts.

## Trixie-Fallback

Docker veröffentlicht sein Apt-Repo für eine neue Debian-Stable-Version oft erst Wochen
bis Monate nach deren Release. Die Rolle prüft per HTTP, ob
`https://download.docker.com/linux/debian/dists/trixie/Release` existiert, und weicht
sonst auf die `bookworm`-Zeile aus (`docker_apt_release_fallback`) - Docker-Pakete für
Debian sind in der Praxis release-übergreifend kompatibel genug dafür. Sobald ein
natives Trixie-Repo existiert, greift `docker_apt_release` automatisch darauf zu.

## Was wird verändert

- `/etc/apt/keyrings/docker.asc` (GPG-Schlüssel)
- `/etc/apt/sources.list.d/docker.list` (Repo-Zeile)
- `/etc/docker/daemon.json` (Log-Rotation)
- Docker-Pakete via apt, Dienst `docker.service` aktiviert und gestartet

## Verifikation

```bash
docker compose version
systemctl is-active docker
```

## Stolperfallen

- **Öffnet keine ufw-Regeln.** Docker verwaltet seine eigenen iptables/nftables-Regeln für
  veröffentlichte Container-Ports, unabhängig von ufw - ein per `ports:` freigegebener
  Port ist trotz `ufw deny incoming` von außen erreichbar, außer er ist explizit auf
  `127.0.0.1` gebunden. Siehe die `common`-Rolle für den generellen "Docker umgeht ufw"-Hinweis.
- **`become: true` ist auf dem Restart-Task Pflicht, keine Ausnahme.** Fehlt es, läuft
  der Aufruf unprivilegiert, systemd routet ihn über PolicyKit, und er scheitert mit
  `Failed to restart docker.service: Connection timed out` - wartet auf eine
  `pkttyagent`-Freigabe, die über SSH nie kommt. Sieht aus wie ein D-Bus-/Hardware-Problem,
  ist aber deterministisch dasselbe fehlende `become: true` bei jedem Lauf. Siehe
  `ansible/roles/common/README.md`, Abschnitt "become: true auf jedem privilegierten Task,
  keine Ausnahmen" - dort zuerst gefunden und dokumentiert, hier zunächst übersehen.
- **Rootless Mode und eigene Registries sind out of scope** für v0.1.
