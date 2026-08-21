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
| `monitoring_deploy_dir` | `/opt/linumed-base/monitoring` | Target directory on the host |
| `monitoring_grafana_admin_password` | `""` (required) | No default - the role aborts in its preflight if unset |
| `monitoring_grafana_admin_user` | `"admin"` | Grafana admin username |
| `monitoring_grafana_port` | `3000` | Bound to `127.0.0.1` only - access via SSH tunnel |
| `monitoring_prometheus_port` | `9090` | Bound to `127.0.0.1` only - for debugging/`promtool` |
| `monitoring_metrics_retention_days` | `90` | Prometheus retention |
| `monitoring_logs_retention_days` | `30` | Loki retention - shorter than metrics, see the GDPR section below |
| `monitoring_retention_days` | `~` (unset) | If set, overrides both retention values at once |
| `monitoring_prometheus_retention_size` | `5GB` | Hard cap independent of time-based retention, so a spike in ingestion cannot fill the disk on its own. Whichever limit is reached first wins |
| `monitoring_node_exporter_port` | `9100` | Must listen on all interfaces (see pitfalls), ufw blocks it from outside |
| `monitoring_node_exporter_deny_external` | `true` | Explicit ufw allow (Docker bridge range) plus deny rule for the Node Exporter port |
| `monitoring_node_exporter_textfile_dir` | `/var/lib/prometheus/node-exporter` | Where node_exporter reads textfile-collector metrics. The backup role writes its `.prom` file here via `backup_textfile_dir`; the two roles share no variable, so the values must agree or `BackupStale` never fires |
| `monitoring_node_exporter_allow_from` | `"172.16.0.0/12"` | Docker's default address-pool range - the source Prometheus's own scrape appears to come from through the bridge gateway; without this allow rule ahead of the deny rule, the "node" target is DOWN on every fresh install (#40) |
| `monitoring_alertmanager_smtp_smarthost` | `""` | Empty = no delivery (v0.1 behavior). Set = SMTP relay `host:port`, arms the stricter preflight |
| `monitoring_alertmanager_smtp_from` | `""` | Required once the smarthost is set |
| `monitoring_alertmanager_smtp_auth_username` / `_password` | `""` | Optional; if a username is set, the password is required |
| `monitoring_alertmanager_smtp_require_tls` | `true` | STARTTLS - only turn off if the smarthost is local/tunneled |
| `monitoring_alertmanager_receivers` | `[]` | List of email addresses that get the `default` receiver; required (at least one entry) once the smarthost is set |
| `monitoring_alertmanager_group_wait` / `_group_interval` / `_repeat_interval` | `30s` / `5m` / `4h` | Sensible defaults for a clinic on-call context, overridable |
| `monitoring_grafana_users` | `[]` | List of `{login, name, password, role}` - local Grafana accounts beyond the shared admin, see below |
| `monitoring_grafana_oidc_client_id` | `""` | Empty = OIDC off. Setting it arms a preflight requiring `client_secret`/`auth_url`/`token_url`/`api_url` too |
| `monitoring_grafana_oidc_allow_sign_up` | `false` | Whether a first-time OIDC login auto-creates a local Grafana account |
| `monitoring_grafana_oidc_name` | `SSO` | Label on Grafana's login button - set it to what your users call the identity provider |
| `monitoring_grafana_oidc_scopes` | `openid email profile` | The common denominator across AD, Entra and Keycloak. Only change it if your provider needs a different scope to return a name and an email |
| `monitoring_grafana_reporting_enabled` | `false` | Grafana's phone-home. Off by default per CONVENTIONS.md's no-telemetry rule |
| `monitoring_grafana_check_for_updates` | `false` | Grafana's update check, which is also a phone-home. Drives the plugin update check too |
| `monitoring_scrape_bridgelink` | `false` | Adds the `bridgelink` scrape job - turn on together with `bridgelink_exporter_enabled`, see below |
| `monitoring_metrics_network_name` | `linumed-base-metrics` | Docker network shared with exporters in other Compose stacks; Prometheus joins it |
| `monitoring_bridgelink_exporter_target` | `linumed-base-bridgelink-exporter:9151` | Scrape target - a container name on that network and the port inside the container, not a host port. Compared against the bridgelink role's Compose template by `scripts/check-variable-docs.py` |
| `monitoring_orthanc_target` | `linumed-base-orthanc:8042` | Scrape target for Orthanc's native metrics endpoint - a container name on the metrics network and the port *inside* that container, which `orthanc_http_port` no longer moves (issue #80). `scripts/check-variable-docs.py` compares both ends |

### Grafana users (issue #42)

The shared admin account means every dashboard/log view happens under one identity, and
Loki logs can carry personal data - "who looked at this" had no answer. Two independent
options, usable together or separately:

**Local accounts**, provisioned idempotently via Grafana's own HTTP API (there's no
declarative alternative - Grafana's file-based provisioning covers datasources/dashboards/
alerting, not users):

