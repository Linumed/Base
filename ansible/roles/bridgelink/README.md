# bridgelink

HL7 v2 integration engine plus its PostgreSQL backend, as a Docker Compose stack
(issue #12). No FHIR data type ships with the engine - see the FHIR section in
`docs/roles/bridgelink.md` for what is and is not possible (issue #97).

## Why BridgeLink and not Mirth Connect

**BridgeLink is not a replacement for Mirth Connect - it is the same codebase under a
different name.** Same channel XML, same Administrator, same transformers and connectors;
the Java packages are still `com.mirth.connect`. NextGen moved Mirth Connect to a
proprietary licence in March 2025 and the open-source lineage continued under new names.

Full reasoning, the alternatives that were evaluated (Open Integration Engine, licensed
Mirth 4.6+, frozen 4.5.2), the downsides this buys us, and the conditions under which the
decision should be revisited: **[ADR 0001](../../../docs/adr/0001-bridgelink-statt-mirth-connect.md)**.

Short version: licensed Mirth 4.6+ violates the FOSS-only rule (and has no public
container image), frozen 4.5.2 gets no security fixes, and OIE - which has the better
governance - publishes no container image for its current release. BridgeLink is the only
option that is simultaneously open source, currently patched, and deployable without
building an image ourselves.

## Which image variant

`innovarhealthcare/bridgelink:26.6.0-dhi-slim`:

- **`-dhi`** is the Docker Hardened Image build: Amazon Corretto on **Debian 13** (the
  same base OS this repo targets), **no shell, no package manager**, non-root **UID
  65532**, and upstream CI gates the build on fixable HIGH/CRITICAL OS-package findings
  from Trivy.
- **`-slim`** additionally strips the legacy Swing admin client from the image. The
  server and its REST API are unaffected; only Java Web Start launching of the Swing
  client and the `/` landing page are dropped. Web Start has been dead since JDK 11 -
  administration happens through the standalone Administrator Launcher (also MPL-2.0) or
  the separate WebAdmin container. Less image, less attack surface, nothing real lost.

The Rocky Linux variant (`26.6.0`) was not chosen. Its only genuine advantage is that a
shell is present, so an exec-form healthcheck would work - not worth the larger CVE
surface and a base OS that doesn't match the target system.

## Variables

See `defaults/main.yml`, all prefixed `bridgelink_*`. User-facing writeup with
verification steps: `docs/roles/bridgelink.md`.

Four have **no default** and the role's preflight refuses to run without them:
`bridgelink_db_password`, `bridgelink_keystore_storepass`, `bridgelink_keystore_keypass`,
`bridgelink_server_id`. Supply via Ansible Vault.

`bridgelink_exporter_user` and `bridgelink_exporter_password` join that list only when
`bridgelink_exporter_enabled` is true - a second, separate preflight, so the error message
can name the switch that actually caused it.

`docker/bridgelink/docker-compose.yml` is a static, `.env`-driven reference for spinning
BridgeLink up manually without Ansible - a hand-maintained testing convenience, not a
guaranteed mirror (see [ADR 0005](../../../docs/adr/0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md)).
Bump `bridgelink_image` here *and* the image tag in `docker/bridgelink/` together.

## Secrets are files, not environment variables

Database and keystore passwords go into `{{ bridgelink_deploy_dir }}/secrets/` (directory
0700, root-owned) and reach the container as Docker secrets. `mirth.properties` and
`exporter_password` are owned by **UID 65532, mode 0400** - not root: Compose bind-mounts
a file-based secret with the host's ownership intact, and the `-dhi` image runs
unprivileged, so a root-owned 0600 file makes the container die with
`AccessDeniedException on /run/secrets/mirth_properties` in a restart loop. `db_password`
stays root-owned 0600 because the Postgres entrypoint reads it before dropping
privileges.

None of them are passed as environment variables, deliberately: env vars are readable by
anyone who can run `docker inspect` and are written into the container's config JSON on
disk.

`.gitignore` excludes `docker/*/secrets/` so a local test run can never accidentally
commit credentials.

## Monitoring

BridgeLink serves no `/metrics` of its own (verified: `GET /metrics` is a 404 on
`26.6.0-dhi-slim`), so cAdvisor's container CPU/RAM was the only signal Prometheus had for
it - which cannot show a stopped channel or a filling queue. `files/bridgelink_exporter.py`
runs as an opt-in sidecar and translates the REST API into metrics. Why a script rather
than `json_exporter` or one of the community exporters, and the measurements behind that
choice: `docs/roles/bridgelink.md`, section "Monitoring".

Prometheus reaches it by container name over `linumed-base-metrics`, a network the
monitoring role creates and this stack joins as `external: true` - not over a host port.
A loopback-published container port is unreachable from another container, and an
all-interfaces one bypasses ufw; `host.docker.internal` is valid only for native services
like Node Exporter (issue #64). Consequence: with the exporter enabled, the monitoring role
must have run on the host first.

## Exposure

Only the admin/API port and, when enabled, the exporter port are published, and only on
`127.0.0.1` - reachable through an SSH
tunnel, not from the network. PostgreSQL gets no host port at all; only BridgeLink talks
to it, over the stack's own Compose network.

**Channel listeners are not published by this role.** An HL7 MLLP listener or an inbound
HTTP channel needs its port reachable by the sending system, which is a per-deployment
decision with real security consequences - and a published container port bypasses ufw
entirely (see the `common` role's ufw documentation). Publishing them is left to the
operator, deliberately.

## What this role does not do

- Does not install Docker - see the `docker` role, which runs before this one in
  `playbooks/site.yml`.
- Does not deploy WebAdmin (its own container upstream) - out of scope for v0.1.
- Does not create or import channels. An empty engine is the deliverable; channels are
  the clinic's own integration work.
- Does not publish channel ports (see above).
- Does not put BridgeLink behind Caddy - same reasoning as monitoring in v0.1.
- Does not create the BridgeLink user the Prometheus exporter authenticates as. That user
  database belongs to the operator and only exists after the first Administrator login,
  which is why the exporter is opt-in (issue #60).
