# caddy

Reverse proxy with automatic ACME/TLS, deployed as a single Docker Compose stack
(issue #6).

## Variables

See `defaults/main.yml`, all prefixed `caddy_*`. User-facing writeup with verification
steps: `docs/roles/caddy.md`.

## What this role does not do

- **Does not install Docker or the compose plugin.** That's the `docker` role (#17),
  which runs before `caddy` in `playbooks/site.yml`. This role only preflight-checks for
  `docker compose version` and fails with a clear message if it's missing - defense in
  depth for anyone running the caddy role standalone.
- **Does not open ufw ports.** Set `common_ufw_extra_rules` (see the `common` role) to
  open 80/tcp and 443/tcp - Caddy needs both reachable for HTTP-01 ACME challenges and
  regular traffic. Unlike the Docker stacks on the dev server itself, Caddy is *meant* to
  be reachable from the LAN/internet - do not bind its ports to 127.0.0.1.

## Two docker-compose.yml files, deliberately

`docker/caddy/docker-compose.yml` is a static, hand-maintained reference for spinning
Caddy up manually (local testing, `.env`-driven) - not a guaranteed mirror, see
[ADR 0005](../../../docs/adr/0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md).
`ansible/roles/caddy/templates/docker-compose.yml.j2` is what actually gets deployed by
this role - it uses Ansible variables instead of `.env`, since the role already owns the
whole config lifecycle. They're kept close in structure on purpose; bump `caddy_image`
here *and* the image tag in `docker/caddy/` together.

## Validation and rollback

Mirrors the pattern in `common`'s SSH role: the Caddyfile is deployed with `backup: true`,
then validated with `docker run ... caddy validate` using the same pinned image that will
actually run it. On failure, the previous Caddyfile (or no file, if this was the first
deploy) is restored before the play fails - the stack is never left pointed at a Caddyfile
that doesn't parse.

## Reaching a container in a different Compose stack (issue #39)

Caddy joins a second Docker network in addition to its own project network -
`caddy_external_network_name`, default `linumed-os-external`, created unconditionally
(an unused bridge network costs nothing and publishes nothing on its own; ufw is
unaffected either way, since this is network membership, not a published port). The
Compose-local key and the actual Docker network name are deliberately the same literal
string via `name:` - not left to Compose's default `<project>_<key>` derivation, since an
operator's entirely separate Compose stack needs a name that stays stable regardless of
what this stack's project name happens to be. That's the piece `docs/roles/caddy.md`'s
worked example is about: the operator's own compose file joins the same name as
`external: true`, and `caddy_sites` then reaches it by service name, the same way it
already reaches `bridgelink:8443` within this stack.

## Reload vs. recreate

A Caddyfile-only change (`caddy_sites` edit) triggers the `Reload caddy` handler
(`caddy reload` inside the running container, zero downtime) rather than a container
recreate - `docker_compose_v2` doesn't recreate a container over a bind-mounted file
change, since it diffs the *service definition*, not mounted file content. A
`docker-compose.yml.j2` change (image bump, port change) goes through
`community.docker.docker_compose_v2` normally, which does recreate when the service
definition itself changes.
