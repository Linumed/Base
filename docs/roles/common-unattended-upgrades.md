# common: unattended-upgrades

## Problem

Security vulnerabilities in packages that don't get patched promptly are a direct risk
on a server running medical integration software. A human running `apt upgrade` by hand
every night doesn't scale - this role automates installing security updates through the
standard `unattended-upgrades` mechanism.

## Variables

All variables are prefixed `common_unattended_upgrades_*` and have sensible defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `common_unattended_upgrades_enabled` | `true` | Installs and configures `unattended-upgrades` |
| `common_unattended_upgrades_origins` | `["${distro_id}:${distro_codename}-security"]` | Security updates only. Add `-updates` for full unattended updates - that then also pulls in non-security changes automatically |
| `common_unattended_upgrades_automatic_reboot` | `false` | **Deliberately off.** An unannounced reboot on a machine running Mirth/PACS is riskier than a kernel update waiting |
| `common_unattended_upgrades_automatic_reboot_time` | `"02:00"` | Only relevant if the reboot setting above is `true` |
| `common_unattended_upgrades_remove_unused_deps` | `true` | Cleans up orphaned dependencies after updates |
| `common_unattended_upgrades_mail` | `""` (off) | Empty = no mail report, since a fresh host isn't assumed to have an MTA |

## What gets changed

- The `unattended-upgrades` package is installed.
- `/etc/apt/apt.conf.d/20auto-upgrades` (newly created): enables the daily package list
  refresh and the unattended-upgrade run.
- `/etc/apt/apt.conf.d/51-linumed-unattended-upgrades` (newly created, its own file
  instead of editing `50unattended-upgrades`): origins pattern, reboot behavior,
  dependency cleanup, optional mail report.
- Triggering runs through the standard `apt-daily-upgrade.timer` (systemd); no separate
  cron job or timer is created.

## Verification

```bash
sudo unattended-upgrade --dry-run --debug
```

Shows which packages would be updated on the next run, without changing anything.

```bash
systemctl status apt-daily-upgrade.timer
sudo apt-config dump | grep -A3 Unattended-Upgrade::Origins-Pattern
```

First command: the timer must be `active`/`waiting`. Second: shows the actually merged
origins - don't just check the role's own drop-in file, `apt.conf.d` merges every file
in the directory.

## Pitfalls

- **`apt.conf.d` files are merged, not selected on first match** - unlike the
  `sshd_config.d` drop-ins in `common-ssh.md`. An extra, conflicting drop-in placed in
  `/etc/apt/apt.conf.d/` therefore silently overrides values from
  `51-linumed-unattended-upgrades`, depending on alphabetical order.
- **Automatic reboot is deliberately off.** Anyone enabling it should set
  `common_unattended_upgrades_automatic_reboot_time` to a maintenance window where
  running integrations (Mirth message processing) won't be harmed.
- **The `-updates` origin pulls in more than security fixes.** Only add it if you
  deliberately want to automate more than security updates - that raises the risk of an
  unexpected behavior change from a regular package update.
