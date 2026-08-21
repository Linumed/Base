# Updates

Three separate things get updated here, on different schedules and through different
mechanisms. Conflating them is the easiest way to either miss a security fix or
accidentally roll a service version you didn't mean to touch.

A fourth thing - moving the host to the next Debian major release - is not an update in the
same sense and has its own section at the end.

## Host security patches: automatic, no action needed

The `common` role's `unattended-upgrades` configuration installs security updates on
its own, daily, without a reboot (`common_unattended_upgrades_automatic_reboot` is
`false` by default - deliberately, an unannounced reboot on a host running an
integration engine is riskier than a kernel update waiting). See
[common: unattended-upgrades](../roles/common-unattended-upgrades.md) for what's
actually covered and how to verify it's running.

Node Exporter, being a native Debian package rather than a container, is covered by this
too - that's one of the reasons it isn't containerized (see
[Architecture](../architecture.md#components)).

## Container image versions: a deliberate variable bump

Every container image in this kit is pinned to a specific tag - `CONVENTIONS.md` forbids
`latest` outright, so nothing updates a container image on its own. Bumping one is a
conscious action:

| Role | Variable | Current pin |
|---|---|---|
| caddy | `caddy_image` | `caddy:2.11.4-alpine` |
| bridgelink | `bridgelink_image` | `innovarhealthcare/bridgelink:26.6.0-dhi-slim` |
| bridgelink | `bridgelink_postgres_image` | `postgres:17.11-alpine` |
| bridgelink | `bridgelink_exporter_image` | `python:3.13.15-alpine` |
| monitoring | `monitoring_prometheus_image` | `prom/prometheus:v3.13.2` |
| monitoring | `monitoring_grafana_image` | `grafana/grafana:13.1.4` |
| monitoring | `monitoring_loki_image` | `grafana/loki:3.7.6` |
| monitoring | `monitoring_alloy_image` | `grafana/alloy:v1.18.1` |
| monitoring | `monitoring_alertmanager_image` | `prom/alertmanager:v0.33.1` |
| monitoring | `monitoring_cadvisor_image` | `ghcr.io/google/cadvisor:v0.60.5` |
| monitoring | `monitoring_docker_socket_proxy_image` | `tecnativa/docker-socket-proxy:0.3.0` |
| orthanc | `orthanc_image` | `jodogne/orthanc-plugins:1.13.0` |
| orthanc | `orthanc_postgres_image` | `postgres:17.11-alpine` |

The roles remain the source of truth, but this table is no longer allowed to drift away
from them: `scripts/check-variable-docs.py` compares every row against the roles' defaults
on every push, and fails on a wrong tag, a missing image or one that no role defines. It
said "it will drift" until 2026-08-21, and it had - two tags behind and three images
missing entirely (issue #81). That was defensible while the table was a convenience. It
stopped being defensible when [ADR 0010](../adr/0010-internal-versus-interface-variables.md)
made this table the documentation that keeps those thirteen variable *names* inside the
v1.0 promise.

Note what is checked and what is not: that the table matches the roles, not that the pins
are current upstream. The latter needs a scanner and a network and is
`scripts/scan-images.py`'s job, weekly in CI (issue #67).

To bump one: override the variable in your inventory, re-run `site.yml`. Ansible
recreates only the affected container. There's no version-check tooling in this repo
yet - checking for new upstream releases is manual, per image.

**Before rolling monitoring image bumps into production**, read
[monitoring: Observability stack](../roles/monitoring.md#pitfalls) - several images in
that stack (Grafana, cAdvisor, docker-socket-proxy) have no `command:` override and
depend on being pre-pulled before the Compose apply computes their config hash, or a
version bump can trigger a spurious second recreate. That's already handled by the role
for a version you set once, but worth knowing if something looks like it "changed twice"
after a bump.

## Ansible itself and its collections

`ansible/requirements.yml` pins the collections this repo needs (currently
`community.docker`, `community.general`). Update with:

```bash
ansible-galaxy collection install -r ansible/requirements.yml --force
```

`--force` matters - without it, `ansible-galaxy` silently keeps an already-installed
older version even if the requirements file asks for a range that includes something
newer.

## After any update: verify, don't assume

The same rule applies here as after a first deployment - see
[Deployment: verifying a deployment actually worked](deployment.md#verifying-a-deployment-actually-worked).
A version bump that applies cleanly isn't the same as a version bump that still works;
run each role's verification commands afterward.

---

## Moving to the next Debian major release

**The supported path is a reinstall and a restore, not an in-place `dist-upgrade`.**

This is a stated position rather than a tested procedure, and the distinction matters. The
kit targets Debian stable and only Debian stable (`CONVENTIONS.md`). Debian 13 has full
security support until **9 August 2028** and LTS until **30 June 2030**; Debian 14 (Forky)
is in testing with no announced release date, and Debian's cadence has been roughly two
years. So this is a question with years of runway - but it needed an answer, because
without one an operator reaches Debian 13's end of life and discovers there is no guidance
at all.

### Why reinstall rather than upgrade in place

Not dogma - it follows from what this kit actually does to a host:

- **The roles configure through drop-ins, and a major upgrade rewrites the files they drop
  into.** `sshd_config.d/`, `apt.conf.d/`, `timesyncd.conf.d/`, `ssh.socket.d/` all survive
  in principle, but a `dist-upgrade` prompts about changed configuration files and the
  outcome depends on how those prompts are answered. That is not a path anyone should be
  taking on a clinic's integration host at 2am.
- **Docker comes from Docker's own repository**, keyed on the Debian codename. The role
  already anticipates the lag - it probes whether Docker publishes a suite for the running
  codename and falls back to the previous one (`docker_apt_release_fallback`, today
  `bookworm`). So this does not block an upgrade, but it does mean a freshly upgraded host
  may run Docker packages built for the *older* Debian for a while, and that fallback
  codename will need revisiting rather than being left at `bookworm` forever.
- **Nothing here has been tested across a major upgrade**, because there has not been one
  to test against.

A reinstall, by contrast, exercises paths that *are* tested on every change: the bootstrap
script, `site.yml` against a fresh host, and a restic restore. `test/vm-test.sh` proves the
first two on every relevant push, and the `backup` role's weekly restore test (#36) proves
the third on a real host.

### The procedure, in outline

1. Verify the backup restores - **before** touching anything. `restore_test_success` should
   be 1; see [Backup & Restore](backup-restore.md).
2. Install Debian 14 fresh on the target.
3. Run `scripts/bootstrap.sh`, then `site.yml` with the **same inventory and vault**.
4. Restore the data from restic.
5. Verify as described under "After any update" above, plus the role-specific checks.

The inventory and vault are what carry a deployment's identity across the move. Keeping
`bridgelink_server_id` stable matters especially - BridgeLink treats a changed ID as a
different server.

### When this gets revisited

When Debian 14 is released and there is something to test against. If an in-place upgrade
turns out to work reliably, it becomes a documented option; until it has been exercised
against a real host, presenting it as supported would be a guess dressed as guidance.
