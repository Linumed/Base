# Linumed Base

Ansible-based IaC kit that turns a standard Debian 13 installation into a
hardened, DSGVO-compliant healthcare infrastructure platform.
On-premise by design. FOSS only.

[linumed.com/base](https://linumed.com/base/)

---

## What it is

Linumed Base is not a custom Linux distribution. It is a collection of
Ansible playbooks and roles that configure a standard Debian 13 (Trixie)
server into a production-ready healthcare infrastructure stack - including
HL7/FHIR integration, monitoring, reverse proxy, and encrypted backups.

## What it includes

| Component | Role |
|---|---|
| Debian 13 hardening | SSH, ufw, fail2ban, unattended-upgrades |
| Caddy | Reverse proxy with automatic TLS |
| BridgeLink | HL7 v2 / FHIR R4 integration engine (MPL-2.0 fork of Mirth Connect) |
| Prometheus + Grafana + Loki + Alertmanager | Observability stack (log shipping via Grafana Alloy, host metrics via native Node Exporter) |
| restic | Encrypted backups |

## Status

**`v0.2.0` is tagged** - see [CHANGELOG.md](CHANGELOG.md). Every role passed a full
`site.yml` double-run against a throwaway VM (idempotent - `changed=0` on the second run)
and, separately, against a real Debian 13 netinst/preseed install via
`scripts/bootstrap.sh` and `test/vm-test-netinst.sh` (issues #13/#14). That double-run now
happens in CI on every change under `ansible/`, `docker/`, `test/` or `scripts/`, not only
when someone remembers to start it (#45). The onboarding path itself is verified too, not
just the roles: a full double-run following this README's own quick start verbatim -
clone, copy the example inventory, fill in the vault, deploy - with no repository
knowledge beyond what's written below (issues #27/#28/#29).

The full plan, in order, with the reasoning behind the sequencing:
[`docs/ROADMAP.md`](docs/ROADMAP.md).

## Requirements

- Target: Debian 13 (Trixie), bare metal or VM
- Control node: any Linux machine with Ansible installed
- SSH access to the target host

### System requirements by stack

Measured, not estimated: each row is a real `site.yml` (or role subset) deployment
against a fresh Debian 13 VM, RAM/CPU sized down until it still deployed cleanly, then
measured after a 2-5 minute settle period so short-lived install-time spikes don't
inflate the number. `free -m` "used" (not "available") is what's reported - it's the
number that predicts whether the next role you add will fit.

| Stack | RAM (allocated / used) | vCPUs | Disk (used) | Notes |
|---|---|---|---|---|
| common + docker + caddy | 1 GB / 381 MB | 1 | 1.6 GB | Minimum that deploys cleanly - no headroom for anything else |
| + monitoring | 2 GB / 903 MB | 2 | 4.6 GB | Prometheus, Grafana, Loki, Alloy, Alertmanager, cAdvisor, native Node Exporter |
| Full stack (+ bridgelink + backup) | 4 GB / 1.6 GB | 2 | 6.0 GB | BridgeLink's JVM is the largest single consumer (~350-480 MB) |
| Full stack, comfortable | 6 GB / 1.7 GB | 3 | 6.0 GB | What `test/vm-test.sh` uses - headroom for image pulls, restic runs, and Grafana/cAdvisor's own usage variance |

A few things worth knowing before sizing a real host:

- **BridgeLink dominates RAM once channels are added.** These numbers are an empty
  engine (`bridgelink_max_heap_mb: 512` default) with no channels configured - real HL7
  traffic and channel-side JavaScript transformers use more. Size the JVM heap for your
  actual channel load, not this baseline.
- **`/var/lib/docker/volumes` starts small and grows.** 51-100 MB here is a fresh
  install; Loki and Prometheus retention (30/90 days by default, see
  `docs/roles/monitoring.md`) and BridgeLink's message storage are what actually
  consumes disk over time - budget accordingly, not from this table.
- **1 vCPU is the minimum, not a recommendation**, even for the smallest stack -
  `test/vm-test.sh` itself runs with 3 for exactly that reason: a busy first apply
  (package installs, image pulls) is visibly slower on a single core, and this repo has
  already chased down enough hard-to-reproduce timing issues during real testing (see
  `ansible/roles/docker/README.md` and `ansible/roles/common/README.md`) to not want to
  reintroduce that risk on a production host to save one vCPU. See
  `ansible/roles/common/README.md` ("become: true on every privileged task") and
  `docs/roles/docker.md` ("Stolperfallen") for the specific bug this repo already found
  and fixed once.

## Quick start

On a **freshly installed Debian 13 minimal/netinst** target, `python3` and `sudo` aren't
guaranteed to be present - run `scripts/bootstrap.sh` from the target itself first (see
`scripts/README.md`). Skip this if the target already has a working sudo user (e.g. any
cloud image, or a host you've set up before).

```bash
# On the target host, as root, only if it's a fresh minimal install:
./scripts/bootstrap.sh --user linumed --key "ssh-ed25519 AAAA... you@host"
```

```bash
git clone https://github.com/Linumed/Base.git
cd Base/ansible
# Every ansible-playbook/ansible-vault/ansible-lint command in this repo runs from here,
# not the repo root - ansible.cfg (roles_path, default inventory) lives in this
# directory and Ansible only picks up an ansible.cfg from the current working directory.

cp -r inventory/example inventory/myhospital
# edit inventory/myhospital/hosts.yml: set ansible_host / ansible_user for your target

# inventory/myhospital/group_vars/linumed/vars.yml holds plain config (edit
# backup_repository at least). .../vault.yml.example lists the six variables with no
# safe default - site.yml aborts without them. Turn it into a real, encrypted vault file:
cp inventory/myhospital/group_vars/linumed/vault.yml.example \
   inventory/myhospital/group_vars/linumed/vault.yml
# edit vault.yml, replace every CHANGEME, then encrypt it:
ansible-vault encrypt inventory/myhospital/group_vars/linumed/vault.yml

ansible-playbook playbooks/site.yml -i inventory/myhospital --ask-vault-pass
# add --ask-become-pass unless bootstrap.sh was run with --nopasswd
```

## Documentation

See [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions and component details.

## Reporting a security problem

Privately, by email, never as a public issue - see [SECURITY.md](SECURITY.md) for the
address, what to include, what response times a one-person project can realistically
promise, and what is in scope here versus belonging upstream.

## License

MIT - see [LICENSE](LICENSE)

## Part of the Linumed ecosystem

- **Linumed Base** (this repo) - open source infrastructure platform
- **Linumed Shifts** - nurse shift scheduling SaaS (commercial)

[linumed.com](https://linumed.com)
