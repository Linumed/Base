# caddy: Reverse Proxy

## Problem

Running services behind a reverse proxy that fetches and renews TLS certificates
automatically (ACME/Let's Encrypt) saves manual certificate management - a common cause
of expired certificates and the outages that follow. This role deploys Caddy as a Docker
Compose stack and generates its configuration (Caddyfile) from Ansible variables.

## Variables

All variables are prefixed `caddy_*` and have sensible defaults in
`ansible/roles/caddy/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `caddy_image` | `"caddy:2.11.4-alpine"` | Pinned image, never `latest` |
| `caddy_deploy_dir` | `/opt/linumed-os/caddy` | Target directory on the host for the Caddyfile and docker-compose.yml |
| `caddy_http_port` / `caddy_https_port` | `80` / `443` | Host ports. Caddy needs both for ACME HTTP-01 and normal traffic - **do not** restrict them to `127.0.0.1`, unlike the usual convention for purely internal services on this machine |
| `caddy_email` | `""` (off) | ACME account email for Let's Encrypt notifications. Empty is valid, but not recommended |
| `caddy_sites` | `[]` | List of `{domain, reverse_proxy, extra}` - see the example below. Empty = Caddy runs but does nothing |

Example for a service running natively on the host (not in Docker):

```yaml
caddy_email: "admin@example-clinic.org"
caddy_sites:
  - domain: "shifts.example-clinic.org"
    reverse_proxy: "host.docker.internal:8080"
```

**Not `127.0.0.1:8080`** - Caddy itself runs as a container, so `127.0.0.1` inside it
would mean Caddy itself, not the Docker host (issue #23). `host.docker.internal` works
because the role sets `extra_hosts: host-gateway` on the Caddy container. For a service
in another Compose stack, you instead need a shared Docker network and the service name
as the hostname - this role doesn't automate that yet.

## What gets changed

- `{{ caddy_deploy_dir }}/Caddyfile` (template, with backup and validation before
  deployment - see below).
- `{{ caddy_deploy_dir }}/docker-compose.yml` (template).
- The Compose stack is brought up via `community.docker.docker_compose_v2`.

## Prerequisites

- Docker Engine and the Compose plugin - provided by the `docker` role (see
  [docker: Docker Engine](docker.md)), which runs before `caddy` in `playbooks/site.yml`.
  `caddy` checks this via a preflight (`docker compose version`) and aborts with a clear
  message if the prerequisite is missing - e.g. when run standalone without the `docker`
  role.
- The `community.docker` collection (see `ansible/requirements.yml`):
  `ansible-galaxy collection install -r ansible/requirements.yml`
- Set the ufw rules for ports 80/tcp and 443/tcp yourself (`common_ufw_extra_rules` in
  the `common` role) - Caddy doesn't open ufw itself.

## Verification

```bash
docker compose -f /opt/linumed-os/caddy/docker-compose.yml ps
```

Expected output: container `linumed-os-caddy` with status `healthy`.

```bash
docker exec linumed-os-caddy caddy validate --config /etc/caddy/Caddyfile
```

Also from outside: `curl -I https://<domain>` must return a valid certificate (no
`-k`/`--insecure` needed) once DNS points at the host and ports 80/443 are reachable -
otherwise ACME HTTP-01 fails silently in the background.

## Pitfalls

- **The HTTP-01 challenge fails silently** if port 80 isn't reachable from outside (a
  forgotten ufw rule, or the host sits behind NAT without port forwarding). Caddy retries
  automatically, but never succeeds without a reachable port 80 - when in doubt, check
  `docker logs linumed-os-caddy` for ACME errors.
- **A Caddyfile change doesn't trigger a container restart**, but a `caddy reload` inside
  the running container (zero downtime). That's intentional: `docker_compose_v2` doesn't
  detect a plain file change in the bind mount as a service change. Changing
  `caddy_image` or the ports, by contrast, goes through the normal Compose apply and can
  recreate the container.
- **Don't bind to `127.0.0.1`**: unlike purely internal services on the Linumed dev
  machine (see that machine's own `CLAUDE.md`), the whole point of Caddy here is to be
  reachable from outside. `caddy_http_port`/`caddy_https_port` deliberately bind to all
  interfaces.
