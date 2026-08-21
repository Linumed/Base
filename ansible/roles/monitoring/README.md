# monitoring

Observability stack for Linumed Base (issues #8, #9): Prometheus, Grafana, Loki, Grafana
Alloy, Alertmanager, cAdvisor as a Docker Compose stack, plus a native Node Exporter.

## Variables

See `defaults/main.yml`, all prefixed `monitoring_*`. User-facing writeup with
verification steps: `docs/roles/monitoring.md`.

## Prometheus config is mounted as a directory, not as two files

`prometheus.yml` and `alert-rules.yml` are deployed into
`{{ monitoring_deploy_dir }}/prometheus/`, and that directory is what the Compose file
bind-mounts. Mounting the two files individually - which is what this role did until
issue #63 - binds their inodes, and Ansible replaces them by atomic rename. The container
then reads the orphaned old copies forever: playbook `changed`, validation green,
`/-/reload` answering 200, and Prometheus still running the config from the first deploy,
with nothing reporting an error.

Only Prometheus was affected, because it is the only service here that is reloaded over
HTTP instead of restarted - a `docker restart` re-resolves the bind mount, so Loki, Alloy
and Alertmanager were always fine. The zero-downtime reload is worth keeping, hence the
directory rather than swapping the reload for a restart.

The role also deletes the pre-#63 files at the old top-level location, so nobody debugs
the copy that no longer counts.

## Exporters in other Compose stacks join linumed-base-metrics

Prometheus sits on a second network besides the stack's default one, named by
`monitoring_metrics_network_name`. Exporters that live in other Compose projects - the
BridgeLink one today - join it as `external: true` and are scraped by container name.

Not a host port, deliberately: one published on `127.0.0.1` cannot be reached from another
container, and one on all interfaces bypasses ufw, since Docker installs its rules ahead of
the firewall. The Node Exporter job's `host.docker.internal` is not a counterexample - that
one is a native systemd service, which is exactly why ufw can protect it (issue #64).

The fixed literal name is the same reasoning as the caddy role's `linumed-base-external`
(#39): two independent Compose projects can only agree on a network name that is a
constant, not one derived from a project name.

## Decisions and why

**Grafana Alloy, not Promtail.** Promtail reached end-of-life on 2026-03-02 and gets no
more security fixes - not an option for a kit that markets itself as DSGVO-compliant.
Alloy is Grafana's own replacement and does the same job (ship host/container logs to
Loki).

**Node Exporter is a native Debian package, not a container.** It gets security updates
through the `common` role's unattended-upgrades automatically, needs none of the
`--pid=host`/`/proc`/`/sys`/rootfs mounts a containerized node_exporter requires, and -
the part that actually matters for security - `ufw` can protect its port. A published
Docker container port bypasses `ufw` entirely (see the `common` role's ufw
documentation); a native process's socket does not. The trade-off: Node Exporter must
listen on all interfaces (`:9100`, not `127.0.0.1`) because Prometheus, running in a
container, cannot reach the host's loopback - so the role explicitly denies external
access to that port via `community.general.ufw` (`monitoring_node_exporter_deny_external`,
default `true`) rather than relying on it being "just" a scrape target nobody thinks to
probe.

**Only Grafana and Prometheus are published, and only on `127.0.0.1`.** Loki,
Alertmanager, and cAdvisor are reached by the other stack members via Compose service
names and get no host port at all - not "bound to loopback", genuinely not published.
This sidesteps the Docker-vs-ufw gap entirely for those three, and avoids a port clash
with Mirth Connect (#12), which is expected to use 8080 like cAdvisor conventionally
would. Access Grafana via SSH port forwarding:
```bash
ssh -L 3000:127.0.0.1:3000 <user>@<host>
```

**Retention is split by data kind.** `monitoring_metrics_retention_days` (default 90) and
`monitoring_logs_retention_days` (default 30, shorter) - logs can contain personal data
(IP addresses, usernames), so a shorter default is data minimization, not an arbitrary
choice. `monitoring_retention_days`, if set, overrides both - kept as an escape hatch so
the single variable name from an earlier ARCHITECTURE.md draft still means something.
Loki's retention needs its compactor enabled with `retention_enabled: true` - setting
`retention_period` alone does not delete anything, it only makes the setting visible in
config. Additionally, `monitoring_prometheus_retention_size` is a hard cap independent of
time-based retention, so a spike in ingestion volume can't fill the disk on its own.

**No default Grafana admin password.** The role's preflight refuses to run without
`monitoring_grafana_admin_password` set - same pattern as `common`'s SSH preflight. Set it
via Ansible Vault; this role never generates or logs one.

**Grafana telemetry is off by default** - matches CONVENTIONS.md's "no phone-home
telemetry" principle; Grafana phones home by default otherwise. All four settings Grafana's
`[analytics]` section actually has are covered: `reporting_enabled` and `check_for_updates`
via `monitoring_grafana_reporting_enabled` and `monitoring_grafana_check_for_updates`,
`check_for_plugin_updates` from the same variable as the latter, and
`feedback_links_enabled` fixed to false in the compose template. This list said
`analytics.enabled` until 2026-08-21, which is not a Grafana setting (issue #75).

**Alloy never touches the Docker socket directly (#21).** A `docker-socket-proxy`
(`tecnativa/docker-socket-proxy`) sits in between: it mounts `/var/run/docker.sock`
read-only and forwards only `GET /containers*` (container list for `discovery.docker`,
log streaming for `loki.source.docker`) and `GET /networks` (`discovery.docker` also
queries per-container network labels - confirmed against a real Alloy that it 403s
without this). No `POST` at all, so no start/stop/restart/exec/build, no socket access
from any other container. Alloy reaches it as `tcp://docker-socket-proxy:2375` by service
name, no host port published.

**Alertmanager delivery is opt-in and all-or-nothing (#22).** Leaving
`monitoring_alertmanager_smtp_smarthost` empty (the default) deploys the same
receiver-less config as before - alerts stay visible only via the Alertmanager API/UI.
Setting it switches the role into "delivery configured" mode, which requires
`monitoring_alertmanager_smtp_from` and at least one address in
`monitoring_alertmanager_receivers` (and a password if
`monitoring_alertmanager_smtp_auth_username` is set) - a preflight refuses to deploy a
half-configured delivery path rather than silently dropping alerts. Recipient policy
(who gets what, escalation stages, quiet hours) is a per-site decision this role does not
make; it only wires up a single `default` receiver that mails every alert to every
configured address. `monitoring_alertmanager_group_wait`/`_group_interval`/
`_repeat_interval` default to values sane for a clinic on-call context (batch a burst,
re-page every 4h) but can be overridden.

**Grafana users beyond the shared admin account (#42).** `monitoring_grafana_users`
provisions local accounts (login/name/password/role) idempotently via the Grafana HTTP
API against `127.0.0.1` - Grafana's own file-based provisioning
(`provisioning/`) covers datasources, dashboards and alerting, but not users, confirmed
against a real 13.1.3 instance while building this, there is no declarative alternative.
Runs after "Deploy the monitoring stack" has already waited for the healthcheck, so the
API is up by the time it's called; the admin password never leaves the host or appears
on a command line (`ansible.builtin.uri`, `no_log: true` throughout). A 412 response from
Grafana's create-user endpoint ("user already exists") is treated as the success case for
an existing account - only the org-role assignment is re-applied on every run, an
existing user's password is deliberately left untouched (see docs/roles/monitoring.md for
why). Same "refuse a half-configured entry" preflight pattern as elsewhere in this role:
a `monitoring_grafana_users` entry with no password fails the play before touching
anything.

**Grafana OIDC as a connection point, not a bundled identity provider (#42, ADR 0003).**
`monitoring_grafana_oidc_*` points Grafana's built-in generic OAuth support at an
institution's *existing* IdP (AD, Entra, Keycloak, ...). Empty `client_id` (the default)
means the whole `GF_AUTH_GENERIC_OAUTH_*` block in the rendered compose file is skipped -
nothing about auth changes. Setting `client_id` requires `client_secret`, `auth_url`,
`token_url` and `api_url` all set too - same all-or-nothing preflight as the Alertmanager
SMTP variables, refusing to deploy a Grafana that advertises SSO and then fails at login
time. `monitoring_grafana_oidc_allow_sign_up` defaults to `false` on purpose: letting
anyone who authenticates against the external IdP get an auto-created local account is a
wider door than the explicit `monitoring_grafana_users` list above.

## What this role does not do

- Does not install Docker itself - see the `docker` role, which runs before this one in
  `playbooks/site.yml`.
- Does not open a Caddy route to Grafana - out of scope for v0.1 (see
  `ARCHITECTURE.md`, "Netzwerk-Design"). Comes when a service actually needs it.
- Does not model receiver groups, escalation stages, or quiet hours for Alertmanager -
  only a single `default` receiver mailing every configured address (#22).
- Does not need a socket proxy for cAdvisor - it reads container metrics via bind mounts
  (`/rootfs`, `/var/lib/docker`), never touches `docker.sock` in the first place.
