# ARCHITECTURE.md - Linumed Base

## Overview

Linumed Base is not a custom operating system and not a bootable image.
It is an Infrastructure-as-Code kit built on Ansible that turns a
standard Debian 13 (Trixie) installation into a hardened, GDPR-compliant
healthcare infrastructure platform.

The target audience is IT departments and system administrators at
clinics and care facilities who want to run open-source software but
don't have the time or expertise to build a healthcare-compliant stack
from scratch.

---

## Design principles

**On-premise by design**
Linumed Base is built to run in the institution's own infrastructure.
There is no cloud dependency, no telemetry call-home, no SaaS
component. All data stays in-house.

**GDPR as a constraint, not a feature**
Data protection requirements are built into every design decision:
local data storage, encrypted backups, a minimal logging surface, no
transfer of personal data to third parties.

**Idempotency**
All Ansible playbooks are idempotent. A second run produces no
changes. That is a hard requirement, not a recommendation.

**FOSS-only in the core**
Every component of Linumed Base is free open-source software.
Linumed Shifts (the commercial product) is not part of this repository
and is licensed separately.

**EU infrastructure**
No dependencies on US-only services. Pulling images from Docker Hub is
accepted, but images run on EU infrastructure. EU-based alternatives
are preferred for CI/CD.

---

## Target architecture (v0.1)

![What runs where on a Linumed Base host: a Docker Engine group holding the Caddy,
BridgeLink and monitoring stacks, and a second group of services that run natively -
ufw/fail2ban/SSH hardening, Node Exporter and restic.](docs/img/01-what-runs-where.svg)

