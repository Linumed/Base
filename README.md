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
| BridgeLink | HL7 v2 / FHIR R4 integration engine (MPL-2.0 fork of Mirth Connect) |
| Prometheus + Grafana + Loki + Alertmanager | Observability stack (log shipping via Grafana Alloy, host metrics via native Node Exporter) |
| restic | Encrypted backups |

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
