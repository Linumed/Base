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
| `caddy_deploy_dir` | `/opt/linumed-base/caddy` | Target directory on the host for the Caddyfile and docker-compose.yml |
| `caddy_http_port` / `caddy_https_port` | `80` / `443` | Host ports. Caddy needs both for ACME HTTP-01 and normal traffic - **do not** restrict them to `127.0.0.1`, unlike the usual convention for purely internal services on this machine |
| `caddy_email` | `""` (off) | ACME account email for Let's Encrypt notifications. Empty is valid, but not recommended |
| `caddy_sites` | `[]` | List of `{domain, reverse_proxy, extra}` - see the examples below. Empty = Caddy runs but does nothing |
| `caddy_external_network_name` | `"linumed-base-external"` | Docker network Caddy joins in addition to its own, so it can reach a container in a *different* Compose stack by service name - see below |

Two upstream shapes, depending on where the proxied service actually runs:

**A service running natively on the host** (not in Docker):

```yaml
caddy_email: "admin@example-clinic.org"
caddy_sites:
  - domain: "shifts.example-clinic.org"
    reverse_proxy: "host.docker.internal:8080"
```

**Not `127.0.0.1:8080`** - Caddy itself runs as a container, so `127.0.0.1` inside it
would mean Caddy itself, not the Docker host (issue #23). `host.docker.internal` works
because the role sets `extra_hosts: host-gateway` on the Caddy container.

**A service running in its own, separate Compose stack** (issue #39) - the common case,
since most operator applications are containerized. Loopback doesn't work here either,
for the same reason as above, and publishing on `0.0.0.0` to work around it would
contradict this kit's own firewall doctrine (a published container port bypasses ufw
entirely). The fix is a shared Docker network: the operator's compose file joins
`caddy_external_network_name` as `external: true` and Caddy reaches it by service name.

In the operator's own `docker-compose.yml` (not managed by this role):

```yaml
services:
  myapp:
    image: example/myapp:1.0
    # No `ports:` needed for Caddy to reach it - only publish one if the app also needs
    # to be reachable some other way. Loopback-only would still be unreachable from
    # Caddy (same reason as host.docker.internal above); the shared network is what
    # makes it reachable, not a port.
    networks:
      - default
      - linumed-base-external

networks:
  linumed-base-external:
    external: true
```

And in the inventory:

```yaml
caddy_sites:
  - domain: "myapp.example-clinic.org"
    reverse_proxy: "myapp:8080"   # the service name from the operator's own compose file
```

`myapp` resolves because both stacks' `myapp` and `caddy` containers now share the
`linumed-base-external` network - Docker's embedded DNS resolves service names to
container IPs within a shared network, the same mechanism `caddy_sites` targeting
another service in *this* stack (e.g. `bridgelink:8443`) already relies on.

## What gets changed

- `{{ caddy_deploy_dir }}/conf/Caddyfile` (template, with backup and validation before
  deployment - see below). Mounted into the container as a directory, not a single file -
  see [Pitfalls](#pitfalls), issue #44.
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
docker compose -f /opt/linumed-base/caddy/docker-compose.yml ps
```

Expected output: container `linumed-base-caddy` with status `healthy`.

```bash
docker exec linumed-base-caddy caddy validate --config /etc/caddy/Caddyfile
```

Also from outside: `curl -I https://<domain>` must return a valid certificate (no
`-k`/`--insecure` needed) once DNS points at the host and ports 80/443 are reachable -
otherwise ACME HTTP-01 fails silently in the background.

## Pitfalls

- **The HTTP-01 challenge fails silently** if port 80 isn't reachable from outside (a
  forgotten ufw rule, or the host sits behind NAT without port forwarding). Caddy retries
  automatically, but never succeeds without a reachable port 80 - when in doubt, check
  `docker logs linumed-base-caddy` for ACME errors.
- **A Caddyfile change doesn't trigger a container restart**, but a `caddy reload` inside
  the running container (zero downtime). That's intentional: `docker_compose_v2` doesn't
  detect a plain file change in the bind mount as a service change. Changing
  `caddy_image` or the ports, by contrast, goes through the normal Compose apply and can
  recreate the container.
- **Don't bind to `127.0.0.1`**: unlike purely internal services on the Linumed dev
  machine (see that machine's own `CLAUDE.md`), the whole point of Caddy here is to be
  reachable from outside. `caddy_http_port`/`caddy_https_port` deliberately bind to all
  interfaces.
- **The Caddyfile is bind-mounted as a directory (`./conf:/etc/caddy`), not a single
  file** (issue #44). A single-file bind mount attaches to the file's inode at container
  start; Ansible's `template` module rewrites atomically (temp file + rename), which would
  orphan a single-file mount - the container would keep serving the original content
  forever after the first change, with `caddy reload` reporting success and the
  healthcheck staying green throughout. If a manually created Caddyfile or a symlink
  workaround ever reappears here, this is why it's wrong.
