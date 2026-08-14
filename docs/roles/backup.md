# backup: Encrypted backups

## Problem

A server without a backup is a server whose data loss is only a matter of time - disk
failure, an operator mistake, a failed update. This role sets up encrypted, automated
backups with [restic](https://restic.net/), scheduled via a systemd timer, with result
metrics for Prometheus.

## Variables

All variables are prefixed `backup_*` and live in
`ansible/roles/backup/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `backup_repository` | `""` (required) | restic repository URI, any backend restic supports |
| `backup_restic_password` | `""` (required) | Encryption password - **without this password, all backups are unrecoverable, permanently** |
| `backup_paths` | `/opt/linumed-os`, `/var/lib/docker/volumes` | What gets backed up |
| `backup_retention_keep_daily/weekly/monthly` | `7`/`4`/`6` | Retention after `restic forget` |
| `backup_schedule` | `*-*-* 03:00:00` | systemd `OnCalendar` expression |

Without `backup_repository` and `backup_restic_password`, the role aborts in its
preflight. Both belong in Ansible Vault.

## Backend examples

```yaml
# Local / external drive
backup_repository: "/mnt/backup-disk/linumed-os"

# SFTP
backup_repository: "sftp:user@backup-host:/srv/restic/linumed-os"

# S3-compatible (e.g. Hetzner Object Storage) - credentials set separately
# as AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, not part of this role
backup_repository: "s3:https://fsn1.your-objectstorage.com/linumed-os-backup"
```

This role doesn't set up the backend itself - SSH keys, S3 buckets or IAM policies must
already exist.

## What gets backed up

By default, `/opt/linumed-os` (configuration and secrets for every role) and
`/var/lib/docker/volumes` (every named Docker volume: Prometheus, Loki and Grafana data,
BridgeLink's app data and its PostgreSQL database). Direct file access, no
`docker-volume-backup`, no database-native dump tool.

## Verification

```bash
# Is the timer active?
systemctl status linumed-os-backup.timer

# Last run
systemctl status linumed-os-backup.service
journalctl -u linumed-os-backup.service -n 50

# Was the metric actually written?
cat /var/lib/prometheus/node-exporter/backup.prom

# Are snapshots actually in the repository?
restic snapshots
```

A manual test run: `sudo systemctl start linumed-os-backup.service`.

## Restore test (mandatory, not optional)

A backup that has never been restored is not a verified backup - that holds generally,
not just for this repo. Manual procedure, repeat regularly:

```bash
export RESTIC_REPOSITORY="<same repository as backup_repository>"
export RESTIC_PASSWORD_FILE=/etc/restic/password

restic snapshots                                    # which snapshots exist
restic restore latest --target /tmp/restore-test     # restore into a scratch directory
diff -rq /tmp/restore-test/opt/linumed-os /opt/linumed-os   # spot check
rm -rf /tmp/restore-test
```

This role doesn't automate that (no `backup-restore-test.yml`) - that's a deliberately
open item for a later version, not an oversight.

## Pitfalls

- **Not a database-consistent backup.** `/var/lib/docker/volumes` is backed up as a
  plain filesystem while PostgreSQL (BridgeLink) keeps running and writing - that's not
  the same guarantee as `pg_dump` or an atomic filesystem snapshot. A deliberate
  trade-off for v0.1: the alternative (stopping the database before every backup) would
  have real availability costs for a system running an integration engine. Anyone who
  can't accept that should add a regular `pg_dump` to `backup_paths` as well.
- **Without the restic password, everything is lost.** There is no recovery mechanism.
  Keep the password at a second, physically separate location in addition to the local
  vault (see the dev machine's own `~/.claude/CLAUDE.md`, the section on total loss at
  the site - the same logic applies to any installation built with this kit).
- **The trap makes sure a failure stays visible**, not that it disappears. If `restic
  backup`, `forget` or `check` fails, a metric is still written (`backup_success 0`) - a
  silent failure that only surfaces once a restore is needed is the real nightmare with
  backups.
- **`restic forget --prune` deletes old snapshots** per the retention policy - that's
  intentional, but lowering the values in `backup_retention_keep_*` loses the
  corresponding earlier restore points.