Deliberately two figures rather than one. This one answers *what runs where* and carries
no arrows at all; the flows are the next one. The previous single diagram mixed
containment with three different kinds of arrow - a security property, a data flow and a
backup operation - and drew two of them at the Docker group's boundary, which is the one
thing the renderer reliably gets wrong (issue #65).

![What reports to whom: restic feeds the Node Exporter's textfile collector; Node
Exporter, cAdvisor and the BridgeLink exporter all scrape into Prometheus; Alloy ships
logs to Loki; Prometheus and Loki both feed Grafana, and Prometheus also feeds
Alertmanager.](docs/img/02-what-reports-to-whom.svg)

---

## Components

### common (Ansible role)

Base hardening of the Debian system. Always runs first.

Covers:
- SSH hardening (PasswordAuthentication off, configurable port, AllowUsers)
- ufw firewall (default deny incoming, only explicitly allowed ports)
- fail2ban (SSH brute-force protection)
- unattended-upgrades (automatic security updates)
- timezone and NTP configuration
- basic system packages

### caddy (Ansible role)

Caddy as a reverse proxy with automatic TLS via ACME (Let's Encrypt or
a private CA), run as a Docker Compose stack.

Configuration via a Caddyfile, generated from Ansible templates.

Design decision - Caddy as a container, not native on the host:
the original plan was to run Caddy natively so TLS termination would
survive a Docker restart. Checked (as of 2026-08-10): Debian 13 ships
`caddy` at version 2.6.2 with 11 open security issues in the Debian
security tracker, while the container runs current upstream 2.11.x.
For the most exposed component in the whole stack, "native" would
therefore not be safer but measurably less safe - the patch-cadence
advantage that would otherwise justify running native works against it
here. The original availability argument barely holds either: if every
backend is itself a container, a surviving Caddy with no reachable
upstream just returns `502` instead of `connection refused` - no
practical gain. A real kill switch (e.g. during a security incident)
belongs in its own documented network-level procedure (`ufw deny`,
interface down) in the operations runbook, not as a side effect of
where the proxy runs.

Docker publishes container ports past ufw (see the security model
below) - for Caddy that's intentional on 80/443, since the proxy has to
be reachable from outside. Any *further* `ports:` entry in this Compose
stack has to account for that trap deliberately.

### bridgelink (Ansible role)

HL7/FHIR integration engine, run as a Docker Compose stack.
The engine used is **BridgeLink**.

This is not a replacement for Mirth Connect, but **the same codebase
under a different name**: same channel XML, same administrator, same
transformers and connectors - the Java packages are still called
`com.mirth.connect`. NextGen Healthcare moved Mirth Connect to a purely
commercial, proprietary license in March 2025 (source closed from 4.6
onward); the open-source line has continued under new names since, and
Linumed Base follows that open line. Mirth Connect remains the industry's
de-facto standard - channels are portable between all variants, so an
institution keeps its integration work if it ever wants to switch.

Full reasoning, including evaluated alternatives (Open Integration
Engine, licensed Mirth 4.6+, frozen 4.5.2), accepted downsides and
revision triggers:
[ADR 0001](https://github.com/Linumed/Base/blob/main/docs/adr/0001-bridgelink-statt-mirth-connect.md).

Protocols supported out of the box: HL7 v2.x, FHIR R4, DICOM, CSV, XML,
database connectors.

Docker Compose stack:
- BridgeLink (hardened image: Debian 13, no shell, non-root)
- PostgreSQL (configuration and message database)

Only the admin/API port is published, and only on `127.0.0.1`. Channel
ports (HL7 MLLP or similar) are deliberately not published by the role
- that's a per-site decision.

### monitoring (Ansible role)

Observability stack. Most components run as a Docker Compose stack;
Node Exporter runs natively.

Components:
- Prometheus - metrics scraping and storage (container)
- Grafana - dashboards, three vendored default dashboards included
  (host overview, container overview, log explorer) - deliberately
  generic infrastructure dashboards, not clinical or patient-related:
  the monitoring stack sees metrics and logs, not the integration
  engine's message contents; bound to `127.0.0.1` only by default,
  access via SSH tunnel (container)
- Loki - log aggregation (container)
- **Grafana Alloy** - ships host and container logs to Loki
  (container). Replaces Promtail, which reached end-of-life on
  2026-03-02 and gets no more security fixes - not an option for a
  GDPR-focused kit.
- Alertmanager - alert routing (container)
- Node Exporter - host metrics (CPU, RAM, disk, network). **Native
  Debian package** instead of a container: gets security updates
  automatically through the existing unattended-upgrades role, needs
  no `--pid=host`/rootfs mounts, and ufw can actually protect the port
  - with a published container port that protection would be
  ineffective (see the security model below).
- cAdvisor - container metrics (container)

cAdvisor covers every container generically, which is why the gap it
leaves is easy to miss: for BridgeLink it reports CPU, RAM and network
of the process, and nothing about whether messages are actually moving.
A stopped channel or a queue that stops draining looks identical to an
idle, healthy engine from the outside. BridgeLink exposes no `/metrics`
of its own, so the `bridgelink` role ships an opt-in exporter sidecar
that translates its REST API into channel-level metrics.

Prometheus reaches that sidecar by container name over a shared Docker
network (`linumed-base-metrics`), not over a host port - the two stacks
are separate Compose projects, and neither a loopback-published port
(unreachable from another container) nor an all-interfaces one
(bypasses ufw) is an option. The Node Exporter job's
`host.docker.internal` works only because Node Exporter is a native
service, not a container. Both switches
(`bridgelink_exporter_enabled`, `monitoring_scrape_bridgelink`) are off
by default - see `docs/roles/bridgelink.md`.

Retention is split by data kind, not a single global value: metrics
(`monitoring_metrics_retention_days`, default 90) and logs
(`monitoring_logs_retention_days`, default 30, shorter) - logs can
contain personal data (IP addresses, usernames), so the shorter
retention here is data minimization, not an arbitrary choice.

### orthanc (Ansible role)

DICOM archive: Orthanc (GPLv3) with its index in PostgreSQL and the
pixel data on a Docker volume. Added in v0.4 (issue #69).

`jodogne/orthanc-plugins`, not the ops-facing `orthancteam/orthanc` -
that one cannot run as a non-root user, and the component holding
patient images is the last place this kit would accept a root
container. Measured, not assumed:
[ADR 0009](https://github.com/Linumed/Base/blob/main/docs/adr/0009-jodogne-orthanc-image-not-orthancteam.md).

Orthanc serves Prometheus metrics natively at
`/tools/metrics-prometheus`, so unlike BridgeLink it needs no exporter -
the pre-check that #60 made mandatory gave the opposite answer here.

The DICOM listener is **not** published to the host by default. Which
modalities may reach the archive, from which network segment, is a
decision about the institution's network; a published container port
also bypasses ufw. Same reasoning as BridgeLink's channel listeners.

### backup (Ansible role)

Encrypted backups with restic. Supported backends:
- local (another directory / external drive)
- SFTP (e.g. another server on the network)
- S3-compatible (optional, e.g. Hetzner Object Storage)

Backup schedule via a systemd timer (not cron). Monitoring integration:
restic results are pushed to Prometheus as metrics.

---

## Network design

**Decided, not open:** no Linumed Base management interface is reachable
from outside. Every component binds to `127.0.0.1` or publishes no
host port at all; access goes through an SSH tunnel. Each Compose stack
has its own Docker network by default.

Two shared networks exist, and neither weakens that: `linumed-base-external`
lets the operator's own stacks be reached by Caddy (issue #39), and
`linumed-base-metrics` lets Prometheus scrape an exporter that lives in
another stack (issue #64). Both are internal Docker networks with no
host port and no route from outside; they exist so that container A can
reach container B *without* publishing anything, which is the opposite
of an exposure. This is explicitly **not** a return of the `linumed-net`
idea below - that one was about routing this kit's own management UIs
through a reverse proxy, which remains dropped.

A shared network (`linumed-net`) through which Caddy would route the
kit's own services was originally planned as the target picture and has
been **deliberately dropped** - along with the SSO integration that
would have been built on top of it. Reasoning, evaluated alternatives
(reverse proxy with an identity provider, mesh VPN) and the accepted
downsides:
[ADR 0003](https://github.com/Linumed/Base/blob/main/docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md).

![Access paths: the internet reaches Caddy on :80 and :443 only, which redirects to
HTTPS and proxies the operator's own applications. Grafana, Prometheus and the BridgeLink
admin interface are reachable exclusively through an SSH tunnel on
127.0.0.1.](docs/img/03-access-paths.svg)

Caddy is the reverse proxy for the **institution's own applications**,
not for this kit's management interfaces. It joins a second Docker
network (`linumed-base-external`, created unconditionally by the caddy
role) for exactly that purpose, independent of the access decision
above: an operator's separate Compose stack joins the same network as
`external: true` and is then reachable by service name, without
publishing a port or touching ufw. See `docs/roles/caddy.md`.

Because everything stays bound to loopback, Linumed Base works over
whatever network the operator already runs - a corporate VPN, a mesh, a
jump host, or the clinic LAN - without needing to know about any of it.
That composability is the reason for the decision, not a side effect of
it.

---

## Storage strategy

All persistent data lives in named Docker volumes, no bind mounts to
host paths except explicitly documented exceptions.

| Service | Volume | Contents |
|---|---|---|
| bridgelink | bridgelink_appdata | keystore, server.id, runtime data |
| postgresql (BridgeLink) | bridgelink_db_data | channel configuration and messages |
| prometheus | prometheus-data | metrics (retention: 90 days default) |
| grafana | grafana-data | dashboards, user settings |
| loki | loki-data | log data (retention: 30 days default, shorter than metrics - see the monitoring role) |

Node Exporter has no volume of its own - it runs natively, and host
metrics aren't persisted there (Prometheus takes care of that).

restic backs up `/var/lib/docker/volumes/` via direct file access, plus
`/opt/linumed-base/` (role configuration, secrets). Backups run daily via
a systemd timer. The result isn't pushed to Prometheus; it's written as
a Prometheus textfile metric (the same mechanism the native Node
Exporter uses) - Prometheus picks it up on its regular scrape, no
pushgateway needed.

Recovery tests are mandated as a documented process (a GDPR
requirement). The `backup` role runs one automatically, weekly, on its
own systemd timer independent of the daily backup - restore into a
throwaway target, diff against the live source, write the result as
its own textfile metrics so a restore test that silently stops running
is exactly as visible as one that starts failing. See
`docs/roles/backup.md`.

---

## Inventory structure

```
ansible/inventory/
└── example/
    ├── hosts.yml            # Example inventory (no real hosts)
    └── group_vars/
        ├── all.yml          # Global variables (timezone, NTP, etc.)
        └── linumed/
            ├── vars.yml            # Linumed-specific, non-secret defaults
            └── vault.yml.example   # Template for the required secrets (Ansible Vault)
```

For a real deployment, the administrator creates their own inventory
outside the repository and references the roles.

---

## Security model

- every connection TLS-encrypted (Caddy + ACME)
- SSH key-only, no password login
- firewall default-deny, minimal opening
- **Docker bypasses ufw**: a container port published via `ports:` is
  reachable despite active ufw rules (Docker's own iptables/nftables
  rules sit ahead of ufw's rules in the chain). Hence this kit's
  default: publish nothing that doesn't need to be publicly reachable
  (the exception is Caddy on 80/443, which is intentional) - everything
  else gets either no host port at all or an explicit `127.0.0.1`
  binding.
- Docker containers run unprivileged, no `--privileged`
- secrets via Ansible Vault or an external `.env` file (never in the
  repo). Passwords a container needs at runtime go in as a Docker
  secret from a file, not as an environment variable - env vars are
  readable by anyone allowed to run `docker inspect` and end up in the
  container config on disk.
- **From the bridgelink role onward, the stack processes real patient
  data.** Up to that point it only holds operational data (metrics,
  logs); an integration engine, by contrast, moves HL7 messages
  carrying names, dates of birth and diagnoses, and its database stores
  them depending on channel settings. That shifts the requirements for
  backup (the `backup` role), retention and access control from
  "securing infrastructure" to "processing health data" - see
  `docs/roles/bridgelink.md`, the GDPR section.
- backup data is encrypted (restic + password via Vault)
- automatic security updates for the host system (unattended-upgrades
  also covers natively installed packages like Node Exporter, not just
  container images)

---

## Scope: Linumed Base vs. Linumed Shifts

| | Linumed Base | Linumed Shifts |
|---|---|---|
| Type | open-source IaC kit | commercial SaaS application |
| License | MIT | proprietary |
| Content | infra stack, integration engine, monitoring | shift scheduling for care wards |
| Repo | Linumed/Base | Linumed/Shifts (private) |
| Audience | IT admins, system integrators | care management, ward leads, nursing staff |
| Dependency | independent | can run on top of Linumed Base |

Linumed Shifts is not in this repository and is not documented here.

---

## Versioning strategy

- v0.1: common + docker + caddy + monitoring + bridgelink + backup
- v0.2: operational readiness - a working onboarding path, the
  operations handbook, access hardening (shell-less tunnel users, real
  Grafana users), an automated restore test. See `docs/ROADMAP.md`.
- v0.3: the product's own name (Linumed Base, ADR 0006), BridgeLink
  application metrics, and the diagram/documentation work that came with
  them. No new role. See `docs/ROADMAP.md`.
- v0.4: the DICOM stack (Orthanc), plus the maintenance the kit did not
  do before - scanning the pinned images for known vulnerabilities,
  answering the lifecycle questions (Debian major upgrade, teardown, the
  single-host assumption), and a playbook for the runtime-agnostic
  subset. See `docs/ROADMAP.md`, Stage 6. Orthanc was earmarked as v0.3
  until 2026-08-20; that number went to the rename and the observability
  work instead.
- v1.0: the point from which breaking changes require a major version
  bump. What that promise covers is written down rather than left to
  interpretation - variable names, deploy paths, container and network
  names, this kit's own metric and alert names, dashboard and datasource
  UIDs, systemd unit names, and the set of variables with no default. See
  [ADR 0008](https://github.com/Linumed/Base/blob/main/docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md),
  which also lists what is deliberately *not* covered (pinned image
  versions have to keep moving) and what has to be cleaned up before the
  tag, because 1.0 freezes whatever exists at that moment. An earlier version of this line also named "certification
  prep"; that term appeared exactly once in the entire repository and was
  defined nowhere, so it was removed rather than left as an expectation
  nobody had committed to. If a specific certification ever becomes a
  goal, it gets named, scoped and given its own issue.

**No bundled identity provider.** The Authentik role originally planned
for v0.2 has been dropped
([ADR 0003](https://github.com/Linumed/Base/blob/main/docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md)):
it would have required an outward-facing opening that this kit
deliberately avoids. Instead of shipping an identity provider, Grafana
gets an optional connection to an **existing** one (OIDC).

Application software (HIS, DMS, document management) is deliberately
not part of Linumed Base. The clinic runs its own applications. Linumed
Base provides the secure, GDPR-compliant foundation.

Every release is tagged as a git tag, and versions follow Semantic
Versioning. For a 0.x project that means the opposite of what an earlier
version of this sentence claimed ("breaking changes only from v1.0
onward"): **before 1.0 there is no stability guarantee at all.** Breaking
changes can and do land in minor releases, and each one is called out
under `### Breaking` in `CHANGELOG.md` - v0.2.0 moved the Caddyfile,
v0.3.0 renamed every identifier and moved Prometheus's configuration
into its own directory.

**`v1.0.0` is tagged (2026-08-22).** From here a breaking change requires a major
version bump. It was not a quality label to reach and did not arrive by itself - it is a
deliberate promise about future releases, made only once the surface it covers had been
measured and, where it should not have been frozen, narrowed (ADR 0010).

The scope of that promise is defined in
[ADR 0008](https://github.com/Linumed/Base/blob/main/docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md).
The surface was measured, not estimated, and re-measured against all seven
roles on 2026-08-21: 138 interface role variables (plus eight recorded as
internal in `ansible/internal-variables.txt`, see ADR 0010), 13 container
names, 16 alert rule names, four systemd units, nine variables a plain run
aborts without, and
the Grafana dashboard and datasource UIDs that every operator-built panel
references.
