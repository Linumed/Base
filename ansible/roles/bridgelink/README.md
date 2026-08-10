# bridgelink

HL7/FHIR integration engine plus its PostgreSQL backend, as a Docker Compose stack
(issue #12).

## Why BridgeLink and not Mirth Connect

The original plan (`ARCHITECTURE.md`) called for Mirth Connect. That is no longer
possible under this repo's FOSS-only rule: NextGen Healthcare moved Mirth Connect to a
**single commercial, proprietary licence in March 2025**. From 4.6 onwards the source is
closed. The last MPL-2.0 release is 4.5.2, and it is frozen - no further security fixes.

Shipping 4.5.2 would repeat the mistake this repo already rejected once, when Promtail
was dropped from the monitoring role for being EOL and unpatched.

Two community forks of the last open-source Mirth codebase exist, both MPL-2.0:

| | Open Integration Engine (OIE) | **BridgeLink** (chosen) |
|---|---|---|
| Governance | Vendor-neutral, non-profit steering committee | Single vendor (Innovar Healthcare) |
| Current release | 4.6.0 (Java 17, 24 CVEs remediated) | 26.6.0 |
| Published container image | **only 4.5.2, from Aug 2025** - no 4.6.0 image | current, published alongside each release |

OIE has the better governance model on paper - and it is the structure specifically
designed to prevent a repeat of the NextGen situation. It lost on a practical point:
there is no published container image for its current release, so using it would mean
either building our own image (impractical for the target audience - clinic IT service
providers without a registry) or shipping the year-old 4.5.2 image with its known CVEs.

This decision is worth revisiting once OIE publishes images for current releases
(tracked upstream as OpenIntegrationEngine/engine#40). Both forks descend from the same
Mirth codebase and channels are portable between them, so a later switch is not a
rewrite.

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

See `defaults/main.yml`, all prefixed `bridgelink_*`. German user-facing writeup with
verification steps: `docs/roles/bridgelink.md`.

Four have **no default** and the role's preflight refuses to run without them:
`bridgelink_db_password`, `bridgelink_keystore_storepass`, `bridgelink_keystore_keypass`,
`bridgelink_server_id`. Supply via Ansible Vault.

## Secrets are files, not environment variables

Database and keystore passwords go into `{{ bridgelink_deploy_dir }}/secrets/` (mode
0600, root-owned, directory 0700) and reach the container as Docker secrets. They are
deliberately **not** passed as environment variables: env vars are readable by anyone who
can run `docker inspect` and are written into the container's config JSON on disk.

`.gitignore` excludes `docker/*/secrets/` so a local test run can never accidentally
commit credentials.

## Exposure

Only the admin/API port is published, and only on `127.0.0.1` - reachable through an SSH
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
