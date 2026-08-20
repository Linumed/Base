# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Written in
English like the rest of the documentation (ADR 0002), even though commit messages are
German - a changelog addresses the same readers the
documentation does. Every entry names its issue, so the reasoning behind a change is one
click away instead of restated here.

## [Unreleased]

## [0.3.0] - 2026-08-20

The release where the product got its own name, and where the monitoring stack started
observing the one component it had been blind to. No new role.

Two of the defects below were found by a test written *for* the new feature rather than by
the feature itself, and neither was in the feature: one had been silently breaking every
Prometheus configuration change since the monitoring role was written, the other made the
new exporter unreachable. Both are recorded as rules in `CONVENTIONS.md`, because both had
a precedent in this repository that had simply never been carried over.

### Added

- **BridgeLink now reports application metrics to Prometheus** (#60). Until now the only
  BridgeLink data Prometheus held came from cAdvisor - CPU, RAM and network of the
  container. Those cannot distinguish a busy engine from a stalled one: a channel that is
  deployed but stopped, or a destination queue that has stopped draining, looks exactly
  like an idle healthy container. For an HL7/FHIR integration engine that is the failure
  mode that matters most, because it is silent.

  BridgeLink serves no `/metrics` endpoint of its own, so the `bridgelink` role gained a
  small exporter sidecar that queries the engine's REST API: per-channel and per-connector
  state, message counters by outcome, queue depth, JVM heap. Six alert rules ship with it
  in the monitoring role, dormant until the metrics appear (the same pattern as the backup
  rules).

  **Opt-in, and it stays that way**: the exporter authenticates against BridgeLink's own
  user database, which this kit does not manage - that user only exists after the operator
  logs into the Administrator for the first time. Set `bridgelink_exporter_enabled` and
  `monitoring_scrape_bridgelink` together once it does; see `docs/roles/bridgelink.md`.

  Prometheus reaches the exporter by container name over a shared Docker network
  (`linumed-base-metrics`, created by the monitoring role), not over a host port. No port
  is published for it beyond a loopback one for manual debugging. The Node Exporter job's
  `host.docker.internal` arrangement deliberately was not copied: it works only because
  Node Exporter is a native service ufw can protect, and a published container port would
  bypass the firewall (#64). This does mean the monitoring role has to run before the
  bridgelink role on a host - `site.yml` already orders them that way.

  `prometheus-community/json_exporter` was tested first and rejected: BridgeLink's JSON is
  serialised from its XML model, so a single-channel installation renders a list as an
  object and json_exporter's JSONPath silently matches nothing while still reporting the
  scrape as successful. The exporter reads the XML representation instead, which has no
  such ambiguity.

- **`vm-test` now exercises the BridgeLink exporter with the switch on** (#62). The
  existing double-run applies `site.yml` with role defaults, and the exporter defaults to
  off - so it proved the feature is a no-op while disabled, and nothing more. The enable
  path had never run through Ansible at all. A third pass now creates the BridgeLink user
  over the REST API (a throwaway VM has no operator to do it), re-applies with the
  exporter on, and checks the secret's ownership, the container healthcheck,
  `bridgelink_up`, and that Prometheus's new `bridgelink` job is healthy.

  Worth generalising: anything added behind a default-off flag ships with zero coverage
  unless a test deliberately turns it on.

- **Architecture diagrams are pre-rendered SVGs and were redrawn** (#65). The Mermaid
  diagrams in `ARCHITECTURE.md` were rendered by JavaScript in the reader's browser, which
  meant the site's theme reached the MkDocs build and nothing else - the same diagram
  looked different on GitHub and in Forgejo. They are now committed SVGs under `docs/img/`,
  rendered from sources in `docs/diagrams/` by `scripts/render-diagrams.sh`, and identical
  everywhere. The vendored `mermaid.min.js`, its init script and its stylesheet are gone,
  and with them the class-name workaround that only existed to stop the theme from
  fetching a renderer off a CDN at runtime.

  The target-architecture figure was also redrawn, because no amount of theming was going
  to fix it: it drew arrows at the boundary of the Docker group, including one from that
  group to a node inside itself, which renders as a label with no arrow attached. It is now
  two figures - what runs where, and what reports to whom - and the second says more than
  the original did, since the metric paths are actually visible.

  A trade-off worth stating: a static SVG cannot follow the site's light/dark toggle the
  way runtime rendering did. The diagrams render as a light card that stays legible on
  either background, which is the price of looking the same on all three surfaces.

  CI re-renders the diagrams on every docs build and fails if the committed SVGs are out of
  date, so a source edited without re-rendering cannot ship.

### Fixed

- **Prometheus config changes now actually reach Prometheus** (#63). Since the monitoring
  role was written, `prometheus.yml` and `alert-rules.yml` were bind-mounted as individual
  files. A single-file bind mount binds the inode, and Ansible's `template` module writes a
  temp file and renames it into place - creating a new one. The container went on reading
  the orphaned old copy, so **every configuration and alert-rule change after the first
  deploy silently did nothing**: the playbook reported `changed`, validation passed, the
  `/-/reload` handler answered 200, and Prometheus kept running the config from day one.
  Nothing reported an error anywhere.

  Both files now live in `{{ monitoring_deploy_dir }}/prometheus/` and that *directory* is
  mounted, which restores the intended behaviour while keeping the zero-downtime reload.
  The role also removes the two files from their old top-level location, so the next person
  debugging a config that "does not apply" cannot find and edit the copy that no longer
  matters.

  Only Prometheus was affected. Loki, Alloy and Alertmanager are updated by restarting
  their container, and a restart re-resolves the bind mount - it is Prometheus's
  deliberate HTTP reload, chosen for zero downtime, that made it the sole victim. Same
  failure class as the Caddyfile mount in #44/#48; the precedent existed and had simply
  never been applied here.

  **If you deployed an earlier version:** any Prometheus config or alert-rule change you
  made since the first deploy never took effect. The next playbook run applies all of them
  at once.

- **Documented the ownership the BridgeLink secret files actually need** (#60). The role's
  README and the hand-run reference in `docker/bridgelink/` both described
  `secrets/mirth.properties` as root-owned `0600`. A file-based Docker secret keeps the
  host's ownership when it is mounted, and the hardened image runs as UID 65532, so
  following that instruction produces `AccessDeniedException: /run/secrets/mirth_properties`
  and a restart loop - which, because the image supports no healthcheck, Compose still
  reports as a successfully started stack. The Ansible role always set the ownership
  correctly; only the documentation was wrong, and only the manual path was affected.

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

### Breaking

- **Every identifier changed with the product's name** (ADR 0006). Containers are
  `linumed-base-*`, the default deploy path is `/opt/linumed-base`, and the shared Docker
  network is `linumed-base-external`. There are no known installations of `v0.1.0` or
  `v0.2.0`, so no migration path is provided - treat an existing one as a fresh deployment
  rather than an upgrade.
- **Prometheus's configuration moved from `{{ monitoring_deploy_dir }}/prometheus.yml` and
  `alert-rules.yml` to `{{ monitoring_deploy_dir }}/prometheus/`** (#63). The role deletes
  the files at the old paths on the next run, so no manual migration is needed - but
  anything referencing the old location, including an operator's own tooling, has to follow
  the move. Edits at the old paths have no effect. This is the same shape of move as the
  Caddyfile in v0.2.0, and for the same underlying reason.

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