```yaml
monitoring_grafana_users:
  - login: "jsmith"
    name: "Jane Smith"
    password: "{{ vault_grafana_jsmith_password }}"   # from Ansible Vault
    role: "Viewer"   # or "Editor" / "Admin"
```

A `Viewer` can see dashboards and Loki logs but can't change a datasource or dashboard -
Grafana's own org-role enforcement, not something this role adds. The password is only
set when the account is first created; changing an existing user's password through this
variable isn't supported (see Pitfalls).

**OIDC**, pointing Grafana at an institution's *existing* identity provider - not a
bundled one (see [ADR 0003](../adr/0003-loopback-only-access-no-bundled-identity-provider.md)):

```yaml
monitoring_grafana_oidc_client_id: "grafana"
monitoring_grafana_oidc_client_secret: "{{ vault_grafana_oidc_secret }}"
monitoring_grafana_oidc_auth_url: "https://idp.example-clinic.org/oauth2/authorize"
monitoring_grafana_oidc_token_url: "https://idp.example-clinic.org/oauth2/token"
monitoring_grafana_oidc_api_url: "https://idp.example-clinic.org/oauth2/userinfo"
```

Costs zero extra containers - the difference to the Authentik role that was evaluated and
dropped (ADR 0003).

### BridgeLink application metrics (issue #60)

cAdvisor reports CPU, RAM and network for every container including BridgeLink, which
makes the gap easy to overlook: none of that says whether messages are actually moving. A
channel that is deployed but stopped, or a destination queue that stops draining, looks
exactly like an idle healthy engine from the outside. BridgeLink itself serves no
`/metrics` (verified against `26.6.0-dhi-slim`), so the `bridgelink` role ships an exporter
sidecar - see `docs/roles/bridgelink.md` for what it exports and why it is a script rather
than `json_exporter`.

Two switches, deliberately separate:

```yaml
bridgelink_exporter_enabled: true    # bridgelink role: deploy the sidecar
monitoring_scrape_bridgelink: true   # monitoring role: scrape it
```

They are not derived from each other and neither defaults to true, for two separate
reasons. On this side: a scrape job pointing at a target that was never deployed sits at
`up == 0` and trips the `HostDown` alert forever, so the monitoring role does not guess
whether BridgeLink exists on this host. On the other side: the exporter authenticates
against BridgeLink's own user database, which this kit does not manage - that user only
exists once someone has logged into the Administrator for the first time, which is after
the playbook has run. Create it first, then set both switches.

The alert rules (`BridgeLinkDown`, `BridgeLinkChannelNotStarted`,
`BridgeLinkConnectorNotStarted`, `BridgeLinkQueueBacklog`, `BridgeLinkErrorRate`,
`BridgeLinkHeapHigh`) ship unconditionally and are dormant until the metrics exist - the
same pattern as `BackupStale`: an absent metric produces no series, so the rule neither
fires nor errors in the meantime.

