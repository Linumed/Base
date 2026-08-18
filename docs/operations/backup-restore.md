# Backup & Restore

The `backup` role's own page covers the mechanics - variables, backends, the exact
`restic` commands, what's backed up and what isn't:
[backup: Encrypted backups](../roles/backup.md). This page is the end-to-end picture:
what a real restore actually touches, across roles, which the role's own page
deliberately doesn't repeat.

## What a full restore actually means

A restore of `/opt/linumed-base` and `/var/lib/docker/volumes` brings back:

- every role's configuration and rendered templates (`/opt/linumed-base/*`)
- BridgeLink's app data, including its keystore and `server.id`
  (`bridgelink_appdata` volume)
- BridgeLink's PostgreSQL database, channel configuration and stored messages
  (`bridgelink_db_data` volume)
- Prometheus, Grafana and Loki's own data (dashboards, metrics, logs)

What it does **not** bring back on its own: the containers and services themselves.
restic restores files; it doesn't run `docker compose up`. A real disaster-recovery
sequence is: fresh host → run `site.yml` to get roles, Docker and empty containers in
place → stop the containers that own the volumes you're restoring into → restore with
restic → start the containers again. Practicing this is exactly what the restore test
below is for; skipping straight to "restic restore" without the surrounding sequence is
how a restore test looks successful and a real recovery doesn't.

## The two secrets a restore needs that live outside the backup itself

Both of these are why "the backup exists" and "the backup is useful" are different
claims - see the `backup` role's own page, "Without the restic password, everything is
lost", for the reasoning:

1. **The restic encryption password** (`backup_restic_password`). Not in the backup, by
   design - it's what makes the backup useless to anyone who steals the storage.
2. **BridgeLink's keystore passwords** (`bridgelink_keystore_storepass` /
   `_keypass`). These aren't secrets restic manages either - they're Ansible Vault
   values. A restored BridgeLink appdata volume is only readable with the same keystore
   passwords that created it.

Both need to survive independently of the host being restored - see the `backup` role's
page for where a second copy belongs.

## Restore test: how often, and what actually counts

The `backup` role's page has the exact commands. What's worth adding here: a restore
test that only checks `restic restore` succeeds and a spot-check `diff` matches is
testing restic, not testing your ability to recover. A test that's actually worth
something restores into a throwaway environment and brings the stack up from there -
the same sequence as the disaster-recovery walkthrough above, run for real often enough
that the first time isn't during an actual incident.

There's no automated version of this in v0.1 - see
[docs/ROADMAP.md](../ROADMAP.md) and issue #36. Until that exists, put it on a
calendar; a restore procedure nobody has run since it was written is not a verified
procedure.
