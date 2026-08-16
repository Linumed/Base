# ARCHITECTURE.md - Linumed OS

## Overview

Linumed OS is not a custom operating system and not a bootable image.
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
Linumed OS is built to run in the institution's own infrastructure.
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
Every component of Linumed OS is free open-source software.
Linumed Shifts (the commercial product) is not part of this repository
and is licensed separately.

**EU infrastructure**
No dependencies on US-only services. Pulling images from Docker Hub is
accepted, but images run on EU infrastructure. EU-based alternatives
are preferred for CI/CD.

---

## Target architecture (v0.1)

```
┌───────────────────────────────────────────────────────────┐
│                  Debian 13 (Bare Metal / VM)               │
│                                                             │
│  ┌──────────┐   ┌───────────────────────────────────────┐ │
│  │  Caddy   │   │              Docker Engine             │ │
│  │ (Proxy,  │   │                                         │ │
│  │  Container)  │  ┌─────────────┐  ┌───────────────────┐│ │
│  │  Port    │──▶│  │ BridgeLink  │  │ Prometheus         ││ │
│  │  80/443  │   │  │ + Postgres  │  │ Grafana (loopback) ││ │
│  └──────────┘   │  │  (loopback) │  │ Loki, Alertmanager ││ │
│                 │  └─────────────┘  │ Alloy, cAdvisor    ││ │
│  ┌──────────┐   │                   └───────────────────┘│ │
│  │  ufw     │   │                                         │ │
│  │ fail2ban │   └───────────────────────────────────────┘ │
│  │  SSH     │                                              │
│  └──────────┘   ┌───────────────────────────────────────┐ │
│                  │  Node Exporter (native, Debian package)│ │
│                  └───────────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  restic (Backup - encrypted, scheduled)               │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

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
Linumed OS follows that open line. Mirth Connect remains the industry's
de-facto standard - channels are portable between all variants, so an
institution keeps its integration work if it ever wants to switch.

Full reasoning, including evaluated alternatives (Open Integration
Engine, licensed Mirth 4.6+, frozen 4.5.2), accepted downsides and
revision triggers:
[ADR 0001](docs/adr/0001-bridgelink-statt-mirth-connect.md).

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

Retention is split by data kind, not a single global value: metrics
(`monitoring_metrics_retention_days`, default 90) and logs
(`monitoring_logs_retention_days`, default 30, shorter) - logs can
contain personal data (IP addresses, usernames), so the shorter
retention here is data minimization, not an arbitrary choice.

### backup (Ansible role)

Encrypted backups with restic. Supported backends:
- local (another directory / external drive)
- SFTP (e.g. another server on the network)
- S3-compatible (optional, e.g. Hetzner Object Storage)

Backup schedule via a systemd timer (not cron). Monitoring integration:
restic results are pushed to Prometheus as metrics.

---

## Network design

**Decided, not open:** no Linumed OS management interface is reachable
from outside. Every component binds to `127.0.0.1` or publishes no
host port at all; access goes through an SSH tunnel. Each Compose stack
has its own, isolated Docker network.

A shared network (`linumed-net`) through which Caddy would route the
kit's own services was originally planned as the target picture and has
been **deliberately dropped** - along with the SSO integration that
would have been built on top of it. Reasoning, evaluated alternatives
(reverse proxy with an identity provider, mesh VPN) and the accepted
downsides:
[ADR 0003](docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md).

```
Internet
   │
   ├── :80  ──▶ Caddy ──▶ redirect to HTTPS
   └── :443 ──▶ Caddy ──▶ the operator's own applications
                          (Linumed OS itself is not behind it)

SSH tunnel (not public)
   ├── 127.0.0.1:3000 ──▶ Grafana
   ├── 127.0.0.1:9090 ──▶ Prometheus
   └── 127.0.0.1:8443 ──▶ BridgeLink admin
```

Caddy is the reverse proxy for the **institution's own applications**,
not for this kit's management interfaces. It joins a second Docker
network (`linumed-os-external`, created unconditionally by the caddy
role) for exactly that purpose, independent of the access decision
above: an operator's separate Compose stack joins the same network as
`external: true` and is then reachable by service name, without
publishing a port or touching ufw. See `docs/roles/caddy.md`.

Because everything stays bound to loopback, Linumed OS works over
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
`/opt/linumed-os/` (role configuration, secrets). Backups run daily via
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

## Scope: Linumed OS vs. Linumed Shifts

| | Linumed OS | Linumed Shifts |
|---|---|---|
| Type | open-source IaC kit | commercial SaaS application |
| License | MIT | proprietary |
| Content | infra stack, integration engine, monitoring | shift scheduling for care wards |
| Repo | linumed/linumed-os | linumed/shifts (private) |
| Audience | IT admins, system integrators | care management, ward leads, nursing staff |
| Dependency | independent | can run on top of Linumed OS |

Linumed Shifts is not in this repository and is not documented here.

---

## Versioning strategy

- v0.1: common + docker + caddy + monitoring + bridgelink + backup
- v0.2: operational readiness - a working onboarding path, the
  operations handbook, access hardening (shell-less tunnel users, real
  Grafana users), an automated restore test. See `docs/ROADMAP.md`.
- v0.3: DICOM stack (Orthanc)
- v1.0: complete documentation, CI-tested roles, certification prep

**No bundled identity provider.** The Authentik role originally planned
for v0.2 has been dropped
([ADR 0003](docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md)):
it would have required an outward-facing opening that this kit
deliberately avoids. Instead of shipping an identity provider, Grafana
gets an optional connection to an **existing** one (OIDC). Linumed
Passpin is unaffected by this - it is a separate product and is not
developed in this repository.

Application software (HIS, DMS, document management) is deliberately
not part of Linumed OS. The clinic runs its own applications. Linumed
OS provides the secure, GDPR-compliant base.

Every release is tagged as a git tag. Breaking changes only from v1.0
onward.
