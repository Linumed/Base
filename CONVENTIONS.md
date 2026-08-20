# CONVENTIONS.md - Linumed Base

This file defines the rules, architecture, and constraints for this project.
Always read this file before making any changes.

---

## What is Linumed Base?

Linumed Base is an Ansible-based Infrastructure-as-Code kit that turns a
standard Debian installation into a hardened, DSGVO-compliant healthcare
infrastructure platform. It is fully open source (MIT). It is NOT a custom
Linux distribution and does NOT produce a bootable ISO.

Linumed Shifts (the nurse scheduling SaaS product) is a separate commercial
product that can optionally run on top of Linumed Base. It is NOT part of this
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
  no Ansible dependency) establishes that baseline before any playbook runs - see
  `scripts/README.md`. Verified against a real netinst/preseed install by
  `test/vm-test-netinst.sh` (issue #14), separate from `test/vm-test.sh`'s genericcloud
  image, which already has both and would otherwise mask the gap.

---

## Repository structure

```
linumed-base/
├── ansible/
│   ├── roles/
│   │   ├── common/          # Hardening, firewall, SSH, updates
│   │   ├── docker/          # Docker Engine + compose plugin, shared prerequisite
│   │   ├── bridgelink/      # HL7/FHIR integration engine (MPL-2.0 Mirth fork)
│   │   ├── monitoring/      # Prometheus + Grafana + Loki + Node Exporter
│   │   ├── caddy/           # Reverse proxy with automatic TLS
│   │   └── backup/          # restic-based backup (local + optional S3)
│   ├── playbooks/
│   │   └── site.yml         # Full stack deployment - the only playbook there is.
│   │                        # Per-role playbooks were listed here for a long time and
│   │                        # never existed. No task carries an Ansible tag either, so
│   │                        # --tags selects nothing; see the note below.
│   └── inventory/
│       └── example/         # Example inventory, never real hosts
├── docker/                  # Docker Compose files per service
├── docs/                    # Documentation source (MkDocs)
├── scripts/                 # Bootstrap and utility scripts (bootstrap.sh - see scripts/README.md)
├── test/                    # Local test environment (libvirt/KVM, see below)
├── ARCHITECTURE.md          # Architecture reference
├── CONVENTIONS.md            # This file
└── README.md
```

---

## Ansible conventions

- Every role has: tasks/main.yml, defaults/main.yml, meta/main.yml, README.md
- **`site.yml` is the only playbook.** Roles are not independently deployable in general -
  the bridgelink exporter joins a Docker network the monitoring role creates, for instance -
  so a per-role playbook would be a promise this repo does not keep. Anything that assumes
  one role can run alone on a fresh host has to say so and be tested that way.
- Variables use the role name as prefix: `common_ssh_port`, `monitoring_retention_days`
- Secrets are never in defaults. Use Ansible Vault or reference `.env` files.
- Handlers go in handlers/main.yml, not inline.
- Tasks use FQCN (fully qualified collection names): `ansible.builtin.apt`, not `apt`
- Every task has a `name:` that describes what it does in plain language
- Idempotency is required. Running a playbook twice must produce no changes on second run.
- Target: Debian 13 (Trixie). Do not use features unavailable on Debian 13.

---

## Docker Compose conventions

- `ansible/roles/*/templates/docker-compose.yml.j2` is the source of truth for every
  Docker-based role - what `site.yml` actually deploys.
- `docker/<role>/` holds a hand-testable, `.env`-driven reference version for a subset of
  roles (currently `caddy`, `bridgelink`) - manual smoke-testing without Ansible, not a
  contractual mirror. It is **not required for every role** - see
  `docs/adr/0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md` for why
  (`backup` has no Compose stack at all; `monitoring`'s 7 containers and multiple secrets
  make a hand-maintained parallel version a maintenance cost outweighing its value for a
  solo-maintained repo) and when to add one for a new role.
- Where a `docker/<role>/` does exist: named volumes only, no bind mounts to host paths
  except for explicitly documented exceptions; include a `.env.example` alongside the
  Compose file; keep the image tag manually in sync with the role's default on touch, but
  don't chase every Ansible-side comment/detail change.
- Container images must be pinned to a specific version tag, never `latest` - applies to
  both the Ansible templates and any `docker/<role>/` reference.
- **Diagrams are Mermaid sources under `docs/diagrams/`, rendered to committed SVGs.**
  Edit the `.mmd`, run `scripts/render-diagrams.sh`, commit both. They are not rendered in
  the reader's browser: the same file is displayed by the MkDocs site, GitHub and Forgejo,
  each with its own Mermaid theme, so styling only ever reached one of three surfaces
  (issue #65). Never draw an edge to or from a `subgraph` - keep containment and flow in
  separate figures; see `scripts/README.md` for that and the empty-`%%` parse trap.
- **A container that another Compose stack must reach joins a shared, explicitly named
  network - it does not get a host port.** A port published on `127.0.0.1` is unreachable
  from another container, and publishing on all interfaces bypasses ufw, because Docker
  installs its rules ahead of the firewall. `host.docker.internal` is only valid for
  *native* services on the host (Node Exporter), where ufw can still protect the port.
  Precedents: `linumed-base-external` (#39), `linumed-base-metrics` (#64).
- **A config file that Ansible manages is bind-mounted as its containing directory, never
  as the individual file.** A single-file bind mount binds the inode; `template`/`copy`
  write a temp file and rename it into place, creating a new one, so the container keeps
  reading the orphaned copy and every change after the first deploy silently does nothing.
  Caddy hit this in #44/#48, Prometheus in #63 - twice is enough to make it a rule. It only
  shows up where the service is reloaded rather than restarted (a container restart
  re-resolves the mount), which is exactly where it is hardest to notice.
- **Health checks required for every service that listens on a port at all** - the broad
  reading, not just services with a published host port. Checked before writing this
  rule down precisely: every image in this repo that looks unable to support one
  (no `wget`/`curl` in a minimal container) turned out to have *some* working option once
  actually tested - `wget` was present after all, or a documented HTTP endpoint answered
  over bash's `/dev/tcp`. The one confirmed, genuine exception is `grafana/loki`: no
  shell, no `wget`, no executable besides the `loki` binary itself, so no exec-form
  healthcheck is technically possible - documented at that exact service in the
  monitoring role's Compose template, not treated as a precedent for skipping the check
  elsewhere without the same verification.

---

## Services in scope (v0.1)

| Service | Role | Notes |
|---|---|---|
| common | ansible/roles/common | SSH hardening, ufw, fail2ban, unattended-upgrades |
| Docker | ansible/roles/docker | Docker Engine + compose plugin, shared prerequisite for every Docker-based role |
| Caddy | ansible/roles/caddy | Reverse proxy, automatic TLS via ACME |
| BridgeLink | ansible/roles/bridgelink | HL7 v2, FHIR R4 integration engine - MPL-2.0 fork of Mirth Connect, which went proprietary in March 2025 |
| Prometheus | ansible/roles/monitoring | Metrics collection |
| Grafana | ansible/roles/monitoring | Dashboards, loopback-only by default |
| Loki | ansible/roles/monitoring | Log aggregation |
| Grafana Alloy | ansible/roles/monitoring | Log shipping to Loki - not Promtail, which reached EOL 2026-03-02 |
| Alertmanager | ansible/roles/monitoring | Alert routing |
| cAdvisor | ansible/roles/monitoring | Container metrics |
| Node Exporter | ansible/roles/monitoring | Host metrics - native Debian package, not a container |
| restic | ansible/roles/backup | Encrypted backup |

Out of scope for v0.1: Orthanc (DICOM, v0.3).

**No identity provider is bundled, ever** - Authentik was planned for v0.2 and is dropped,
see `docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md`. Every management
interface binds to `127.0.0.1` and is reached through an SSH tunnel; Caddy serves the
operator's own applications, not this kit's admin UIs. Do not propose a shared
`linumed-net`, a reverse-proxy route to a Linumed Base service, or a mesh-VPN role without
first reading that ADR - all three were evaluated and rejected on the grounds that the kit
must work after the playbooks run, without the institution supplying a second subsystem.
Connecting Grafana to an *existing* identity provider via OIDC is fine; shipping one is not.

Application software (KIS, DMS, document management) is out of scope entirely.
Clinics bring their own applications. Linumed Base provides the secure base.

---

## Testing

- Local testing uses libvirt/KVM against the official Debian 13 genericcloud image, driven
  by `test/vm-test.sh`. Not Vagrant/VirtualBox: VirtualBox is not packaged for Debian 13,
  Vagrant is stuck on 2.3.7 (last MPL-licensed release before the BUSL relicense), and there
  is no official Debian 13 Vagrant box (Debian bug #1110834, open as of 2026).
- Before opening a PR, the full `site.yml` playbook must run idempotently
  against the test VM (no errors, no changes on second run) - `test/vm-test.sh` checks this.
- CI/CD is Forgejo Actions, self-hosted alongside the runner - see the CI/CD section
  below. `ansible-lint` runs on every push; the full `site.yml` VM double-run runs on
  changes under `ansible/`, `docker/`, `test/` or `scripts/` (issue #45).

---

## CI/CD

Forgejo is canonical and self-hosted, with its Actions runner on the same machine - there
is no separate VPS and no tunnel between them. (Earlier drafts of this file described a
split setup - Forgejo on a remote VPS, runner at home, mesh VPN in between. That was a
plan, it is not what got built. Corrected 2026-08-18 after checking against the running
system rather than trusting this file.)

Three workflows under `.forgejo/workflows/`:

- `ansible-lint.yml` - every push and pull request to `main`.
- `vm-test.yml` - the full `site.yml` double-run against a throwaway libvirt/KVM VM, plus
  Prometheus target health, the `docker/` smoke test, and a third `site.yml` pass with the
  BridgeLink exporter switched on (issue #62). Triggers on pushes touching `ansible/`,
  `docker/`, `test/` or `scripts/`, and on demand via `workflow_dispatch`. Not on every
  push: the run was ~9 minutes before the exporter pass and the runner has capacity 1
  (issue #45).

  The exporter pass exists because opt-in features are invisible to a defaults-only test:
  `bridgelink_exporter_enabled` defaults to false, so the first two runs prove only that
  the feature is a no-op while switched off. Anything added behind a default-off flag
  needs its own pass, or it ships with no coverage at all.

- `docs-site.yml` - re-renders the diagrams and fails if the committed SVGs are stale,
  then builds the MkDocs handbook with `--strict` and publishes it as the
  `docs-site-latest` release asset, which Website#5 pulls to host at `linumed.com/base/docs/`
  (issue #55). Triggers on `docs/**`, `mkdocs.yml`, `README.md`, `ARCHITECTURE.md`,
  `CHANGELOG.md`. It deliberately stops at publishing an artifact - putting the built HTML
  on the website is a manual pull, because prod deploys are a manual gate.

  **The docs are a published artifact, not a byproduct.** The repository is public and the
  website is built from it, so a change without its documentation is a publicly visible
  gap. Treat `CHANGELOG.md` as part of every user-visible change, not as an afterthought -
  it is the entry most easily forgotten and it ships on the site via the `docs/changelog.md`
  symlink.

`runs-on: docker`, never `ubuntu-latest` - the runner registers that label only.

Keep workflows portable. If a GitHub mirror is ever added it stays a mirror; do not
introduce steps that only work on one platform.

**Machine-specific details of this particular runner and host** (paths, the libvirt
socket mount, its Docker/registry setup) belong in that machine's own system
documentation, not in this repository - see ADR 0004 for the parts that genuinely affect
the workflow design.

## Documentation

- Docs live in `docs/` and are built with MkDocs (Material theme)
- Every role has its own doc page under `docs/roles/`
- Language: **English**, for both end-user and developer documentation - see
  `docs/adr/0002-english-as-documentation-language.md`. Commit messages stay German.
  `ARCHITECTURE.md` and `docs/roles/*.md` were translated 2026-08-14 (#30). ADR 0001
  stays German on purpose: it records a decision as it was made, backdating it would be
  dishonest.
- Do not document things that are already obvious from the code
- Decisions that someone will predictably challenge from the outside ("why not X?")
  go into `docs/adr/` as a numbered ADR - context, evaluated alternatives, the
  downsides accepted, and what would make the decision worth revisiting. Reserved for
  decisions that are expensive to reverse and whose reasoning is not readable from the
  code; everything else is a comment at the relevant place. Role READMEs and role docs
  link to the ADR instead of restating the reasoning, so there is one source of truth.

---

## What NOT to do

- Do not build or reference a bootable ISO or PXE boot setup
- Do not add Kubernetes, Helm, or k8s manifests to this repo
- Do not add Linumed Shifts application code here
- Do not use `become: yes` globally - only where explicitly required
- Do not commit any file containing passwords, tokens, or private keys
- Do not use `latest` as a Docker image tag
- Do not add US-cloud-dependent services without a self-hostable alternative
