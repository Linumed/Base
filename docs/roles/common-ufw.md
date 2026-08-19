# common: ufw firewall

## Problem

A freshly installed Debian has no active firewall - any service that later opens a port
(Docker containers included - see the `docker` role, "Docker bypasses ufw") is
immediately visible across the whole reachable network. This role sets up `ufw` with
default-deny for incoming traffic and opens only the ports actually needed.

## Variables

All variables are prefixed `common_ufw_*` and have sensible defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `common_ufw_enabled` | `true` | Enables ufw at the end of the role run |
| `common_ufw_default_incoming` | `"deny"` | Default policy for incoming traffic |
| `common_ufw_default_outgoing` | `"allow"` | Default policy for outgoing traffic |
| `common_ufw_allow_ssh` | `true` | Opens `common_ssh_port`/tcp automatically. Only set to `false` if SSH access is secured through some other mechanism |
| `common_ufw_extra_rules` | `[]` | List of further rules, e.g. `- {port: 443, proto: tcp, comment: "HTTPS"}` |

## What gets changed

- The `ufw` package is installed.
- Default policies (`ufw default deny incoming` / `allow outgoing`).
- Allow rule for `common_ssh_port`/tcp, then one for each entry in
  `common_ufw_extra_rules`.
- `ufw enable` runs as the last step - only once the SSH rule is in place.

## Prerequisite: collection

Uses `community.general.ufw`, not `ansible.builtin`. Before the first run:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## Verification

```bash
sudo ufw status verbose
```

Expected output (with default values): status `active`, `Default: deny (incoming), allow
(outgoing)`, a rule for port 22/tcp (or the configured `common_ssh_port`).

Also check from a second machine: a connection to a port that isn't opened must hang or
time out, not return "connection refused" (that would mean a closed but unfiltered
port - a sign that ufw isn't actually sitting in front of the service as expected).

## Pitfalls

- **Order**: only enable ufw after the SSH rule is in place - otherwise the
  default-deny cuts the running Ansible connection. The role preserves this order
  (`tasks/ufw.yml`); a hand-rolled playbook has to enforce it itself.
- **Docker bypasses ufw**: a container port published via `ports:` is reachable on the
  LAN despite active ufw rules (Docker's own `iptables` rules sit ahead of ufw's rules
  in the chain). This role doesn't change that - container ports belong bound to
  `127.0.0.1`, with public access going through a reverse proxy or Tailscale.
- **Changing the SSH port**: if `common_ssh_port` changes, this role automatically opens
  the new port along with it - still apply both roles (SSH and ufw) in the same run,
  never change the port manually in `sshd_config` and run ufw separately or later.
