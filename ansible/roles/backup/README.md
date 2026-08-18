# backup

Encrypted backups for Linumed Base with restic, a systemd timer (not cron), and Prometheus
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

`backup_paths` defaults to `/opt/linumed-base` (every role's deployed config and secrets)
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
hand-written predecessor of this script stopped a container before backing up and
started it again after, without a trap, so a failed `restic` step left the container down
for hours before anyone noticed by accident. This role's script doesn't stop any service
(see the consistency trade-off above), so the failure mode is smaller - but "a failed
backup is invisible" is the same class of bug either way, and the fix is the same pattern.

## Restore test (#36)

A backup that has never been restored is not a verified backup. `backup_restore_test_enabled`
(default `true`) deploys a second script, `linumed-base-restore-test.sh`, on its own weekly
systemd timer (`backup_restore_test_schedule`, default Sunday 04:00 - an hour after the
daily backup, so there's always something recent to restore against):

1. `restic restore latest` into a throwaway `mktemp -d` target.
2. `diff -rq` between the restored copy and the live source, for every path in
   `backup_restore_test_diff_paths` (default: `/opt/linumed-base` only, deliberately
   narrower than `backup_paths` - diffing `/var/lib/docker/volumes` against a live,
   currently-writing Prometheus/Loki/Postgres would produce spurious differences that
   have nothing to do with whether the backup actually works).
3. Writes its own textfile metrics (`{{ backup_textfile_dir }}/restore_test.prom`):
   `restore_test_last_run_timestamp_seconds`, `restore_test_success`,
   `restore_test_diff_lines`, `restore_test_last_success_timestamp_seconds` - same
   always-write-on-exit trap pattern as the backup script, so a restore test that stops
   running silently is exactly as visible as one that starts failing
   (`RestoreTestStale`/`RestoreTestFailed` in the monitoring role's alert rules).

Setting `backup_restore_test_enabled: false` removes the timer, service and script again
on the next run rather than leaving an orphaned, unmanaged timer behind.

**A `set -e`/`pipefail` trap worth naming explicitly:** `diff` exits `1` when it finds any
difference. Under this script's `set -euo pipefail`, that would kill the script at the
exact moment a real difference needs to be counted, before `diff_lines` is ever assigned
- confirmed by reproducing it directly before shipping. The fix is `|| true` on the diff
pipeline, applied to the whole pipeline (not just `diff` itself, since `pipefail` takes
the rightmost non-zero exit status across every stage). This repository's own issue #25
hit the same class of bug once already.

## What this role does not do

- Does not stop or drain any service before backing up (see consistency trade-off) - the
  restore test inherits the same non-database-consistency caveat.
- Does not configure or reach the backend itself - no S3 bucket creation, no SFTP host
  key setup, no IAM policy. Bring your own reachable, already-authenticated destination.
