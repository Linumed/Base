# Deployment

For the actual commands - cloning, filling in the inventory, encrypting the vault,
running the playbook - use the [repository README's quick
start](https://github.com/Linumed/Base#quick-start). This page covers what
happens during that run and why, across roles, which the README doesn't.

## Role order, and why it's fixed

`ansible/playbooks/site.yml` applies roles in one order, always:

```
common → docker → caddy → monitoring → bridgelink → backup
```

Each step depends on the one before it:

1. **common** hardens the bare host (SSH, ufw, fail2ban, unattended-upgrades, NTP)
   before anything else touches it. Nothing later assumes an unhardened host, but
   nothing earlier could run once ufw's default-deny is active either - the role handles
   its own sequencing internally (SSH rule before `ufw enable`).
2. **docker** installs Docker Engine and the Compose plugin. Every role after this one
   is a Docker Compose stack.
3. **caddy**, **monitoring**, **bridgelink** are independent of each other and could in
   principle run in any order relative to one another - the order here is roughly
   "smallest blast radius first". None of them currently depend on another being present
   (see [Architecture: network design](../architecture.md#network-design) for why - they
   don't share a network).
4. **backup** runs last because it backs up `/var/lib/docker/volumes`, which only has
   meaningful content once the other roles have created their volumes.

A partial deployment (running only some roles) is supported for maintenance or testing -
see the `roles:` list in `site.yml`, or point `ansible-playbook` at a single role with
`--tags` or a custom playbook - but isn't the documented path for a first install.

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
