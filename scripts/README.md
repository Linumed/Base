# scripts/

## bootstrap.sh

Establishes what every Ansible role in this repo assumes: `python3`, `sudo`, and a
sudo-capable user with an SSH key. Debian 13's minimal/netinst install has none of these
by default (issue #13).

**When you need it:** a freshly netinst-installed Debian 13 host, or any host where
you're not sure `python3`/`sudo` are present. Log in as root (console or SSH) and run:

```bash
./bootstrap.sh --user <username> --key "ssh-ed25519 AAAA... you@host"
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

## scan-images.py

Scans every image pinned in a role's `defaults/main.yml` for known vulnerabilities, and
checks that the `docker/` references pin the same versions.

```bash
./scripts/scan-images.py            # exits non-zero on an actionable finding
./scripts/scan-images.py --report   # same output, always exits 0
```

Uses `trivy` from PATH if present, otherwise runs it in a container. CI uses the binary,
because the runner deliberately has no broad Docker socket access.

**Why it is not a plain `trivy && exit $?`** (issue #67): a finding is only actionable if a
newer tag would clear it, and that is not the same as the pin being behind. Measured on
2026-08-20: bumping Grafana 13.1.3 to 13.1.4 cleared 5 of 18 findings, while bumping
Postgres 17.10 to 17.11 cleared none. So the script scans the candidate before demanding
the bump, and distinguishes three cases:

- **behind, and the bump measurably helps** - failure, fix it
- **already newest, findings remain** - must be recorded in
  `security/accepted-image-findings.txt` with a reason and a date; unrecorded ones fail
- **newer series available** (13.1 -> 13.2, v0.33 -> v0.34) - reported, never enforced.
  That is a decision, not a security patch.

The alternative, failing on any finding at all, would leave the check permanently red -
and a check that always says the same thing stops being read. This repository has hit that
failure mode three times (#40, #48, #63).

The scanner version is pinned in both the script and the workflow, and the script checks
that the two agree. Different trivy versions produce different finding sets - 0.58.2 and
0.74.0 disagreed on Prometheus and on the total - so a drift between the pins would make a
local run and a CI run disagree about whether the accepted list is complete, and that
disagreement would look like a real finding.

**When bumping the scanner, verify the download URL rather than assuming it.** The first
version of the workflow pinned 0.58.2: a real trivy version whose container image pulls
normally, but whose GitHub release carries no asset under the expected name. CI found it
with a bare `curl: (22) ... 404`. Bumping the scanner also means regenerating the
accepted-findings list, because the finding set moves with it.

Entries in the accepted-findings file older than 90 days are reported, not failed:
re-check them rather than refreshing the date, because an ageing entry usually means an
upstream has stopped rebuilding.

## check-numeric-claims.py

Checks that a small, deliberately curated list of numeric claims in prose - "120
interface role variables", "11 container names" - still match what the repository
currently measures (issue #88).

```bash
./scripts/check-numeric-claims.py            # exits non-zero on a mismatch
./scripts/check-numeric-claims.py --report   # same output, always exits 0
```

**A register, not a scan** - the same shape as `ansible/internal-variables.txt` and
`security/accepted-image-findings.txt`. It does not go looking for every number in the
docs; it re-verifies exactly the ones listed in `NUMERIC_CLAIMS` inside the script.
Reasoning behind that restraint, and what is deliberately left out (a dated measurement
like "Measured on 2026-08-20: all eleven pinned images..." should stay exactly as
written, not be flagged as stale), is in the script's own docstring.

Reuses `check-variable-docs.py`'s own counting functions rather than re-deriving the same
numbers a second way, so the two checks cannot quietly disagree about what "interface
variable" means.

## select-roles.sh

Interactive role selection for `linumed_base_roles` (issue #86), so picking a subset of
the six roles doesn't mean hand-editing YAML.

```bash
./scripts/select-roles.sh --file inventory/myhospital/group_vars/linumed/vars.yml
```

`whiptail` - the same toolkit Debian's own installer uses. Runs on the control node
before any playbook does; opens nothing on the network (see ADR 0003, which this does not
conflict with for exactly that reason). Shows the resulting YAML before writing it - the
tool's whole job is picking roles, not hiding what it did.

**Scope, deliberately narrow:** writes `linumed_base_roles` and nothing else. It does not
touch `hosts.yml`, any other setting in `vars.yml`, or `vault.yml` - the rest of onboarding
stays the README's job.

None of the four optional roles depends on another being selected, so this is a single
flat checklist - there used to be a gated second step for `orthanc`, removed along with
the role itself in #92/ADR 0011 (see `docs/operations/orthanc-recommendation.md`).

Re-running it replaces the previous selection in place (between two `# BEGIN
linumed_base_roles` / `# END` markers) rather than piling up duplicate blocks - safe to
run again after changing your mind.

```bash
./scripts/select-roles.sh --file inventory/myhospital/group_vars/linumed/vars.yml \
  --non-interactive "caddy monitoring backup"
```

`--non-interactive` skips the dialogs - what `test/select-roles-check.sh` uses (`whiptail`
can't be driven headlessly), and usable by anyone scripting onboarding without a TTY.
`common` and `docker` are always included and never listed here.

## test/vm-test-netinst.sh

Not in this directory (lives under `test/`) but exercises `bootstrap.sh` end-to-end
against a real Debian 13 netinst install with a deliberately minimal preseed (no
`python3`, no `sudo` - see that script's own comments for why that matters). Run before
releases, not in regular CI (issue #14) - a full netinst is much slower than the
genericcloud image `test/vm-test.sh` uses.