Prometheus reaches the exporter **by container name over a shared Docker network**
(`monitoring_metrics_network_name`, created by this role), not over a host port. This is
deliberately *not* the Node Exporter arrangement, and the difference is the point
(issue #64): Node Exporter is a native systemd service listening on all interfaces, which
ufw can protect, so `host.docker.internal` works for it. A container is different - a port
published on `127.0.0.1` cannot be reached from another container at all, and publishing it
on all interfaces would bypass ufw, since Docker installs its rules ahead of the firewall.

The shared-network arrangement is the same one the caddy role uses for
`linumed-base-external` (issue #39), including the fixed literal name: two independent
Compose projects can only agree on a network name if it is a constant rather than derived
from a project name.

Consequence for ordering: the exporter's stack joins this network as `external: true`, so
the monitoring role must run before the bridgelink role on a given host. `site.yml` already
does that.

## What gets changed

- `{{ monitoring_deploy_dir }}/` - Loki, Alertmanager and Alloy configuration, Grafana
  provisioning and the Docker Compose stack.
- `{{ monitoring_deploy_dir }}/prometheus/` - `prometheus.yml` and `alert-rules.yml`, in
  their own directory because that directory is what gets bind-mounted. Mounting the two
  files individually meant no config change after the first deploy ever reached Prometheus
  (issue #63); see the pitfall below.
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
docker run --rm --network container:linumed-base-loki curlimages/curl:latest -s -G \
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
- **An existing Grafana user's password is never changed by this role** (#42). The
  create-user API call only ever runs once per account (a 412 "user already exists"
  response is treated as success, not as "update it"); changing `password` in
  `monitoring_grafana_users` for an account that already exists has no effect on a
  subsequent run. Reset a forgotten password directly in Grafana (Administration ->
  Users) or via its API by hand - not something this role automates, to avoid silently
  invalidating a session or resetting a password an admin just changed by hand in the UI.
- **The org-role assignment runs on every apply, the account creation does not.** So a
  role change in `monitoring_grafana_users` (e.g. `Viewer` -> `Editor`) does take effect
  on the next run, even though the password does not.

### Editing Prometheus config by hand does not survive, and used to not apply at all

The bind mount is the **directory** `{{ monitoring_deploy_dir }}/prometheus/`, not the two
files inside it. That is not cosmetic: a single-file bind mount binds the inode, and
Ansible's `template` module writes a temp file and renames it into place, producing a new
one. With the old per-file mounts the container went on reading the orphaned copy, so
every change after the first deploy silently did nothing - the playbook said `changed`,
the validation passed, the `/-/reload` handler answered 200, and Prometheus kept running
the config from day one. Nothing anywhere reported a problem (issue #63).

The other services in this stack were never affected: they are updated by restarting their
container, and a restart re-resolves the bind mount. Prometheus is the only one reloaded
over HTTP, which is worth keeping for zero downtime - hence the directory.

Note the practical consequence for debugging: an *in-place* edit of
`prometheus/prometheus.yml` on the host does now reach the container, but the next
playbook run overwrites it. Change the template, not the deployed file.

## GDPR: what ends up in Loki

Logs are personal data in a sense metrics are not: journal and container logs can
contain IP addresses, usernames, and in individual cases application data too, depending
on what the respective application logs. Because of that:

- **Retention is deliberately shorter** than for metrics
  (`monitoring_logs_retention_days: 30` vs. `monitoring_metrics_retention_days: 90`) -
  data minimization, not an arbitrary choice.
- **Access to Grafana/Loki is limited to SSH-tunnel users** (no public access in v0.1),
  which limits the circle of people who can see logs at all - see `common`'s
  `common_ssh_tunnel_users` (#41) for shell-less accounts scoped to exactly this port.
- **Individual Grafana accounts (`monitoring_grafana_users`, #42), not a shared admin
  login**, mean "who looked at these logs" now has an answer in Grafana's own logs -
  previously every viewer was the same `admin` identity.
- **What actually gets logged depends on the applications running** - this role only
  collects what the applications themselves write to the journal or to
  `stdout`/`stderr`. A customer's processing overview needs to document which
  applications run on the host and what they log - this role can't answer that
  generically.
- Alloy has not touched the Docker socket directly since #21 - a `docker-socket-proxy`
  in front of it only allows `GET /containers*` and `GET /networks` (no `POST`, no exec,
  no build), see `ansible/roles/monitoring/README.md`.
