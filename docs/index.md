# Linumed Base

Ansible-based Infrastructure-as-Code kit that turns a standard Debian 13 installation
into a hardened, GDPR-aware healthcare infrastructure platform. On-premise by
design. FOSS only.

This site is the operator's handbook: how the pieces fit together, how to run the kit
day to day, and why specific decisions were made. For installing it, start with the
[repository README](https://github.com/Linumed/Base) - it has the quick start.

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
  Records](adr/README.md) - BridgeLink over Mirth Connect, why there is no Kubernetes and
  what that costs, why nothing is exposed to the internet, English as the documentation
  language, how CI gets to run VM tests.
- **Evaluating whether this kit fits at all?** The decisions most likely to rule it in or
  out are [no Kubernetes and therefore no high
  availability](adr/0007-docker-compose-not-kubernetes.md) and [no bundled identity
  provider, no admin UI on the
  internet](adr/0003-loopback-only-access-no-bundled-identity-provider.md). Both name what
  they cost, not only what they buy - and the first one also lists the parts of the kit
  that work on Kubernetes nodes anyway.
- **Working on a specific role?** Every role has its own page under **Roles** in the
  navigation: variables, what gets changed on the host, how to verify it worked, and
  known pitfalls.

## What's in the kit

| Component | Role |
|---|---|
| Debian 13 hardening | SSH, ufw, fail2ban, unattended-upgrades |
| Caddy | Reverse proxy with automatic TLS |
| BridgeLink | HL7 v2 integration engine (MPL-2.0 fork of Mirth Connect). FHIR endpoints can be built as HTTP/JSON channels; no FHIR data type ships with the engine - see [bridgelink](roles/bridgelink.md) |
| Prometheus + Grafana + Loki + Alertmanager | Observability stack |
| restic | Encrypted backups |

Current status, open issues and the plan for what comes next:
[docs/ROADMAP.md](ROADMAP.md).
