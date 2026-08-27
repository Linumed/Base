# Roadmap

Planned work in the order it should happen, and why that order. Each item links to its
issue; the issue holds the detail, this page holds the sequencing and the reasoning behind
it.

Written 2026-08-14, after an audit of the repository against its own stated requirements
(`CONVENTIONS.md`, `ARCHITECTURE.md`).

> **Update 2026-08-17: every stage written up to that point is done and `v0.2.0` is
> tagged.** A second pass over the repository afterwards - deliberately looking for what a green test suite does
> not prove - turned up one real defect (#48, a Compose reference broken by the #44 fix
> and caught by nobody, because nothing tested it) and four gaps that were closed straight
> away: the full VM test now triggers itself (#45), the `docker/` references have a smoke
> test (#46), `SECURITY.md` exists (#47), and there is a `CHANGELOG.md` (#49). #50,
> publication to GitHub, was the last of those and is closed: the repository is public at
> `Linumed/Base` (MIT), with Forgejo staying canonical and GitHub serving as the push
> mirror. See [CHANGELOG.md](changelog.md) for what shipped.
>
> **Update 2026-08-20: `v0.3.0` is tagged**, see Stage 5 below.
>
> **Update 2026-08-21: `v0.4.0` is tagged** and Stage 6 is complete, see below. What is
> left before 1.0 is Stage 7, and it is now four issues rather than a paragraph.
>
> **Update 2026-08-22: `v1.0.0` is tagged**, Stage 7 is complete. See below for what
> shipped before it and what is deliberately still open.
>
> **Update 2026-08-23: Orthanc removed from the kit** (#92/[ADR
> 0011](adr/0011-orthanc-removed-not-part-of-base.md)) - it held patient data as a
> genuine, unbounded archive with no way to attribute an access to a person, which put it
> on the wrong side of README's own "no application software" boundary. Six roles remain.
> This is a breaking change against the v1.0.0 stability surface; see the ADR for what a
> v2.0.0 release covers. #90 and #84, listed below as the two issues still open after
> v1.0.0, are both resolved by this removal rather than by the fix each originally
> described.
>
> **Update 2026-08-27: `v2.0.0` is tagged.** Five days after `v1.0.0` - a major bump this
> soon after a major release is not what ADR 0008's stability guarantee was written to
> encourage, but it says what it says: a breaking change requires a major version, not a
> grace period. `vm-test.yml` had also been red since the Orthanc removal, intermittently
> failing on a teardown-step SSH flake that never reproduced against a hand-built VM
> (diagnostic instrumentation left in `test/lib/teardown-check.sh` in case it recurs) -
> the tag waited for a real green CI run, not just local verification.

## Where this actually stands

**As of 2026-08-22, `v1.0.0`:** all seven roles are implemented, VM-tested and idempotent -
`common`, `docker`, `caddy`, `monitoring`, `bridgelink`, `backup` and `orthanc`. From this
tag, the surface named in [ADR 0008](adr/0008-what-the-v1-0-stability-guarantee-covers.md)
carries a stability guarantee. The repository is public, the documentation site is built
and published from it, and there are no known defects and no open defect issues. Two
issues remain open, both post-1.0 maintenance rather than tag prerequisites: #84
(re-measuring system requirements for the seven-role stack) and the roadmap items opened
during the pre-1.0 audit (#88-#90), which were deliberately left for after the tag - see
[What comes after 1.0](#what-comes-after-10).

[What was open, and why it was not built earlier](#what-was-open-and-why-it-was-not-built-earlier)
further down is kept as the record of the three items that carried that status until
v0.4.0, because the reason something was open is the more useful half of the answer and
outlives its being open.

The rest of this section is the audit that produced Stages 1-5, kept because the reasoning
still explains why the order was what it was.

There was a gap between roles that work and a product operable by someone who is not the
author.
The audit found it by measurement rather than assumption:

- The example inventory defines two variables. `site.yml` aborts without seven. Anyone
  following the documented quick start hits a preflight abort (#27).
- `ansible-vault` appears nowhere in the repository, although `CONVENTIONS.md` mandates it and
  the role READMEs point at it (#28).
- No git tag exists, although `ARCHITECTURE.md` requires releases to be tagged
  (#29).

So the honest description was: **the roles work, the product does not yet onboard anyone.**
That is what Stage 1 fixed, and it is why SSO was not next despite `ARCHITECTURE.md` naming
it as v0.2.

## Stage 1 - Operability, ending in the v0.1.0 tag (done, 2026-08-14)

Nothing here was a new feature. This stage made the claim already published in the README
("feature-complete and verified") true from an operator's point of view.

| | Issue |
|---|---|
| Complete the example inventory, fix the quick start | #27 closed |
| Document the Ansible Vault workflow, add an example vault | #28 closed |
| Tag `v0.1.0` | #29 closed, tagged |

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

`CONVENTIONS.md` had required MkDocs from the beginning; there was no `mkdocs.yml`. The
documentation sources existed and were good, but nothing built or navigated them.

| | Issue |
|---|---|
| MkDocs setup and operations handbook | #26 closed |
| Translate the existing German docs per ADR 0002 | #30 closed |

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
| Caddy cannot reach the operator's own containers - no working path documented | #39, closed 2026-08-16 |

**#39 is resolved (closed 2026-08-16).** Caddy joins a second Docker
network, created unconditionally by the role (`caddy_external_network_name`, default
`linumed-base-external`, fixed literal name rather than Compose's project-derived one). The
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
`osinfo-db` first. #43's pull-through cache resolved cleanly in the
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
| Tunnel-only SSH users, no shell | #41, closed 2026-08-16 |
| Real Grafana users plus optional OIDC connection | #42, closed 2026-08-16 |

**#41 is resolved (closed 2026-08-16).** New `common_ssh_tunnel_users`
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

**#42 is resolved (closed 2026-08-16).** New `monitoring_grafana_users`
provisions local Grafana accounts (login/name/password/role) idempotently via Grafana's
own HTTP API against `127.0.0.1`, run after the stack deploy has already waited for the
healthcheck - confirmed while building this that Grafana's file-based provisioning covers
datasources/dashboards/alerting but not users, there is no declarative path. A `412`
("user already exists") response is the success case for an already-provisioned account;
only the org-role assignment re-runs on every apply, an existing password is never
touched. `monitoring_grafana_oidc_*` optionally points Grafana's built-in generic OAuth
at an institution's *existing* identity provider - empty `client_id` means nothing
changes, setting it arms a preflight requiring the rest of the OIDC variables, same
all-or-nothing pattern as the Alertmanager SMTP preflight. Verified against a real VM
running the full stack: a freshly provisioned Viewer logs in (`HTTP 200`), is correctly
refused `datasources:create` (`HTTP 403`), sees the shipped dashboards, and a role change
to Editor takes effect on the next apply while the account stays idempotent
(`changed=0`).

**This closes Stage 4 and, with it, every issue that was open at the start of this
session (#39, #41, #42, plus #44 found along the way).**

**The restore test is automated (#36, closed 2026-08-16).** A second, independent
systemd timer in the `backup` role, weekly: restore into a throwaway target, diff
against the live source, write the result as its own textfile metrics so a restore test
that silently stops running is exactly as visible as one that starts failing. Found and
fixed a real bug before shipping it - `diff`'s exit code under `set -euo pipefail` would
have zeroed out the exact signal the whole thing exists to produce, the same class of bug
as issue #25. Verified against a real VM with both outcomes actually provoked, not
assumed: a clean restore reports `success=1`, a deliberate post-backup change reports
`success=0` with the diff counted, not just detected.

#35 - re-measuring the system requirements - is closed along with the
Authentik role: without four additional containers there is nothing to re-measure. It
returns if the stack grows.

## Stage 5 - v0.3: the name, and observability that observes something (done, 2026-08-20)

Two unrelated things share this release because they happened in the same window.

**The product got its own name.** "Linumed OS" described something this repository is not -
a collection of Ansible roles that configure a standard Debian install is not an operating
system. Renamed while nothing was published and nothing was installed anywhere; identifiers
moved with it (`linumed-base-*` containers, `/opt/linumed-base`, `linumed-base-external`).
[ADR 0006](adr/0006-linumed-base-not-linumed-os.md) has the reasoning and what was
deliberately *not* renamed.

**BridgeLink reports application metrics (#60, closed 2026-08-19).** Until now the only
BridgeLink data Prometheus held came from cAdvisor: CPU, RAM and network of the container.
For an integration engine that is close to useless - a channel that is deployed but stopped,
or a destination queue that has stopped draining, looks exactly like an idle healthy
container. BridgeLink serves no `/metrics`, so the role gained a standard-library exporter
sidecar running in a pinned upstream `python` image, plus six alert rules.

`prometheus-community/json_exporter` was tried first and rejected on a measurement, which is
worth recording so nobody re-evaluates it: BridgeLink's JSON is serialised from its XML
model, so a list with exactly one entry becomes an object and json_exporter's JSONPath
matches nothing - while still reporting the scrape as successful. A monitoring gap that
announces itself as healthy is worse than none. The exporter reads the XML instead.

### What the test found, which is the more valuable half

| | Issue |
|---|---|
| Documented secret ownership that produces a restart loop | #61 closed |
| `vm-test` never exercised the exporter with the switch on | #62 closed |
| Prometheus config changes never reached Prometheus | #63 closed |
| Prometheus could not reach the exporter at all | #64 closed |
| Diagrams redrawn and pre-rendered to SVG | #65 closed |

**#62 is the reason the other two exist.** `bridgelink_exporter_enabled` defaults to false,
so the existing double-run proved only that the feature is a no-op while switched off - the
enable path had no coverage whatsoever. A third `site.yml` pass with the switch on found two
real defects within two runs. The general lesson, now in `CONVENTIONS.md`: **anything behind
a default-off flag ships with zero test coverage until a test deliberately turns it on.**

**#63 was the expensive one, and it was not new.** `prometheus.yml` and `alert-rules.yml`
were bind-mounted as individual files. A single-file bind mount binds the inode; Ansible
rewrites atomically, orphaning it. Since the monitoring role was written, **no Prometheus
configuration or alert-rule change had ever reached the running container** - playbook
`changed`, validation green, `/-/reload` answering 200, and nothing reporting an error.
Only Prometheus was affected, because it is the only service here reloaded over HTTP rather
than restarted, and a restart re-resolves the mount.

This is the same defect as #44 in the Caddyfile, documented in Stage 3 above, four days
earlier. The precedent existed and was simply never transferred - which is why it is now a
rule in `CONVENTIONS.md` rather than a closed issue: a config file Ansible manages is
mounted as its containing directory, never as the file.

**#64 was self-inflicted and is instructive about verification.** The exporter was addressed
via `host.docker.internal`, copied from the Node Exporter job - whose precondition, being a
*native* service that ufw can protect, does not transfer to a container. A container port on
`127.0.0.1` is unreachable from another container, and publishing it on all interfaces would
bypass ufw entirely. Fixed with a shared, explicitly named Docker network
(`linumed-base-metrics`), the same pattern as `linumed-base-external` from #39. Worth noting
how it survived: #60 was verified by hand against real instances - container, secrets,
healthcheck, metrics, alert expressions - and still shipped this, because the hand
verification never walked the scrape path *from Prometheus*. Hand verification and a role
run do not test the same thing.

**#65 - the diagrams.** Three attempts at theming had not made them look better, because the
problem was not colour: the target-architecture figure drew arrows at the boundary of the
Docker group, including one from that group to a node inside itself, which renders as a
label with no arrow. Redrawn as two figures (containment, then flow) and pre-rendered to
committed SVGs, which also settles a quieter problem - the diagrams appear on the MkDocs
site, on GitHub and in Forgejo, and browser-side theming only ever reached the first of the
three.

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
reference whose only job is manual smoke-testing - not worth the recurring cost.
Checked rather than assumed before deciding: the two existing references
(`docker/caddy/`, `docker/bridgelink/`) had not actually drifted from their Ansible
templates despite the issue's concern.

## What was open, and why it was not built earlier

> **All three items below closed in v0.4.0**, #66, #67 and #68 all on 2026-08-20.
> Rewritten to the past tense on 2026-08-21; until then this section still
> opened with "everything above is done, this section is the part that is not", which had
> quietly become false. What is open *now* is Stage 7, further down.

The section is kept rather than deleted because "why wasn't that in v0.1?" is the second
question a reader of a public infrastructure kit has, after "what is left?", and answering
only the first reads like a wish list. The reason an item was open outlives its being open.

None of these was a feature someone forgot. Each was open for one of three reasons, and the
reason determined how urgent it was:

**1. It could not have been built earlier without guessing.** The stability guarantee
(#66, closed 2026-08-20) is the clearest case: a promise about which names and paths will not change is
worthless before those names have survived contact with real use. v0.3.0 renamed every
identifier; had 1.0 been declared in July, that rename would have been a broken promise
instead of a normal release.

**2. It only becomes visible once someone else operates it.** The lifecycle questions
(#68, closed 2026-08-20) - what happens at a Debian major upgrade, how to remove the kit again, whether it
assumes a single host - stay invisible as long as the only people running the kit are the
people who built it, because they know the answers without writing them down. They are
also the questions that decide whether an evaluator tries the kit at all.

**3. It was an accepted responsibility with no mechanism behind it.** Container image
scanning (#67, closed 2026-08-20) was the uncomfortable one. `SECURITY.md` lists "pinned image versions with
known vulnerabilities that have a fixed version available" as in scope - and nothing in
this repository has ever checked. Measured on 2026-08-20: all eleven pinned images carry
fixable HIGH/CRITICAL findings - 129 distinct image/CVE pairs. (An earlier count of 192 in
this section came from summing per-package occurrences, which counts the same CVE several
times when it affects several packages in one image. The scanner deduplicates.) Some are simply behind (Alertmanager and
Grafana both have newer tags), others are already on the newest tag and carry findings
from their upstream base image, which no version bump here can clear. That difference is
the whole design problem: a gate that goes red on any finding is permanently red, and a
check that always says the same thing stops being read - the exact failure mode this
repository already hit three times (#40, #48, #63).

There is a fourth category worth naming because it was never on this list: things that were
evaluated and rejected. Those live under "Deliberately not on this roadmap" below, with
their ADRs. An open question and a closed decision are different states, and conflating
them is how a rejected idea quietly comes back.

## Stage 6 - v0.4: the last named service, and the maintenance the kit does not yet do

| | Issue |
|---|---|
| Scan the pinned images, and act on the difference between "behind" and "upstream's problem" | #67, **done 2026-08-20** |
| Orthanc as the DICOM role | #69, **done 2026-08-21** |
| The node-baseline subset, deployable and tested on its own | #70, **done 2026-08-20** |
| Lifecycle: Debian major upgrade, teardown, the single-host assumption | #68, **done 2026-08-20** |

**Ordering, and it matters:** #67 comes before #69. Adding a role means adding two more
pinned images, and until something checks whether pins go stale, every new role widens a
gap that has already been measured. Building the scanner second would mean building it
against a larger problem than necessary.

Orthanc (#69) is the last service named in `ARCHITECTURE.md` that does not exist. It moves
the claim "healthcare infrastructure stack" from integration (HL7/FHIR, via BridgeLink)
to imaging. It was not built earlier because the order was deliberate: the role set first,
then operability, then the name and observability. A DICOM role on an untested foundation
would have been the wrong sequence, and it is also the role with the sharpest data
protection profile in the kit - DICOM metadata routinely carries names and dates of birth
alongside the images.

## Stage 7 - v1.0: the promise, and what it covers

v1.0 is not a quality label and does not arrive by itself. It is the point from which a
breaking change requires a major version bump - and that promise could not be made before
someone wrote down what it applies to.

**That is now written down (#66, closed 2026-08-20):**
[ADR 0008](adr/0008-what-the-v1-0-stability-guarantee-covers.md) names the covered surface,
measured rather than estimated - re-measured against seven roles on 2026-08-21 (#73),
then again against six roles on 2026-08-23 after Orthanc's removal (#92/ADR 0011):
120 interface role variables (plus four internal, ADR 0010), deploy paths, 11 container
names, two shared networks, this kit's own
metric names, 13 alert rule names, four systemd units, the seven variables a plain run
aborts without, and the Grafana dashboard and datasource UIDs that every operator-built
panel references. It also names what is deliberately *not* covered: pinned
image versions have to keep moving, and #67 exists to make them move.

What remains for v1.0 is therefore not definition but **removal**, because the tag freezes
whatever exists at that moment. The lifecycle questions (#68), the third item ADR 0008
named as a precondition, are closed since 2026-08-20. Three items remain, and their order
is not arbitrary:

| | Issue |
|---|---|
| Audit the role variables for ones that should not be carried forever | #71, **done 2026-08-21** |
| Decide which variables are internal rather than interface | #72, **done 2026-08-21** |
| Re-measure ADR 0008's surface against seven roles, not six | #73, **done 2026-08-21** |
| Tag and publish v1.0.0 | #74, **done 2026-08-22** |

**#71 before #72**: the audit decides *whether* a variable survives, the visibility
decision decides *what it survives as*. Doing them the other way round means classifying
variables that are about to be deleted.

**#73 existed because the measurement aged faster than the decision.** ADR 0008 measured
its surface across six roles on 2026-08-20; Orthanc (#69) landed a day later with 18 more
variables, and was in none of the ADR's numbers - not the container names, not the deploy paths,
not the volumes. **#73 is done (2026-08-21):** every row of the ADR's table was re-measured,
and two of them were wrong for reasons that had nothing to do with Orthanc - the variable
count missed every name containing a digit, and "variables with no default" was not a
measurable category, since all of them have one (the empty string). A guarantee resting on
a stale measurement is the exact failure ADR 0008 was written to avoid: its whole point was
to *measure* the surface rather than estimate it.

**#71 is done too, and it contradicted the ADR.** `monitoring_retention_days` was named
there as the known removal candidate, "dead weight". It is not: both templates read it, the
role page documents it twice, and `CONVENTIONS.md` uses it as the naming-convention example.
It stays. The one variable nothing read was `monitoring_grafana_analytics_enabled` (#75,
removed), leaving 146 defined. The "30 variables documented nowhere" figure from that audit
was itself too high - the search behind it could not see collapsed table rows like
`backup_retention_keep_daily/weekly/monthly`. Measured correctly during #72 it was 19, and
they are now either documented or recorded as internal.

## What comes after 1.0

A roadmap that ends at the tag reads like a discontinued project. It doesn't - the tag was
never the finish line, only the point where the promise starts applying. What follows was
sorted by whether it touches the surface ADR 0008 now freezes: anything that does had to
be decided *before* the tag or not at all, which is why #86 landed the day before it
rather than after.

**Landed just before the tag, on that reasoning:**

| | Issue |
|---|---|
| Role selection (`linumed_base_roles`) - deploy a subset instead of all seven | #86, **done 2026-08-22** |

A per-role deployment mechanism is exactly the kind of thing that would have been frozen
on its first design if it had shipped after 1.0. Building it before meant the two
preflights it turned out to need (a missing dependency, a deselected role that had already
run) could still be added for free.

**Open, deliberately after 1.0 - none of these touch the frozen surface:**

| | Issue |
|---|---|
| Role-selection TUI, `whiptail`-style over SSH | #87 |
| A register for numeric claims in prose, so they stop aging silently | #88 |
| A documented, tested upgrade path between kit versions | #89 |
| An access log for Orthanc - the kit claims DGSVO-compliance and currently keeps none | #90, **resolved 2026-08-23 by removing Orthanc (#92/ADR 0011) rather than building one** |
| Re-measure system requirements including Orthanc | #84, **done 2026-08-22, then re-measured again after removal (#92)** |

#87 depends on #86 and only became plannable once #86 existed. #88, #89 and #90 came out
of a deliberate brainstorm on 2026-08-22, once the tag itself no longer needed sequencing
decisions - the point of asking "what comes after 1.0" only arrives once "what must come
before" has an answer. #84 is the one item here found by measurement rather than
proposed: the README's own requirements table claims to be measured and has not accounted
for Orthanc since the role landed in v0.4.0. Investigating #90 surfaced the findings that
became #92, which removed Orthanc entirely - closing both #90 and #84 by removing the
thing they were about, not by building the access log or re-measuring Orthanc's footprint
forever.

None of these five is a stability-surface change. That is what makes them safe to decide
at leisure rather than under the same before-the-tag pressure #86 was built under.
