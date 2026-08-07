# common

Base hardening role for Linumed OS. Runs first, before any other role.

Currently implements SSH hardening only (issue #1). ufw (#3), fail2ban (#10),
unattended-upgrades (#5), and NTP/timezone (#11) will be added as separate task files
imported from `tasks/main.yml`.

## SSH hardening

Deploys `/etc/ssh/sshd_config.d/10-linumed-hardening.conf` as a drop-in — the main
`/etc/ssh/sshd_config` is never templated, because it is ucf-managed on Debian and a
full-file template would fight ucf on every `openssh-server` upgrade.

See `docs/roles/common-ssh.md` (German) for the user-facing writeup: variables, files
touched, verification command, and known pitfalls (drop-in ordering, socket activation,
port changes without a matching ufw rule).

### Variables

See `defaults/main.yml`. All variables are prefixed `common_ssh_*`.

### Safety checks

- **Pre-flight**: if `common_ssh_permit_root_login` is `"no"`, the role refuses to run
  unless it finds a non-root, sudo-capable user with a populated
  `~/.ssh/authorized_keys`. Disable via `common_ssh_preflight_enabled: false` only for
  deliberately root-only hosts (e.g. throwaway CI images).
- **Socket guard**: aborts if `ssh.socket` is enabled/active and `common_ssh_port` is not
  `22` — socket activation ignores the `Port` directive in `sshd_config`.
- **Validation**: `sshd -t` is run after deploying the drop-in; on failure the previous
  drop-in (or no file, if none existed) is restored and the play fails before reloading
  `ssh.service`.

### Ciphers, MACs, KexAlgorithms

Deliberately left untouched. Debian 13 ships OpenSSH 10.0p1, which already disables weak
KEX/DSA by default upstream; a role-maintained allowlist would only go stale.

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
