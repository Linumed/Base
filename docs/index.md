# Linumed Base

Ansible-based Infrastructure-as-Code kit that turns a standard Debian 13 installation
into a hardened, GDPR-compliant healthcare infrastructure platform. On-premise by
design. FOSS only.

This site is the operator's handbook: how the pieces fit together, how to run the kit
day to day, and why specific decisions were made. For installing it, start with the
[repository README](https://github.com/linumed/linumed-base) - it has the quick start.

## Where to start

- **New to this kit?** Read [Architecture](architecture.md) for the design
  principles and the overall picture, then [Deployment](operations/deployment.md) for
  the order things happen in and what a first run looks like.
- **Operating an existing installation?** [Access](operations/access.md),
  [Updates](operations/updates.md), and [Backup & Restore](operations/backup-restore.md)
  cover the day-to-day.
- **Something's broken?** [Troubleshooting](operations/troubleshooting.md) is the
  cross-role index; each role's own page has a more detailed pitfalls section.
- **Wondering why a specific choice was made?** [Architecture Decision
  Records](adr/README.md) - BridgeLink over Mirth Connect, English as the documentation
  language, why nothing is exposed to the internet, how CI gets to run VM tests.
- **Working on a specific role?** Every role has its own page under **Roles** in the
  navigation: variables, what gets changed on the host, how to verify it worked, and
  known pitfalls.

## What's in the kit (v0.1)

| Component | Role |
|---|---|
| Debian 13 hardening | SSH, ufw, fail2ban, unattended-upgrades |
| Caddy | Reverse proxy with automatic TLS |
| BridgeLink | HL7 v2 / FHIR R4 integration engine (MPL-2.0 fork of Mirth Connect) |
| Prometheus + Grafana + Loki + Alertmanager | Observability stack |
| restic | Encrypted backups |

Current status, open issues and the plan for what comes next:
[docs/ROADMAP.md](ROADMAP.md).
