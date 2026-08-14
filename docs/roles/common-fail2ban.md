# common: fail2ban

## Problem

Even with key-only SSH (see `common-ssh.md`), a server reachable from the internet sees
a constant stream of automated login attempts in the logs. That's harmless as long as
password auth is off, but it creates log noise and unnecessary CPU load from the auth
attempts themselves. fail2ban temporarily bans IPs entirely, via a firewall rule, after
repeated failed attempts.

## Variables

All variables are prefixed `common_fail2ban_*` and have sensible defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `common_fail2ban_enabled` | `true` | Installs and enables fail2ban. With `false`, the service is stopped/disabled (if present), not uninstalled |
| `common_fail2ban_backend` | `"systemd"` | Reads the journal log directly, no dependency on `/var/log/auth.log`/rsyslog |
| `common_fail2ban_maxretry` | `5` | Failed attempts before a ban |
| `common_fail2ban_findtime` | `"10m"` | Time window in which `maxretry` must be reached |
| `common_fail2ban_bantime` | `"1h"` | Ban duration |
| `common_fail2ban_ignoreip` | `["127.0.0.1/8", "::1"]` | Addresses never banned. Add your own management IP/Tailscale range, or too many failed attempts can lock you out yourself |

## What gets changed

- The `fail2ban` package is installed.
- `/etc/fail2ban/jail.d/10-linumed-sshd.conf` (newly created drop-in). `jail.local`/
  `jail.conf` are **not** touched - fail2ban itself documents `jail.d/` as the place for
  local overrides, and `jail.conf` gets overwritten on package upgrades anyway.
- The `fail2ban` service is restarted on change (not reloaded - see
  `handlers/main.yml`), enabled and started.

## Verification

```bash
sudo fail2ban-client status sshd
```

Expected output includes `Currently banned` and `Total banned` (0 right after rollout is
normal) and the port number taken from `common_ssh_port` under `Filter`/`Actions`.

```bash
sudo fail2ban-client status
```

shows whether the `sshd` jail is active at all.

## Pitfalls

- **Extend `common_fail2ban_ignoreip` before the first real test**: testing from an IP
  that deliberately triggers failed attempts (e.g. a password-login test against
  `common_ssh_password_authentication`) can lock you out yourself. Add your own
  Tailscale/management range first.
- **Interaction with ufw**: fail2ban's default action (`iptables-multiport`) sets its own
  `iptables` rules, independent of the ufw rules from `common-ufw.md`. Both coexist in
  different chains - so `ufw status` shows **none** of fail2ban's bans; use
  `fail2ban-client status sshd` for that.
- **`systemd` backend**: assumes sshd is reachable through the journal log (the Debian
  default). If `rsyslog` was removed or journald reconfigured, this doesn't work - in
  that case, set `common_fail2ban_backend` explicitly to `"auto"`.
