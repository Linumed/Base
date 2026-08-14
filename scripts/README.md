# scripts/

## bootstrap.sh

Establishes what every Ansible role in this repo assumes: `python3`, `sudo`, and a
sudo-capable user with an SSH key. Debian 13's minimal/netinst install has none of these
by default (issue #13).

**When you need it:** a freshly netinst-installed Debian 13 host, or any host where
you're not sure `python3`/`sudo` are present. Log in as root (console or SSH) and run:

```bash
./bootstrap.sh --user linumed --key "ssh-ed25519 AAAA... you@host"
```

**When you don't need it:** the official Debian 13 genericcloud/cloud images (used by
`test/vm-test.sh`) already have all of this via cloud-init. So does any host you've
already logged into with a working sudo user.

**What it deliberately does not do:** hardening, ufw, fail2ban, sshd configuration -
that's the `common` role's job, once Ansible can reach the host at all.

See the script's own header comment for the full argument list and the
`--nopasswd`/`--ask-become-pass` trade-off.

**Known boundary case, unsolved on purpose:** `openssh-server` is `Priority: optional` on
Debian 13 just like `python3` and `sudo` (issue #13), so a minimal/netinst install can
lack it too. `bootstrap.sh` installs it as part of its own run, but that only helps if
something can already reach the host to *run* the script - either a console (physical,
IPMI/iDRAC, or the hypervisor's virtual console) or a working SSH daemon. If a host has
neither - no console access and no SSH - there is no remote fix; this repo does not
attempt one. Get console access first, or include `openssh-server` in the Debian
installer's own package selection (`pkgsel/include` in a preseed, or the installer's task
selection) so the host is reachable before `bootstrap.sh` ever needs to run.

## test/vm-test-netinst.sh

Not in this directory (lives under `test/`) but exercises `bootstrap.sh` end-to-end
against a real Debian 13 netinst install with a deliberately minimal preseed (no
`python3`, no `sudo` - see that script's own comments for why that matters). Run before
releases, not in regular CI (issue #14) - a full netinst is much slower than the
genericcloud image `test/vm-test.sh` uses.
