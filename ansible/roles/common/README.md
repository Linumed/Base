# common

Base hardening role for Linumed Base. Runs first, before any other role.

Implements SSH hardening (issue #1), ufw (#3), fail2ban (#10), unattended-upgrades (#5),
and NTP/timezone (#11) - the full planned scope of the common role.

Requires the `community.general` collection (for the `ufw` module) - see
`ansible/requirements.yml`, install with
`ansible-galaxy collection install -r requirements.yml`.

## SSH hardening

Deploys `/etc/ssh/sshd_config.d/10-linumed-hardening.conf` as a drop-in — the main
`/etc/ssh/sshd_config` is never templated, because it is ucf-managed on Debian and a
full-file template would fight ucf on every `openssh-server` upgrade.

See `docs/roles/common-ssh.md` for the user-facing writeup: variables, files touched,
verification command, and known pitfalls (drop-in ordering, socket activation, port
changes without a matching ufw rule).

### Variables

See `defaults/main.yml`. All variables are prefixed `common_ssh_*`.

### Safety checks

- **Pre-flight**: if `common_ssh_permit_root_login` is `"no"`, the role refuses to run
  unless it finds a non-root, sudo-capable user with a populated
  `~/.ssh/authorized_keys`. Disable via `common_ssh_preflight_enabled: false` only for
  deliberately root-only hosts (e.g. throwaway CI images).
- **Socket guard**: if `ssh.socket` is enabled/active, socket activation ignores the
  `Port` directive in `sshd_config` - the role templates its own
  `/etc/systemd/system/ssh.socket.d/listen.conf` override (blanking the unit's baked-in
  `ListenStream=22` before setting `common_ssh_port`) and reloads the socket unit, rather
  than aborting (#15). `ssh.service` is stopped first: with `Accept=no` it's started
  eagerly alongside the socket and holds the listening fd, so restarting `ssh.socket`
  while it's still running fails with "Socket service ssh.service already active,
  refusing." (confirmed in an isolated test container). Setting `common_ssh_port` back to
  `22` removes the override again on the next run.
- **Validation**: `sshd -t` is run after deploying the drop-in; on failure the previous
  drop-in (or no file, if none existed) is restored and the play fails before reloading
  `ssh.service`.

### Ciphers, MACs, KexAlgorithms

Deliberately left untouched. Debian 13 ships OpenSSH 10.0p1, which already disables weak
KEX/DSA by default upstream; a role-maintained allowlist would only go stale.

### Tunnel-only users (issue #41)

`common_ssh_tunnel_users` creates shell-less accounts (`/usr/sbin/nologin`, no password)
that can open exactly the loopback port-forwards listed in `targets` - nothing else.
Enforced by sshd itself via a per-user `Match` block (`PermitOpen`, `ForceCommand
nologin`, `PermitTTY no`), not by a wrapper script or a second component. Deployed as
`/etc/ssh/sshd_config.d/90-linumed-tunnel-users.conf` - the highest-numbered drop-in this
role ships, deliberately: a `Match` block scopes everything parsed after it (Include
splices `sshd_config.d/*.conf` in alphabetically, inline) until the next `Match` line or
the end of the whole chain, so this file has to sort after every other drop-in, including
a cloud image's own `50-cloud-init.conf`, or those directives would be silently scoped to
only the matched user. Validated with `sshd -t` and rolled back on failure, same pattern
as the main hardening drop-in. An empty list removes the drop-in again.

## ufw firewall

Default-deny incoming, default-allow outgoing. `common_ssh_port` is opened automatically
so the role can never lock itself out over the connection Ansible is running on; further
ports go through `common_ufw_extra_rules`. See `defaults/main.yml` for both.

Rule ordering in `tasks/ufw.yml` matters: policies are set, then the SSH allow rule, then
any extra rules, and `ufw enable` runs last - enabling first would apply the deny-incoming
default before any allow rule exists.

## fail2ban

Bans IPs on repeated SSH auth failures. Config is a drop-in under `jail.d/`
(`10-linumed-sshd.conf`), not a template of `jail.local` - fail2ban's own docs point at
`jail.d/` as the place for local overrides, and `jail.conf` gets overwritten on package
upgrades either way. Backend is `systemd` (reads the journal directly) rather than
`/var/log/auth.log`, so this doesn't pick up a dependency on rsyslog being installed.

Works alongside ufw: fail2ban's default `iptables-multiport` action and ufw's rules live
in separate netfilter chains and don't conflict.

## unattended-upgrades

Security-origin package updates applied automatically via the standard
`apt-daily-upgrade.timer`. Config lives in a separate `51-linumed-unattended-upgrades`
drop-in rather than editing the package-provided `50unattended-upgrades` - `apt.conf.d`
files are all merged regardless of filename (unlike sshd's first-wins drop-ins), so this
sidesteps dpkg conffile prompts on package upgrades.

`common_unattended_upgrades_automatic_reboot` defaults to `false` - an unannounced reboot
on infrastructure that may run patient-adjacent services (Mirth, PACS) is worse than a
pending kernel update sitting until the next planned maintenance window. Enable it
deliberately per-host, not as a blanket default.

## NTP and timezone

Timezone via `community.general.timezone` (defaults to `Etc/UTC` - unambiguous log
timestamps and cross-host correlation matter more than local wall-clock time on a server).
NTP via `systemd-timesyncd`, which Debian ships active by default - no extra package. A
drop-in under `timesyncd.conf.d/` for the same reason as the other drop-ins in this role:
survives package upgrades cleanly.

### `become: true` on every privileged task, no exceptions

Every task that touches root-owned state (reading `ssh.socket`'s unit state, deploying
the drop-in, validating, reloading) sets `become: true` individually - `CLAUDE.md` bans
play-level `become`. This was violated once during development on the "Socket guard" read
task and the "Reload ssh" handler: `ansible.builtin.systemd_service` silently ran as the
unprivileged connecting user, systemd routed the call through PolicyKit, and `pkttyagent`
hung waiting for interactive authorization that never arrives over SSH - failing with
`Failed to reload ssh.service: Connection timed out` on every single run, not
intermittently. If you see that exact error, check for a missing `become: true` before
suspecting D-Bus, timing, or hardware first.
