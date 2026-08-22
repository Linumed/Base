# Deployment

For the actual commands - cloning, filling in the inventory, encrypting the vault,
running the playbook - use the [repository README's quick
start](https://github.com/Linumed/Base#quick-start). This page covers what
happens during that run and why, across roles, which the README doesn't.

## Role order, and why it's fixed

`ansible/playbooks/site.yml` applies roles in one order, always:

```
common → docker → caddy → monitoring → bridgelink → orthanc → backup
```

This said `common → docker → caddy → monitoring → bridgelink → backup` - missing orthanc -
until 2026-08-22, the same kind of staleness `node-baseline.yml`'s header once had: correct
when written, never re-checked when the seventh role landed.

Each step depends on the one before it:

1. **common** hardens the bare host (SSH, ufw, fail2ban, unattended-upgrades, NTP)
   before anything else touches it. Nothing later assumes an unhardened host, but
   nothing earlier could run once ufw's default-deny is active either - the role handles
   its own sequencing internally (SSH rule before `ufw enable`).
2. **docker** installs Docker Engine and the Compose plugin. Every role after this one
   is a Docker Compose stack.
3. **caddy**, **monitoring**, **bridgelink**, **orthanc** are independent of each other
   with two exceptions, and the order here is otherwise roughly "smallest blast radius
   first". With `bridgelink_exporter_enabled`, the bridgelink stack joins a Docker network
   the **monitoring** role creates; with `orthanc_metrics_enabled` (on by default), Orthanc
   does the same. Either way monitoring has to have run on the host first, or Compose fails
   on a missing external network (issue #64) - both roles now check for the network
   themselves and abort with a clear message rather than Compose's raw error (issue #86).
   With both switches off, all four are genuinely independent. See
   [Architecture: network design](../architecture.md#network-design).
4. **backup** runs last because it backs up `/var/lib/docker/volumes`, which only has
   meaningful content once the other roles have created their volumes.

### Deploying a subset of roles

Set `linumed_base_roles` in the inventory to deploy less than the full stack (issue #86) -
for example everything except `orthanc` on a site with no imaging. Either edit the
commented example in `group_vars/linumed/vars.yml` by hand, or run
`scripts/select-roles.sh` against that file (issue #87) - a `whiptail` picker that shows
the resulting YAML before writing it and grays out `orthanc` unless `monitoring` is also
selected, rather than letting an invalid combination reach the preflight below at all.
See `scripts/README.md` for the full usage. `site.yml` is still the one playbook to run; a
preflight
aborts with a clear message if the selection names an unknown role, omits a role another
selected one needs (`docker` for any Compose role, `common` for `monitoring` unless
`monitoring_node_exporter_deny_external` is off, `monitoring` for `orthanc`/`bridgelink`
with their metrics switches on), or if a role that is *not* selected has already run on
this host - deselecting does not remove anything; see
[teardown](teardown.md) for that.

**`node-baseline.yml` is the one selection that ships as its own playbook**, because it is
the one aimed at a named audience rather than a general mechanism:

```bash
ansible-playbook -i inventory/myhospital playbooks/node-baseline.yml --ask-vault-pass
```

It is a thin wrapper setting `linumed_base_roles: [common, docker, backup]` - the roles
that ship no Compose stack and depend on no other role. Meant for a host that runs
something else on top: a Kubernetes node, or a server that should be hardened and backed up
without also carrying an integration engine and a monitoring stack. See
[ADR 0007](../adr/0007-docker-compose-not-kubernetes.md) for why the service stacks stay
Compose-only, and what that leaves usable for a Kubernetes site.

**Set `backup_paths`.** Its default covers this kit's own state (`/opt/linumed-base`,
`/var/lib/docker/volumes`), which is the wrong answer on a node whose data lives
elsewhere. Checked at deploy time and aborts rather than failing silently at 03:00 - but a
value that is merely incomplete will not be caught for you.

`node-baseline.yml` sets `backup_restore_test_enabled: false` by default, for the same
reason: the playbook has no way to know what `backup_paths` will be set to, so it cannot
pick a `backup_restore_test_diff_paths` that means anything, and testing a restore against
nothing is worse than not testing it (issue #86). Once `backup_paths` names real data on
this node, set `backup_restore_test_diff_paths` to match and turn
`backup_restore_test_enabled` back on - otherwise a restic backup runs weekly with nothing
ever confirming it can be restored.

**Ansible tags are deliberately not the mechanism here.** They would live on the command
line rather than in the inventory: an operator who deployed a subset and later runs plain
`site.yml` would silently get the full stack back, with no record anywhere of what the host
was meant to be. `linumed_base_roles` keeps that record where the rest of the host's
configuration already lives.

## One host, and what that means

**Linumed Base deploys to a single host.** Not a limitation that was discovered late - it
follows from the design - but it was never written down, which meant an evaluator had no way
to find out except by trying (issue #68).

What makes it a single-host kit, concretely:

- `site.yml` applies all seven roles to the same machine.
- Prometheus reaches the Node Exporter over `host.docker.internal`, which resolves to *this*
  host's gateway, and reaches the BridgeLink exporter over a Docker network that exists on
  *this* host (issue #64).
- BridgeLink and its PostgreSQL are one Compose stack, communicating over that stack's own
  network.
- The `backup` role backs up `/var/lib/docker/volumes` on the machine it runs on.

Running the roles against several hosts in an inventory works - each one gets its own
complete, independent installation. What does **not** work is splitting the kit across
hosts: monitoring on one machine and BridgeLink on another is not a supported arrangement,
and with `bridgelink_exporter_enabled` it fails outright, because the exporter joins a
network the monitoring role creates locally.

### The consequences worth knowing before choosing this kit

- **No high availability.** One host is a single point of failure. If an HL7 interface has to
  survive the loss of a machine, this kit does not provide that - see
  [ADR 0007](../adr/0007-docker-compose-not-kubernetes.md), which states the same thing from
  the Kubernetes side.
- **Capacity is one machine's capacity.** Four Compose stacks sit comfortably on one server
  today; that is a fact about the current service set, not a promise about a future one.
- **A central monitoring stack across sites is not what this is.** Each host monitors
  itself. Feeding several installations into one Grafana is possible - it is the operator's
  own federation problem, not something the kit sets up.

None of this is a step towards a distributed version. It is the shape the kit has, stated so
it can be evaluated.

## First run vs. every run after

The first run on a host does more work than every subsequent one: package installs,
image pulls, keystore/database initialization for BridgeLink, the first restic
repository init. Expect it to take several minutes - BridgeLink's image alone is
substantial, and monitoring pulls seven container images.

Every run after that should be fast and change nothing if nothing changed
(`changed=0` on a second run is a hard requirement for every role in this repo, not a
nice-to-have - see `CONVENTIONS.md`). If a routine re-run reports unexpected changes, that's
worth investigating before assuming it's fine; see
[Troubleshooting](troubleshooting.md).

## Re-running after a configuration change

Changing a variable (a new `caddy_sites` entry, a different retention setting, a bumped
image pin) and re-running `site.yml` is the normal way to apply it - there's no separate
"update" mechanism. Ansible only touches what actually changed. For image version bumps
specifically, see [Updates](updates.md).

## Verifying a deployment actually worked

A green Ansible run means the playbook applied without errors - it does not mean the
resulting stack is healthy. This distinction mattered in practice: issue #40 found that
node_exporter's Prometheus target was silently DOWN on every fresh install (blocked by
ufw) while the playbook itself reported success every time. Each role's own page has a
**Verification** section with commands that check actual function, not just that a
container is running - use those after any deployment, not just the Ansible exit code.
