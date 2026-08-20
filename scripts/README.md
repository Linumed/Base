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

## render-diagrams.sh

Renders every `docs/diagrams/*.mmd` to `docs/img/*.svg` with a pinned `mermaid-cli`.
Run it after editing a diagram and commit both the source and the SVG; CI re-renders and
fails if they disagree (`docs-site.yml`).

```bash
./scripts/render-diagrams.sh
```

**Why the diagrams are pre-rendered rather than drawn in the browser** (issue #65): they
appear on three surfaces - the MkDocs site, GitHub and Forgejo - each with its own Mermaid
theme, so styling only ever reached one of the three. A committed SVG looks the same
everywhere and needs no JavaScript, which also removed the vendored `mermaid.min.js` and
the class-name workaround that existed purely to stop Material from fetching its renderer
off a CDN at runtime.

Two things to know before editing a `.mmd`:

- **A line containing only `%%` is a parse error**, and the message points at line 1
  regardless of where the offending line actually is. Comment lines need at least one
  character after the marker; these sources use `%% -` as a blank separator.
- **Do not draw edges to or from a `subgraph`.** That is what made the previous diagram
  unreadable: an arrow from a group to a node inside itself renders as a floating label
  with no arrow at all. Keep containment and flow in separate figures.

Needs Node (for `npx`) and downloads a Chromium once into `PUPPETEER_CACHE_DIR`
(`/var/tmp/puppeteer` by default - deliberately not `/tmp`, which is a tmpfs on the
development machine).

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

## test/vm-test-netinst.sh

Not in this directory (lives under `test/`) but exercises `bootstrap.sh` end-to-end
against a real Debian 13 netinst install with a deliberately minimal preseed (no
`python3`, no `sudo` - see that script's own comments for why that matters). Run before
releases, not in regular CI (issue #14) - a full netinst is much slower than the
genericcloud image `test/vm-test.sh` uses.
