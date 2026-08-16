# Roadmap

Planned work in the order it should happen, and why that order. Each item links to its
issue; the issue holds the detail, this page holds the sequencing and the reasoning behind
it.

Written 2026-08-14, after an audit of the repository against its own stated requirements
(`CLAUDE.md`, `ARCHITECTURE.md`).

## Where this actually stands

All six v0.1 roles are implemented, VM-tested and idempotent: `common`, `docker`, `caddy`,
`monitoring`, `bridgelink`, `backup`. There are no open bugs.

There is, however, a gap between that and being operable by someone who is not the author.
The audit found it by measurement rather than assumption:

- The example inventory defines two variables. `site.yml` aborts without seven. Anyone
  following the documented quick start hits a preflight abort ([#27](../../issues/27)).
- `ansible-vault` appears nowhere in the repository, although `CLAUDE.md` mandates it and
  the role READMEs point at it ([#28](../../issues/28)).
- No git tag exists, although `ARCHITECTURE.md` requires releases to be tagged
  ([#29](../../issues/29)).

So the honest description was: **the roles work, the product does not yet onboard anyone.**
That is what Stage 1 fixed, and it is why SSO was not next despite `ARCHITECTURE.md` naming
it as v0.2.

## Stage 1 - Operability, ending in the v0.1.0 tag (done, 2026-08-14)

Nothing here was a new feature. This stage made the claim already published in the README
("feature-complete and verified") true from an operator's point of view.

| | Issue |
|---|---|
| Complete the example inventory, fix the quick start | [#27](../../issues/27) closed |
| Document the Ansible Vault workflow, add an example vault | [#28](../../issues/28) closed |
| Tag `v0.1.0` | [#29](../../issues/29) closed, tagged |

**The acceptance run found two more bugs than the audit had - both from actually
following the README, not from reading it.** `.gitignore` had kept the entire example
inventory untracked since the initial commit (a directory negation that didn't reach the
files inside it - every clone of this repository got an empty `ansible/inventory/`, not
an incomplete one). And the quick start's own commands ran from the repo root, where
`ansible.cfg` (which sets `roles_path`) is never picked up - the very first task failed
with "the role 'common' was not found". Neither had ever surfaced before because every
automated test in this repo already `cd`s into `ansible/` first; only the copy-pasteable
instructions didn't. Both fixed, and the acceptance run repeated afterward: a full
`site.yml` double-run against a fresh VM, following the README's own procedure verbatim -
run 1 `ok=102 changed=62 failed=0`, run 2 `ok=88 changed=0 failed=0`.

## Stage 2 - Documentation foundation (done, 2026-08-14)

`CLAUDE.md` had required MkDocs from the beginning; there was no `mkdocs.yml`. The
documentation sources existed and were good, but nothing built or navigated them.

| | Issue |
|---|---|
| MkDocs setup and operations handbook | [#26](../../issues/26) closed |
| Translate the existing German docs per ADR 0002 | [#30](../../issues/30) closed |

The language question was settled first, deliberately: writing the operations handbook in
German and then internationalising would have meant writing it twice. See
[ADR 0002](adr/0002-english-as-documentation-language.md).

`mkdocs.yml` (Material theme) now navigates `ARCHITECTURE.md` (included via a symlink at
`docs/architecture.md`, so it stays a single source of truth rendered by GitHub at the
repo root), every role page, all four ADRs, and a new `docs/operations/` section - the
actual gap the audit found: deployment order, an access reference covering every
service in one place, an update workflow split by mechanism (host patches vs. pinned
image versions vs. Ansible collections), a backup/restore walkthrough covering what a
restore touches across roles, and a symptom-first troubleshooting index. Verified with
`mkdocs build`: 24 pages, clean. All ten `docs/roles/*.md` pages, `ARCHITECTURE.md` and
`docs/adr/README.md` are now English; ADR 0001 stays German on purpose (see ADR 0002).

Not done as part of this stage, deliberately: no CI workflow builds or deploys the site
yet. The scaffold exists and builds; where or whether it gets hosted is a separate
decision.

## Stage 3 - Access model: decided, now closed

The access question that hung over this stage is settled. Every management interface stays
bound to `127.0.0.1` and is reached through an SSH tunnel; no identity provider is bundled;
no mesh-VPN role is added. `linumed-net`, the Caddy route to BridgeLink and the Authentik
role are dropped, and issues #31, #32 and #34 are closed. The reasoning, the rejected
alternatives and the accepted downsides are in
[ADR 0003](adr/0003-loopback-only-access-no-bundled-identity-provider.md).

The decisive criterion was not security in the abstract but **out-of-the-box operability**:
a component that only becomes useful once the institution supplies a coordination server or
a directory is not a feature, it is a documented gap. That criterion was in no document
before this decision and now is.

What survives from this stage is smaller and unrelated to exposing anything:

| | Issue |
|---|---|
| Caddy cannot reach the operator's own containers - no working path documented | [#39](../../issues/39), closed 2026-08-16 |

**[#39](../../issues/39) is resolved (closed 2026-08-16).** Caddy joins a second Docker
network, created unconditionally by the role (`caddy_external_network_name`, default
`linumed-os-external`, fixed literal name rather than Compose's project-derived one). The
operator's own, entirely separate Compose stack joins that same network as `external: true`
and `caddy_sites` then reaches it by service name - no published port, no ufw change. Full
worked example in `docs/roles/caddy.md`. Verified against a real VM: a genuinely separate
operator stack, network membership confirmed, direct container-to-container reachability
confirmed, and (after the fix below) Caddy's own `reverse_proxy` actually serving the
request.

Verifying #39 surfaced an unrelated, pre-existing bug: **the Caddyfile bind mount was a
single file, which silently stopped picking up changes after the first deploy (issue #44,
closed 2026-08-16).** A single-file Docker bind mount attaches to the file's inode at
container start; Ansible's `template` module rewrites atomically (temp file + rename),
which orphans that mount - the container kept serving the *original* Caddyfile forever,
with `caddy reload` reporting success and the healthcheck staying green throughout. Fixed
by mounting the containing directory (`conf/`) instead, which follows the directory entry
rather than a fixed inode. This affected every production deployment that ever changed
`caddy_sites` after the first run, not just the #39 verification VM.

**CI now runs VM provisioning and idempotency checks, not just lint (#33, closed
2026-08-16).** `.forgejo/workflows/vm-test.yml`, `workflow_dispatch`-triggered per
[ADR 0004](adr/0004-vm-tests-in-ci-via-host-libvirt-socket.md) - the job container mounts
the host's libvirt socket rather than running its own nested libvirtd. One thing the ADR
hadn't accounted for surfaced while building this: the VM work directory has to be a bind
mount at an identical path on both sides, because `virt-install` running in the container
hands the *host's* libvirtd file paths it opens literally. A second real bug found on the
first live run: `node:24-bookworm`'s own `osinfo-db` package predates both "debian12" and
"debian13" as entries (Bookworm didn't exist yet when it was frozen), so `virt-install`
failed with "Unknown OS name 'debian12'" until the workflow re-imports a current
`osinfo-db` first. [#43](../../issues/43)'s pull-through cache resolved cleanly in the
same run - the workflow's own log shows it served every Docker Hub image in the stack.
Verified against two real triggered runs, not just a syntax check: the first caught the
`osinfo-db` bug, the second completed a full double-run with `changed=0` on the second
pass and a healthy Prometheus target check, end to end inside the actual CI pipeline.

**Node_exporter's ufw-blocked scrape was confirmed and fixed on 2026-08-14 (#40, closed).**
It mattered beyond the individual bug: `test/vm-test.sh` verified that the playbook ran,
not that Prometheus could reach its targets, so the bug survived every green run until
someone asked the question directly. `test/lib/site-idempotency.sh` now checks target
health after every run for exactly that reason.

## Stage 4 - v0.2: access hardening and the operational gaps

With SSO gone, v0.2 gets the content the audit actually surfaced.

| | Issue |
|---|---|
| Tunnel-only SSH users, no shell | [#41](../../issues/41), closed 2026-08-16 |
| Real Grafana users plus optional OIDC connection | [#42](../../issues/42) |

**[#41](../../issues/41) is resolved (closed 2026-08-16).** New `common_ssh_tunnel_users`
variable: shell-less accounts (`/usr/sbin/nologin`, no password) restricted by `sshd`
itself, via a per-user `Match` block, to exactly the loopback forwards listed in
`targets`. Deployed as its own drop-in (`90-linumed-tunnel-users.conf`, the
highest-numbered one in the role - a `Match` block scopes everything parsed after it,
across the whole `sshd_config.d` chain, not just its own file, so it has to sort last or
a later drop-in like a cloud image's `50-cloud-init.conf` would get silently swallowed
into it). Verified against a real VM, not just the throwaway container from the issue's
own preliminary check: an account limited to `127.0.0.1:3000` reaches it (`HTTP 200`
through the tunnel) and is refused a forward to `127.0.0.1:9090` with `administratively
prohibited`, and gets no shell at all (`ssh ... whoami` -> "This account is currently not
available."). That is finer granularity than a proxy-level login would have given.

**The restore test is automated (#36, closed 2026-08-16).** A second, independent
systemd timer in the `backup` role, weekly: restore into a throwaway target, diff
against the live source, write the result as its own textfile metrics so a restore test
that silently stops running is exactly as visible as one that starts failing. Found and
fixed a real bug before shipping it - `diff`'s exit code under `set -euo pipefail` would
have zeroed out the exact signal the whole thing exists to produce, the same class of bug
as issue #25. Verified against a real VM with both outcomes actually provoked, not
assumed: a clean restore reports `success=1`, a deliberate post-backup change reports
`success=0` with the diff counted, not just detected.

[#35](../../issues/35) - re-measuring the system requirements - is closed along with the
Authentik role: without four additional containers there is nothing to re-measure. It
returns if the stack grows.

## Open convention questions

These were cases where the repository stated a rule it didn't follow, which is worse than
either following it or changing it. Both are now resolved.

**The healthcheck rule now means the broad reading, and the four missing ones exist
(#38, closed 2026-08-16).** Alertmanager, cAdvisor, docker-socket-proxy and Alloy all got
real healthchecks - checked before assuming any of them couldn't have one, and all four
did once actually tested. `grafana/loki` stays the one genuine exception. Found a real
YAML pitfall while building Alloy's (no `wget`/`curl` in that image, so its healthcheck
uses bash's `/dev/tcp` to speak raw HTTP): a double-quoted YAML scalar interprets `\r\n`
as real control characters at parse time, silently breaking the embedded shell command
before Compose ever sees it - single-quoted YAML was the fix. Verified against a real VM:
all four report `healthy`, not just `running`.

**`docker/` only holding two of six roles is the intended shape now (#37, closed
2026-08-16).** [ADR 0005](adr/0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md) -
narrowed the convention rather than completing it. `backup` was never a gap: it installs
`restic` natively via `apt`, there's no Compose stack there to mirror. `monitoring`'s
seven containers and multiple secrets would have cost real, recurring maintenance for a
reference whose only job is manual smoke-testing - not worth it for a single maintainer.
Checked rather than assumed before deciding: the two existing references
(`docker/caddy/`, `docker/bridgelink/`) had not actually drifted from their Ansible
templates despite the issue's concern.

## Deliberately not on this roadmap

- **v0.3 (Orthanc/DICOM)** and **Linumed Passpin** - named in `ARCHITECTURE.md`, no work
  started, no issues. Passpin is a separate product and is not developed in this repository.
- **A bundled identity provider, a shared `linumed-net`, or a mesh-VPN role.** All three
  evaluated and rejected on 2026-08-14, see
  [ADR 0003](adr/0003-loopback-only-access-no-bundled-identity-provider.md). Connecting
  Grafana to an *existing* provider via OIDC is in scope ([#42](../../issues/42)); shipping
  one is not.
- **Application software** (HIS, DMS, document management). Out of scope by design.
  Institutions bring their own applications; Linumed OS provides the secure base.
- **Kubernetes, bootable images, PXE.** Excluded by `CLAUDE.md`, not revisited here.
