# Updates

Three separate things get updated here, on different schedules and through different
mechanisms. Conflating them is the easiest way to either miss a security fix or
accidentally roll a service version you didn't mean to touch.

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
| bridgelink | `bridgelink_postgres_image` | `postgres:17.10-alpine` |
| monitoring | `monitoring_prometheus_image` | `prom/prometheus:v3.13.2` |
| monitoring | `monitoring_grafana_image` | `grafana/grafana:13.1.3` |
| monitoring | `monitoring_loki_image` | `grafana/loki:3.7.6` |
| monitoring | `monitoring_alloy_image` | `grafana/alloy:v1.18.1` |
| monitoring | `monitoring_alertmanager_image` | `prom/alertmanager:v0.33.1` |
| monitoring | `monitoring_cadvisor_image` | `ghcr.io/google/cadvisor:v0.60.5` |
| monitoring | `monitoring_docker_socket_proxy_image` | `tecnativa/docker-socket-proxy:0.3.0` |

(Exact current values are in each role's `defaults/main.yml` - the table above is a
pointer, not the source of truth; it will drift.)

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
