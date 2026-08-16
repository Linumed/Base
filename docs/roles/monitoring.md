# monitoring: Observability stack

## Problem

Without monitoring, a full disk, a crashed container or a failed backup run only gets
noticed once a user complains - or not at all. This role brings metrics (Prometheus),
dashboards (Grafana), logs (Loki) and alerting (Alertmanager) as a Docker Compose stack,
plus host metrics via a native Node Exporter service.

## Variables

All variables are prefixed `monitoring_*` and have sensible defaults in
`ansible/roles/monitoring/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `monitoring_deploy_dir` | `/opt/linumed-os/monitoring` | Target directory on the host |
| `monitoring_grafana_admin_password` | `""` (required) | No default - the role aborts in its preflight if unset |
| `monitoring_grafana_admin_user` | `"admin"` | Grafana admin username |
| `monitoring_grafana_port` | `3000` | Bound to `127.0.0.1` only - access via SSH tunnel |
| `monitoring_prometheus_port` | `9090` | Bound to `127.0.0.1` only - for debugging/`promtool` |
| `monitoring_metrics_retention_days` | `90` | Prometheus retention |
| `monitoring_logs_retention_days` | `30` | Loki retention - shorter than metrics, see the GDPR section below |
| `monitoring_retention_days` | `~` (unset) | If set, overrides both retention values at once |
| `monitoring_node_exporter_port` | `9100` | Must listen on all interfaces (see pitfalls), ufw blocks it from outside |
| `monitoring_node_exporter_deny_external` | `true` | Explicit ufw allow (Docker bridge range) plus deny rule for the Node Exporter port |
| `monitoring_node_exporter_allow_from` | `"172.16.0.0/12"` | Docker's default address-pool range - the source Prometheus's own scrape appears to come from through the bridge gateway; without this allow rule ahead of the deny rule, the "node" target is DOWN on every fresh install (#40) |
| `monitoring_alertmanager_smtp_smarthost` | `""` | Empty = no delivery (v0.1 behavior). Set = SMTP relay `host:port`, arms the stricter preflight |
| `monitoring_alertmanager_smtp_from` | `""` | Required once the smarthost is set |
| `monitoring_alertmanager_smtp_auth_username` / `_password` | `""` | Optional; if a username is set, the password is required |
| `monitoring_alertmanager_smtp_require_tls` | `true` | STARTTLS - only turn off if the smarthost is local/tunneled |
| `monitoring_alertmanager_receivers` | `[]` | List of email addresses that get the `default` receiver; required (at least one entry) once the smarthost is set |
| `monitoring_alertmanager_group_wait` / `_group_interval` / `_repeat_interval` | `30s` / `5m` / `4h` | Sensible defaults for a clinic on-call context, overridable |

## What gets changed

- `{{ monitoring_deploy_dir }}/` - Prometheus, Loki, Alertmanager and Alloy
  configuration, Grafana provisioning and the Docker Compose stack.
- `/etc/default/prometheus-node-exporter` - command-line arguments for the native
  service.
- `/var/lib/prometheus/node-exporter/` - textfile-collector directory (used by the
  `backup` role).
- ufw rules: `allow` from `monitoring_node_exporter_allow_from`, then `deny`, both on
  `monitoring_node_exporter_port`/tcp - order matters, see pitfalls.
- Docker containers: Prometheus, Grafana, Loki, Grafana Alloy, Alertmanager, cAdvisor,
  docker-socket-proxy.

## Accessing Grafana

Reachable only through an SSH tunnel by default, no Caddy routing in v0.1 (see
`ARCHITECTURE.md`, "Network design"):

```bash
ssh -L 3000:127.0.0.1:3000 <user>@<host>
# then in a browser: http://localhost:3000
```

## Verification

Not just "containers are running" - check actual function:

```bash
# Every scrape target is actually UP
curl -s localhost:9090/api/v1/targets | python3 -c \
  "import sys,json;[print(t['labels']['job'],t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"

# A host metric actually exists (not just "target green")
curl -s 'localhost:9090/api/v1/query?query=node_load1'

# Prometheus knows about Alertmanager
curl -s localhost:9090/api/v1/alertmanagers

# Every alert rule loaded and "ok"
curl -s localhost:9090/api/v1/rules

# Grafana healthy
curl -s localhost:3000/api/health
```

Loki and Alertmanager have **no published port** (see pitfalls) - from outside the
Compose network they're only reachable through a temporary debug container in the same
network namespace:

```bash
docker run --rm --network container:linumed-os-loki curlimages/curl:latest -s -G \
  "http://127.0.0.1:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="journal"}' --data-urlencode limit=3
