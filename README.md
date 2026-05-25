# Linumed OS

Ansible-based IaC kit that turns a standard Debian 13 installation into a
hardened, DSGVO-compliant healthcare infrastructure platform.
On-premise by design. FOSS only.

---

## What it is

Linumed OS is not a custom Linux distribution. It is a collection of
Ansible playbooks and roles that configure a standard Debian 13 (Trixie)
server into a production-ready healthcare infrastructure stack - including
HL7/FHIR integration, monitoring, reverse proxy, and encrypted backups.

## What it includes (v0.1)

| Component | Role |
|---|---|
| Debian 13 hardening | SSH, ufw, fail2ban, unattended-upgrades |
| Caddy | Reverse proxy with automatic TLS |
| Mirth Connect | HL7 v2 / FHIR R4 integration engine |
| Prometheus + Grafana + Loki | Observability stack |
| restic | Encrypted backups |

## Requirements

- Target: Debian 13 (Trixie), bare metal or VM
- Control node: any Linux machine with Ansible installed
- SSH access to the target host

## Quick start

```bash
git clone https://github.com/linumed/linumed-os.git
cd linumed-os
cp ansible/inventory/example ansible/inventory/myhospital
# edit inventory/myhospital/hosts.yml
ansible-playbook ansible/playbooks/site.yml -i ansible/inventory/myhospital
```

## Documentation

See [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions and component details.

## License

MIT - see [LICENSE](LICENSE)

## Part of the Linumed ecosystem

- **Linumed OS** (this repo) - open source infrastructure platform
- **Linumed Shifts** - nurse shift scheduling SaaS (commercial)
- **Linumed Passpin** - identity and secrets management (in development)

[linumed.com](https://linumed.com)
