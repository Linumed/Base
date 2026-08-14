# common: SSH hardening

## Problem

A freshly installed Debian allows password login over SSH by default, and depending on
the install path, sometimes root login too. For a server reachable from the internet, or
even just from the clinic LAN, that's an open door for brute-force attacks. This role
hardens SSH to key-only access with restricted root login, without hand-maintaining
every line of `/etc/ssh/sshd_config`.

## Variables

All variables are prefixed `common_ssh_*` and have sensible defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `common_ssh_port` | `22` | SSH port. The ufw role opens this port automatically (see `common-ufw.md`) - changing it only needs `common_ssh_port` set once, centrally |
| `common_ssh_permit_root_login` | `"no"` | Root login off entirely |
| `common_ssh_password_authentication` | `"no"` | Password login off, key only |
| `common_ssh_pubkey_authentication` | `"yes"` | Key login on |
| `common_ssh_kbd_interactive_authentication` | `"no"` | Interactive auth methods off |
| `common_ssh_x11_forwarding` | `"no"` | No X11 forwarding |
| `common_ssh_max_auth_tries` | `3` | Max. auth attempts per connection |
| `common_ssh_login_grace_time` | `30` | Seconds until the connection drops without successful auth |
| `common_ssh_allow_users` | `[]` | Empty = no restriction. Only set once you're sure your own user is in the list |
| `common_ssh_allow_groups` | `[]` | Same as above, group-based |
| `common_ssh_preflight_enabled` | `true` | Safety check before disabling root login (see below). Only set to `false` for deliberately root-only hosts (e.g. throwaway CI images) |

## What gets changed

- **File**: `/etc/ssh/sshd_config.d/10-linumed-hardening.conf` (newly created). The main
  file `/etc/ssh/sshd_config` is **not** touched - it's ucf-managed on Debian, and a
  full-file template would lose against ucf on every `openssh-server` upgrade.
- **Service**: `ssh.service` is reloaded on change (`systemctl reload ssh`), not
  restarted - existing connections stay open.
- **Port**: unchanged by default (22).

## Verification

Check for yourself after a playbook run, don't trust the playbook's own output:

```bash
sudo /usr/sbin/sshd -T | grep -E '^(permitrootlogin|passwordauthentication|port|maxauthtries)'
```

Expected output (with default values):

```
permitrootlogin no
passwordauthentication no
port 22
maxauthtries 3
```

Additionally: a password login must fail, a key login must succeed.

## Pitfalls

- **Drop-in order**: sshd uses the *first* value it finds for each directive. Cloud
  images often ship a `50-cloud-init.conf` - our `10-linumed-hardening.conf` only wins
  because `10` sorts before `50`. Any additional drop-ins of your own need a higher
  number, never a lower one.
- **Socket activation**: if `ssh.socket` is active (Debian offers this optionally, see
  `openssh-server`'s `README.Debian`), `sshd` ignores its own `Port` directive - the port
  then comes from the socket unit's `ListenStream=`. The role detects this and, since
  #15, templates its own drop-in (`/etc/systemd/system/ssh.socket.d/listen.conf`) instead
  of aborting - the unit ships with `ListenStream=22` hardwired, so the drop-in has to
  blank that out before setting the actual port, or `sshd` ends up listening on both
  ports at once. `ssh.service` is stopped before the socket unit restarts: with
  `Accept=no`, the service runs continuously holding the socket unit's listening fd, and
  restarting the socket unit fails while the service is still active ("Socket service
  ssh.service already active, refusing."). If `common_ssh_port` is set back to `22`, the
  role removes the drop-in again on the next run.
- **Root login lockout without a safety net**: the role aborts on its own if no
  non-root user with sudo rights and a deployed SSH key exists - that's intentional, not
  a bug. So create an admin user with a key before the first run - on a fresh minimal
  install, `scripts/bootstrap.sh` takes care of that.
