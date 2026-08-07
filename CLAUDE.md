# CLAUDE.md - Linumed OS

This file defines the rules, architecture, and constraints for this project.
Always read this file before making any changes.

---

## What is Linumed OS?

Linumed OS is an Ansible-based Infrastructure-as-Code kit that turns a
standard Debian installation into a hardened, DSGVO-compliant healthcare
infrastructure platform. It is fully open source (MIT). It is NOT a custom
Linux distribution and does NOT produce a bootable ISO.

Linumed Shifts (the nurse scheduling SaaS product) is a separate commercial
product that can optionally run on top of Linumed OS. It is NOT part of this
repository.

---

## Non-negotiable principles

- Ansible is the sole orchestration layer. No Salt, no Chef, no Puppet.
- Debian stable is the only supported target OS. Currently Debian 13 (Trixie). No Ubuntu, no Rocky, no RHEL.
- All services in this repo must be FOSS. No commercial software, no
  proprietary licenses.
- Docker Compose is used for service stacks. Kubernetes/Helm is out of scope
  for this repo.
- EU infrastructure wherever possible: no US-only dependencies, no
  phone-home telemetry, no cloud lock-in.
- DSGVO compliance is a design constraint, not an afterthought. Any service
  added must be evaluated for data residency and logging behavior.
- No credentials, secrets, or real IP addresses in any committed file.
  Always use .env.example templates and Ansible Vault references.
- Target host baseline is not assumed: `python3` and `sudo` are both `Priority: optional`
  in Debian 13, so a minimal/netinst install has neither. `scripts/bootstrap.sh` (shell,
  no Ansible dependency) exists to establish the baseline before any playbook runs.

---

## Repository structure

```
linumed-os/
├── ansible/
│   ├── roles/
│   │   ├── common/          # Hardening, firewall, SSH, updates
│   │   ├── mirth-connect/   # HL7/FHIR integration engine (Dockerized)
│   │   ├── monitoring/      # Prometheus + Grafana + Loki + Node Exporter
│   │   ├── caddy/           # Reverse proxy with automatic TLS
│   │   └── backup/          # restic-based backup (local + optional S3)
│   ├── playbooks/
│   │   ├── site.yml         # Full stack deployment
│   │   ├── monitoring.yml   # Monitoring stack only
│   │   └── mirth.yml        # Mirth Connect only
│   └── inventory/
│       └── example/         # Example inventory, never real hosts
├── docker/                  # Docker Compose files per service
├── docs/                    # Documentation source (MkDocs)
├── scripts/                 # Bootstrap and utility scripts
├── test/                    # Local test environment (libvirt/KVM, see below)
├── ARCHITECTURE.md          # Architecture reference
├── CLAUDE.md                # This file
└── README.md
```

---

## Ansible conventions

- Every role has: tasks/main.yml, defaults/main.yml, meta/main.yml, README.md
- Variables use the role name as prefix: `common_ssh_port`, `monitoring_retention_days`
- Secrets are never in defaults. Use Ansible Vault or reference `.env` files.
- Handlers go in handlers/main.yml, not inline.
- Tasks use FQCN (fully qualified collection names): `ansible.builtin.apt`, not `apt`
- Every task has a `name:` that describes what it does in plain language
- Idempotency is required. Running a playbook twice must produce no changes on second run.
- Target: Debian 13 (Trixie). Do not use features unavailable on Debian 13.

---

## Docker Compose conventions

- One Compose file per service stack under `docker/`
- Named volumes only, no bind mounts to host paths except for explicitly documented exceptions
- Always include a `.env.example` alongside each Compose file
- Container images must be pinned to a specific version tag, never `latest`
- Health checks required for every service that exposes a port

---

## Services in scope (v0.1)

| Service | Role | Notes |
|---|---|---|
| common | ansible/roles/common | SSH hardening, ufw, fail2ban, unattended-upgrades |
| Caddy | ansible/roles/caddy | Reverse proxy, automatic TLS via ACME |
| Mirth Connect | ansible/roles/mirth-connect | HL7 v2, FHIR R4 integration engine |
| Prometheus | ansible/roles/monitoring | Metrics collection |
| Grafana | ansible/roles/monitoring | Dashboards |
| Loki | ansible/roles/monitoring | Log aggregation |
| Node Exporter | ansible/roles/monitoring | Host metrics |
| restic | ansible/roles/backup | Encrypted backup |

Services explicitly out of scope for v0.1: Authentik (SSO, v0.2), Orthanc (DICOM, v0.3), Linumed Passpin (separate product, long-term).
These are planned for v0.2+.

Application software (KIS, DMS, document management) is out of scope entirely.
Clinics bring their own applications. Linumed OS provides the secure base.

---

## Testing

- Local testing uses libvirt/KVM against the official Debian 13 genericcloud image, driven
  by `test/vm-test.sh`. Not Vagrant/VirtualBox: VirtualBox is not packaged for Debian 13,
  Vagrant is stuck on 2.3.7 (last MPL-licensed release before the BUSL relicense), and there
  is no official Debian 13 Vagrant box (Debian bug #1110834, open as of 2026).
- Before opening a PR, the full `site.yml` playbook must run idempotently
  against the test VM (no errors, no changes on second run) - `test/vm-test.sh` checks this.
- Target CI/CD: Forgejo (forgejo.linumed.com on HostEurope VPS) with Forgejo Runner
  on the local Linumed dev server, connected via Headscale/WireGuard tunnel
- Interim CI/CD (until dev server is operational): GitHub Actions runs ansible-lint
  on all roles - do not build deep GitHub Actions dependencies, keep workflows minimal
  and portable so migration to Forgejo is straightforward

---

## CI/CD

Target setup (once Linumed dev server is operational):

- Forgejo at forgejo.linumed.com (HostEurope VPS) as Git host and CI platform
- Forgejo Runner on the Linumed dev server (local EliteDesk), connected to the VPS
  via Headscale/WireGuard tunnel
- Pipelines run locally on the dev server: ansible-lint, libvirt/KVM VM provisioning
  (`test/vm-test.sh`), idempotency checks

Interim setup (GitHub Actions, until dev server is ready):

- Minimal workflow: ansible-lint only, no VM-based tests
- Keep .github/workflows/ simple and portable - no GitHub-specific features
  that would make migration to Forgejo painful
- Once Forgejo is live, GitHub repo can remain as a public mirror

Do not introduce GitHub Actions steps that cannot be replicated 1:1 in a
Forgejo Actions workflow.

## Documentation

- Docs live in `docs/` and are built with MkDocs (Material theme)
- Every role has its own doc page under `docs/roles/`
- Language: German for end-user docs, English for technical/developer docs
- Do not document things that are already obvious from the code

---

## What NOT to do

- Do not build or reference a bootable ISO or PXE boot setup
- Do not add Kubernetes, Helm, or k8s manifests to this repo
- Do not add Linumed Shifts application code here
- Do not use `become: yes` globally - only where explicitly required
- Do not commit any file containing passwords, tokens, or private keys
- Do not use `latest` as a Docker image tag
- Do not add US-cloud-dependent services without a self-hostable alternative
