# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Written in
English like the rest of the documentation (ADR 0002), even though commit messages are
German - a changelog addresses the same readers the
documentation does. Every entry names its issue, so the reasoning behind a change is one
click away instead of restated here.

## [Unreleased]

### Changed

- **The product is now called Linumed Base.** It was released as "Linumed OS" through
  `v0.2.0`; the name was wrong, because this is a collection of Ansible roles that
  configure a standard Debian install, not an operating system, a distribution or a
  bootable image. Renamed while nothing was published and nothing was installed anywhere -
  see ADR 0006 for the full reasoning and for what was deliberately *not* renamed.

  **What this means for you:** identifiers changed with the name. Container names are now
  `linumed-base-*`, the default deploy path is `/opt/linumed-base`, and the shared Docker
  network is `linumed-base-external`. There are no known installations of the earlier
  releases, so no migration path is provided - if you did install `v0.1.0` or `v0.2.0`,
  treat this as a fresh deployment rather than an upgrade.

  Git history and the `v0.1.0` / `v0.2.0` tag messages keep the old name on purpose. Those
  releases happened under it, and rewriting published history to pretend otherwise would
  be dishonest.

## [0.2.0] - 2026-08-17

Operational maturity rather than new services: the v0.1 role set stayed as it was, and
the gaps a repository audit surfaced got closed - real users instead of shared logins,
tests that verify behaviour instead of configuration, and a restore test that actually
restores.

### Added

- **Tunnel-only SSH users** (`common_ssh_tunnel_users`) - shell-less accounts restricted
  by `sshd` itself to exactly the loopback ports listed, so someone who should read a
  dashboard no longer needs a shell on a machine that processes patient data (#41).
- **Individual Grafana users** (`monitoring_grafana_users`) with Viewer/Editor/Admin
  roles, provisioned through Grafana's HTTP API, replacing the shared admin login as the
  way everyone views dashboards and logs (#42).
- **Optional OIDC for Grafana** (`monitoring_grafana_oidc_*`) pointing at an institution's
  *existing* identity provider. No provider is bundled, and empty settings change nothing
  (ADR 0003, #42).
- **Shared Docker network for Caddy** (`caddy_external_network_name`, default
  `linumed-base-external`) so Caddy can reverse-proxy a container in an operator's own,
  separate Compose stack by service name - without publishing a port or touching ufw
  (#39).
- **Automated weekly restore test** in the `backup` role: restores into a throwaway
  target, diffs against the live source, and reports the result as its own Prometheus
  metrics, with `RestoreTestFailed` and `RestoreTestStale` alert rules. A restore test
  that silently stops running is now as visible as one that fails (#36).
- **VM provisioning and idempotency checks in CI** - a full `site.yml` double-run against
  a real libvirt/KVM VM, not just linting (ADR 0004, #33). Since #45 it triggers itself on changes under `ansible/`, `docker/`, `test/` and `scripts/`.
- **Health checks** for Alertmanager, cAdvisor, docker-socket-proxy and Alloy. All four
  had been assumed impossible; all four turned out to have a working option once actually
  tested. `grafana/loki` remains the single genuine exception (#38).
- **Smoke test for the `docker/` references**, which previously had no coverage of any
  kind (#46, #48).
- **`SECURITY.md`** - private reporting channel, realistic response times for a
  one-person project, and an explicit scope boundary against upstream software (#47).
- **MkDocs documentation site** (Material theme) with a cross-role operations handbook
  under `docs/operations/` (#26).
- **Optional Docker Hub pull-through cache** (`docker_registry_mirrors`) for test runs
  (#43).

### Changed

- **Documentation language is English** (ADR 0002). `ARCHITECTURE.md` and all
  `docs/roles/*.md` were translated; ADR 0001 stays German on purpose, as a record of a
  decision as it was made (#30).
- **`docker/<role>/` is a manual-testing reference, not a required mirror** of the Ansible
  templates - the templates are the single source of truth (ADR 0005, #37).

### Fixed

- **Caddyfile changes never reached the running container after the first deploy.** The
  Caddyfile was bind-mounted as a single file, which attaches to that file's inode, while
  Ansible's `template` module rewrites atomically - so the container kept serving the
  original file forever, with `caddy reload` reporting success and the health check
  staying green throughout. Now the containing directory is mounted instead (#44).
- **The `docker/caddy` reference was left broken by that same fix** - its
  `Caddyfile.example` stayed in the old location, so following the directory's own
  instructions produced a crash-looping Caddy (#48).
- **The osinfo-db in the CI job container predated Debian 12/13**, breaking
  `virt-install` in the VM test workflow (#33).

### Breaking

- **The Caddyfile moved from `{{ caddy_deploy_dir }}/Caddyfile` to
  `{{ caddy_deploy_dir }}/conf/Caddyfile`** (#44). The role deletes the file at the old
  path on the next run, so no manual migration is needed - but anyone who edited that
  file directly, or whose own tooling references the old path, has to follow the move.
  Edits to the old location have no effect.

## [0.1.0] - 2026-08-14

First tagged release. Complete v0.1 role set, each verified against a real Debian 13 VM.

### Added

- **`common`** - SSH hardening (#1), ufw (#3), fail2ban (#10), unattended-upgrades (#5),
  NTP/timezone (#11), and an `ssh.socket` override instead of aborting on socket
  activation (#15).
- **`docker`** - Docker Engine and the Compose plugin from the official repository, as a
  shared prerequisite for every Docker-based role (#17).
- **`caddy`** - reverse proxy with automatic ACME/TLS, Caddyfile generated from
  `caddy_sites`, validated before it takes effect and reloaded without downtime (#6).
- **`monitoring`** - Prometheus, Grafana, Loki, Grafana Alloy, Alertmanager, cAdvisor and
  a native Node Exporter. Only Grafana and Prometheus get a host port, both on loopback
  (#8, #9). Optional Alertmanager SMTP delivery, all-or-nothing (#22); Alloy reaches the
  Docker API only through a read-only socket proxy (#21).
- **`bridgelink`** - HL7 v2 / FHIR R4 integration engine, an MPL-2.0 fork of Mirth
  Connect, which went proprietary in March 2025 (ADR 0001, #12).
- **`backup`** - restic via systemd timer, any restic backend, with the result exported as
  Prometheus metrics (#7).
- **`scripts/bootstrap.sh`** - establishes the `python3`/`sudo` baseline on a minimal
  netinst install, where neither is guaranteed, plus a separate netinst test path
  (#13, #14, #25).
- **Complete example inventory** with an Ansible Vault template (#27, #28).

### Fixed

- **Node Exporter was DOWN in Prometheus on every fresh install** - ufw blocked
  Prometheus's own scrape, and both VM tests stayed green because neither had ever asked
  Prometheus whether its targets were reachable (#40).
- **`.gitignore` had excluded the entire example inventory since the initial commit** -
  every clone got an empty directory (#27).
- **The README quick start ran from the wrong directory**, so `ansible.cfg` was never
  loaded and the first task failed with "role common not found". Every automated test
  implicitly did the right thing, which is why nobody noticed (#29).
