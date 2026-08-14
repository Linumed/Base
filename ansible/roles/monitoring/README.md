# monitoring

Observability stack for Linumed OS (issues #8, #9): Prometheus, Grafana, Loki, Grafana
Alloy, Alertmanager, cAdvisor as a Docker Compose stack, plus a native Node Exporter.

## Variables

See `defaults/main.yml`, all prefixed `monitoring_*`. German user-facing writeup with
verification steps: `docs/roles/monitoring.md`.

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

**Grafana telemetry is off by default** (`reporting_enabled`, `check_for_updates`,
`analytics.enabled`) - matches CLAUDE.md's "no phone-home telemetry" principle; Grafana
phones home by default otherwise.

**Alloy needs the Docker socket, mounted read-only**, for `discovery.docker` container
labels. This is a real privilege trade-off (socket access is close to root-equivalent on
the host even read-only) accepted for v0.1; a `docker-socket-proxy` in front of it that
only exposes the read endpoints Alloy actually needs is tracked as a v0.2 hardening issue
(#21).

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

## What this role does not do

- Does not install Docker itself - see the `docker` role, which runs before this one in
  `playbooks/site.yml`.
- Does not open a Caddy route to Grafana - out of scope for v0.1 (see
  `ARCHITECTURE.md`, "Netzwerk-Design"). Comes when a service actually needs it.
- Does not model receiver groups, escalation stages, or quiet hours for Alertmanager -
  only a single `default` receiver mailing every configured address (#22).
- Does not harden the Docker-socket access for Alloy beyond a read-only mount (#21).
