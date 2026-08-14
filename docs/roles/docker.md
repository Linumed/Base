# docker: Docker Engine

## Problem

Every Docker-based role in this repo (caddy, monitoring, bridgelink) needs Docker Engine
and the Compose plugin (`docker compose`) on the target host. Without a shared role,
each of them would either install Docker itself (code duplication) or abort with an
unclear error message when it's missing - that was exactly what happened with `caddy`
initially (issue #17). This role installs Docker from the official Docker apt repository
and runs in `playbooks/site.yml` before any role that needs Docker Compose.

## Variables

All variables are prefixed `docker_*` and have sensible defaults in
`ansible/roles/docker/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `docker_apt_release` | `{{ ansible_distribution_release }}` | Debian version codename for the Docker repo line |
| `docker_apt_release_fallback` | `"bookworm"` | Fallback if Docker hasn't published a repo for `docker_apt_release` yet (see below) |
| `docker_packages` | docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin | Packages installed |
| `docker_users` | `[]` | Users added to the `docker` group (root-equivalent access to the Docker socket - deliberately empty by default) |
| `docker_log_max_size` / `docker_log_max_file` | `"10m"` / `"3"` | Log rotation for container logs via `/etc/docker/daemon.json` |

## Why the official Docker repo, not `docker.io`

Debian's own `docker.io` package lags behind Docker releases and on some releases ships
no Compose v2 (`docker compose`, which this repo assumes as the standard) at all - only
the deprecated Python-based `docker-compose` v1, or nothing.

## Trixie fallback

Docker often doesn't publish its apt repo for a new Debian stable release until weeks or
months after it ships. The role checks over HTTP whether
`https://download.docker.com/linux/debian/dists/trixie/Release` exists, and falls back
to the `bookworm` line otherwise (`docker_apt_release_fallback`) - Docker's packages for
Debian are in practice compatible enough across releases for that to work. As soon as a
native Trixie repo exists, `docker_apt_release` picks it up automatically.

## What gets changed

- `/etc/apt/keyrings/docker.asc` (GPG key)
- `/etc/apt/sources.list.d/docker.list` (repo line)
- `/etc/docker/daemon.json` (log rotation)
- Docker packages via apt, the `docker.service` enabled and started

## Verification

```bash
docker compose version
systemctl is-active docker
```

## Pitfalls

- **Doesn't open any ufw rules.** Docker manages its own iptables/nftables rules for
  published container ports, independent of ufw - a port opened via `ports:` is
  reachable from outside despite `ufw deny incoming`, unless it's explicitly bound to
  `127.0.0.1`. See the `common` role for the general "Docker bypasses ufw" note.
- **`become: true` on the restart task is mandatory, not optional.** Without it, the call
  runs unprivileged, systemd routes it through PolicyKit, and it fails with `Failed to
  restart docker.service: Connection timed out` - waiting for a `pkttyagent` prompt that
  never comes over SSH. It looks like a D-Bus or hardware problem, but it's the same
  missing `become: true`, deterministically, every time. See
  `ansible/roles/common/README.md`, "become: true on every privileged task, no
  exceptions" - found and documented there first, initially missed here.
- **Rootless mode and private registries are out of scope** for v0.1.