```

## Pitfalls

- **Node Exporter deliberately listens on all interfaces, not just `127.0.0.1`.** A
  container (Prometheus) can't reach the host's loopback - so the service listens on
  `:9100`, and Prometheus scrapes it via `host.docker.internal`
  (`extra_hosts: host-gateway`). The actual protection is the explicit ufw rule pair, not
  the binding - and that genuinely works here, unlike with a published Docker container
  port (see `docs/roles/common-ufw.md`, "Docker bypasses ufw"). The allow rule has to
  come *before* the deny rule for the same port - confirmed against a real VM (#40): a
  deny-only setup blocks Prometheus's own scrape too, since it arrives via the same
  Docker bridge gateway address.
- **Loki and Alertmanager have no host port.** They're reachable only inside the Compose
  network, by service name - that's intentional (smaller attack surface), not an
  oversight. Debugging goes through the network-namespace trick shown above.
- **`grafana/loki` has no healthcheck** - the image contains no shell, no `wget`, nothing
  besides the loki binary itself. An exec-based healthcheck is therefore technically
  impossible; functional verification goes through a real query (see Verification).
- **Retention alone deletes nothing.** `monitoring_logs_retention_days` only sets
  `retention_period` on Loki - without the compactor enabled (`retention_enabled: true`,
  configured by this role), nothing actually happens and the disk fills up.
- **`monitoring_retention_days` overrides both values at once**, not just one - anyone
  who only wants to change metrics retention sets `monitoring_metrics_retention_days`
  directly, not the shared variable.
- **Alertmanager delivery is opt-in and all-or-nothing** (#22). Without
  `monitoring_alertmanager_smtp_smarthost` set, alerts still only land in Alertmanager
  and are visible via its API - nobody gets notified. Once the smarthost is set, a
  preflight additionally requires `monitoring_alertmanager_smtp_from` and at least one
  address in `monitoring_alertmanager_receivers` (and a password, if
  `monitoring_alertmanager_smtp_auth_username` is set) - a half-configured delivery setup
  is rejected rather than silently swallowing alerts. Recipient groups, escalation
  levels and quiet hours per site are deliberately not part of this role: there is only
  one `default` receiver that emails every configured address.
- **docker-socket-proxy has no `command:` override**, same as Grafana and cAdvisor - it
  must stay in the pre-pull loop in `tasks/stack.yml`, or a fresh install's second
  `site.yml` run spuriously recreates it and breaks idempotency (found and fixed the same
  day as the ufw issue above, see the role's `tasks/stack.yml` comments).
- **Alertmanager, cAdvisor, docker-socket-proxy and Alloy all have healthchecks now**
  (issue #38) - `grafana/loki` was the genuine exception, not a precedent. Checked before
  assuming any of the other four couldn't have one: all had a working option once
  actually tested (`wget` was present, or a documented HTTP endpoint answered). Alloy is
  the interesting case - no `wget`/`curl` in its image, but it does have a shell, so its
  healthcheck uses bash's `/dev/tcp` pseudo-device to speak raw HTTP instead. That
  command needs single-quoted YAML, not double: a double-quoted YAML scalar interprets
  `\r\n` as real control characters at parse time, before Docker Compose ever reads it,
  which silently breaks the embedded shell command (confirmed the hard way while
  building this).

## GDPR: what ends up in Loki

Logs are personal data in a sense metrics are not: journal and container logs can
contain IP addresses, usernames, and in individual cases application data too, depending
on what the respective application logs. Because of that:

- **Retention is deliberately shorter** than for metrics
  (`monitoring_logs_retention_days: 30` vs. `monitoring_metrics_retention_days: 90`) -
  data minimization, not an arbitrary choice.
- **Access to Grafana/Loki is limited to SSH-tunnel users** (no public access in v0.1),
  which limits the circle of people who can see logs at all.
- **What actually gets logged depends on the applications running** - this role only
  collects what the applications themselves write to the journal or to
  `stdout`/`stderr`. A customer's processing overview needs to document which
  applications run on the host and what they log - this role can't answer that
  generically.
- Alloy has not touched the Docker socket directly since #21 - a `docker-socket-proxy`
  in front of it only allows `GET /containers*` and `GET /networks` (no `POST`, no exec,
  no build), see `ansible/roles/monitoring/README.md`.
