# backup

Encrypted backups for Linumed OS with restic, a systemd timer (not cron), and Prometheus
textfile-collector metrics (issue #7).

## Variables

See `defaults/main.yml`, all prefixed `backup_*`. `backup_repository` and
`backup_restic_password` have no default and the role's preflight refuses to run without
both set - same pattern as the SSH, Grafana, and BridgeLink preflights.

## Backend

`backup_repository` is passed straight through as restic's `RESTIC_REPOSITORY` - any
backend restic supports works (`local:`, `sftp:`, `s3:`, ...). This role does not
special-case any backend; picking and reaching one (network access, credentials for
`s3:`, an SSH key already in place for `sftp:`) is the operator's job.

## What gets backed up

`backup_paths` defaults to `/opt/linumed-os` (every role's deployed config and secrets)
and `/var/lib/docker/volumes` (every named Docker volume's data - Prometheus, Loki,
Grafana, BridgeLink's appdata and its Postgres data, whatever else is running). Direct
filesystem access, not `docker-volume-backup` or a database-native dump tool.

**This is not database-consistent.** Backing up Postgres's data directory while it's
running and writing is not the same guarantee as `pg_dump` or a filesystem snapshot taken
atomically. Accepted for v0.1 as a documented trade-off, not an oversight - see
`docs/roles/backup.md` for the reasoning and what upgrading this would take.

## Metrics, not a push

The backup script writes `{{ backup_textfile_dir }}/backup.prom` (default:
`/var/lib/prometheus/node-exporter/backup.prom`, the same directory the monitoring role's
native Node Exporter already scans) with:

- `backup_last_run_timestamp_seconds` - written on every attempt, success or failure
- `backup_success` - `1` or `0`
- `backup_last_success_timestamp_seconds` - only written on success

This role has no hard dependency on the monitoring role - it creates the directory itself
if monitoring isn't installed, the metrics just go unscraped in that case. If monitoring
*is* installed, its `BackupStale` alert rule (dormant since it was written - the metric
didn't exist yet) starts firing for real as soon as this role's first run lands.

## Why a trap, not a plain script

The backup script always writes its metrics via a `trap ... EXIT`, regardless of how the
script exits. This is not a stylistic choice - it's the direct lesson from Issue #18: the
hand-written backup script on `linumed-dev` itself stopped Forgejo before backing up and
started it again after, without a trap, so a failed `restic` step left the container down
for hours before anyone noticed by accident. This role's script doesn't stop any service
(see the consistency trade-off above), so the failure mode is smaller - but "a failed
backup is invisible" is the same class of bug either way, and the fix is the same pattern.

## What this role does not do

- Does not stop or drain any service before backing up (see consistency trade-off).
- Does not configure or reach the backend itself - no S3 bucket creation, no SFTP host
  key setup, no IAM policy. Bring your own reachable, already-authenticated destination.
- Does not automate a restore test. The manual procedure is documented in
  `docs/roles/backup.md`; running it periodically is an operational practice, not
  something this role can enforce.
