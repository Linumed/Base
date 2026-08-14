# common: NTP and timezone

## Problem

Inconsistent timezones and drifting system clocks make log correlation across multiple
hosts (e.g. when debugging an HL7 message that travels through several systems)
unnecessarily painful, and some protocols and certificate checks are sensitive to larger
clock offsets. This role sets timezone and NTP synchronization consistently.

## Variables

All variables have sensible defaults in `ansible/roles/common/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `common_timezone` | `"Etc/UTC"` | System timezone. Deliberately UTC rather than a local timezone - unambiguous log timestamps across multiple hosts matter more than a server's local wall-clock time. Override per inventory if staff need to read logs directly on the host in local time |
| `common_ntp_enabled` | `true` | Enables NTP configuration and `systemd-timesyncd` |
| `common_ntp_servers` | `[]` | Empty = Debian's compiled-in default pool. Set your own NTP server for environments with restricted internet access |
| `common_ntp_fallback_servers` | `[]` | Fallback servers if the primary ones are unreachable |

## What gets changed

- Timezone via `community.general.timezone` (sets `/etc/timezone` and the
  `/etc/localtime` symlink).
- `/etc/systemd/timesyncd.conf.d/10-linumed.conf` (newly created drop-in - the main file
  `timesyncd.conf` is left untouched, for the same reason as the other drop-ins in this
  role: it survives package upgrades cleanly).
- `systemd-timesyncd` is enabled and started. No extra package needed - Debian ships and
  enables it by default.

## Verification

```bash
timedatectl status
```

Expected output: `Time zone` matches `common_timezone`, `System clock synchronized:
yes`, `NTP service: active`.

```bash
sudo cat /etc/systemd/timesyncd.conf.d/10-linumed.conf
```

Shows the actually active NTP servers, if `common_ntp_servers` was set.

## Pitfalls

- **chrony instead of systemd-timesyncd**: if `chrony` is installed on a host (e.g. from
  some other setup step), it competes with `systemd-timesyncd` for the same NTP port.
  This role assumes the Debian default (`systemd-timesyncd`) and does not install
  `chrony` - on a chrony host, decide up front which service should be authoritative.
- **UTC default and log tools**: reading logs with a tool that doesn't convert
  timezones shows UTC timestamps, not local time. That's intentional, but worth
  checking here first the moment "wrong" timestamps in logs cause confusion, before
  assuming an actual clock drift.
