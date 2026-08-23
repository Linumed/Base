# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Written in
English like the rest of the documentation (ADR 0002), even though commit messages are
German - a changelog addresses the same readers the
documentation does. Every entry names its issue, so the reasoning behind a change is one
click away instead of restated here.

## [Unreleased]

### Changed

- **README's "System requirements by stack" table re-measured to include `orthanc`**
  (issue #84), same methodology as the original table: RAM sized down on a fresh VM
  until `site.yml` still deployed cleanly, `free -m` "used" read after a 2-5 minute
  settle. Finding: Orthanc barely moves the floor. With or without it, the stack bottoms
  out at 1.5 GB - BridgeLink's JVM is the binding constraint, not Orthanc's PostgreSQL or
  archive. 1 GB fails outright: BridgeLink never finishes starting. Disk did move, 6.0 GB
  to 7.0 GB, from pulling Orthanc's two images. Table now has a "no imaging" row built on
  `linumed_base_roles` (#86) next to "Full stack (all seven roles)", replacing the old
  stopgap note that excluded Orthanc from the numbers entirely.

### Added

- **`scripts/check-numeric-claims.py` re-verifies a curated list of numeric claims in
  prose against what the repository currently measures** (issue #88). Five real cases
  this week alone: ADR 0008's role-variable count (125, then silently wrong again at 129
  and 146), the "30 undocumented variables" figure from the #71 audit (was 19), the
  README's requirements table (silently excluded Orthanc), "all six roles" in two places
  (became seven), `node-baseline.yml`'s "three Compose stacks" (became four). Code has
  had gates against this shape of drift for a while; prose had none until now.

  Deliberately a register, not a scan - modelled on `ansible/internal-variables.txt` and
  `security/accepted-image-findings.txt`. It only re-checks the eleven claims explicitly
  listed in the script, because not every number in this repository is supposed to stay
  current: `docs/ROADMAP.md`'s "Measured on 2026-08-20: all eleven pinned images..." is a
  dated record and correct forever as written, and a checker that flagged it as stale
  would train everyone to ignore the next real finding - the same failure mode
  `scripts/scan-images.py` already exists to avoid. Reuses `check-variable-docs.py`'s own
  counting functions rather than re-deriving the same numbers a second way.


- **A documented, tested upgrade path** (issue #89). Until now "pull the new version, run
  `site.yml` again" was a plausible answer nobody had actually tried across a version
  boundary - idempotency within one version and idempotency across an upgrade are
  different claims. Measured by hand for the first time this kit has ever been upgraded
  (`v0.4.0` → `v1.0.0`): two changed tasks, both explained by issue #80's
  `orthanc_http_port` template change, nothing else moved, and the second apply was
  `changed=0`. Written up in
  [docs/operations/upgrading.md](operations/upgrading.md) with that result as a
  worked example.

  `test/lib/upgrade-check.sh` keeps this true going forward: on every relevant push, the
  CI VM is deployed with the previous tagged release first (reusing the VM
  `test/vm-test.sh` already provisions rather than starting a second one), then upgraded
  to the commit under test, with the changed-task count reported explicitly. The tag it
  upgrades from is a fixed literal, bumped by hand when preparing each release -
  deliberately not auto-detected, for the same reason coupled literals elsewhere in this
  kit are compared rather than inferred (ADR 0010).


- **`scripts/select-roles.sh` picks a subset of the seven roles interactively** (issue
  #87), rather than requiring an operator to hand-edit `linumed_base_roles` (#86) and
  remember its one dependency rule. A `whiptail` checklist - the same toolkit Debian's own
  installer uses, nothing on the network - shows the resulting YAML before writing it, and
  offers `orthanc` only once `monitoring` is selected, since `orthanc_metrics_enabled`
  defaults to true and orthanc alone fails `site.yml`'s own preflight otherwise.
  `bridgelink` is deliberately not gated the same way: its exporter defaults to off, so
  bridgelink alone is a normal, supported combination, and gating it too would make the
  tool more restrictive than the kit actually is.

  Re-running it replaces the previous selection in place rather than duplicating it, and
  a `--non-interactive` mode (used by `test/select-roles-check.sh`, since `whiptail`
  cannot be driven headlessly) makes the same logic usable from a script.

### Fixed

- **`docs-site.yml` kept recreating the `docs-site-latest` release and tag on every doc
  push, even after they were deleted as part of closing #85.** The step that created them
  had no `if:` guard - it was unconditional, so the release/tag came right back on the
  next push and reappeared in the public GitHub mirror's tag list next to `v1.0.0`. Now
  that the package registry path is confirmed working (cc@prod switched and verified
  independently), the release/tag creation is removed outright rather than gated - the
  package path was always meant to replace it, not run alongside it indefinitely.

## [1.0.0] - 2026-08-22

The tag ADR 0008 was written for: from here, a change to role variable names, deploy
paths, container and network names, this kit's own metric and alert names, dashboard and
datasource UIDs, or systemd unit names requires a major version bump. Nothing about this
release is a quality claim - v0.4.0 already had no known defects - it is the point from
which the promise applies.

Before tagging, the surface itself was re-measured rather than assumed correct (#71-#73),
narrowed to what should actually be frozen (#72), and closed against silent drift with
five new CI gates - variable documentation, cross-role literal agreement, Prometheus
scrape targets, the image-pin table, and role selection. The two biggest items landed
just before the tag rather than after it, on the reasoning in #74: whatever ships as part
of the interface should have survived contact with real use first. `linumed_base_roles`
(#86) is the clearest case - a mechanism invented after 1.0 would have been frozen on its
first try, with no chance to find the two preflights it turned out to need.

### Changed

- **ADR 0003's "does it work after the playbook run" criterion now has three levels instead
  of two.** As written it read as a yes-or-no test, and applied that way it rejects `caddy`
  (serves nothing until `caddy_sites` is set), `bridgelink` (transports nothing without
  channels) and `orthanc` (receives nothing until a modality is pointed at it) - which is
  the wrong answer, because that is what infrastructure is.

  The distinction that actually matters is **what is missing**: nothing, content the
  operator supplies in the course of normal use, or another system somebody has to procure
  and integrate. Only the third is what the ADR rejects. `CONVENTIONS.md` now asks the
  question where a new role would be proposed.

- **Eight role variables are recorded as implementation detail rather than interface, so
  v1.0 promises 138 names instead of 146** (#72). The two `*_uid`/`*_gid` pairs are dictated
  by the container images - a different value is the restart loop of #61 - and the two
  `*_db_name`/`*_db_user` pairs address a PostgreSQL that runs inside its own Compose stack
  with no host port, where a change on an existing host points the application at a database
  without its data. They are listed in `ansible/internal-variables.txt` with the reason for
  each.

  Nothing was renamed, removed, or changed in behaviour, so this is not a breaking change.
  Setting one of the eight still works exactly as before; what no longer applies is the
  promise that the name survives to 2.0.

  ADR 0010 has the reasoning,
  including why the list is documented rather than enforced. Ansible could enforce it -
  `vars/main.yml` outranks inventory `group_vars` - but it enforces by discarding an
  operator's override in silence, which is the failure mode of #44, #63 and #78. The new
  `scripts/check-variable-docs.py` enforces in CI instead, where a failure can name the
  variable and the file.

- **Eleven variables gained the documentation they should already have had**, found by that
  same check: `backup_exclude`, `backup_restic_password_file`, `backup_textfile_dir`,
  `monitoring_prometheus_retention_size`, `monitoring_node_exporter_textfile_dir`,
  `monitoring_orthanc_target`, the two Grafana telemetry switches, the two OIDC display
  variables, and `orthanc_metrics_network` - the third leg of a three-way constraint whose
  other two legs were documented.

### Added

- **The Orthanc scrape credentials are checked against `orthanc_users` before deployment**
  (#76). Orthanc serves its own metrics endpoint behind its own REST authentication (ADR
  0009), so the same account has to exist twice: once in `orthanc_users`, once in
  `monitoring_orthanc_user`/`_password`. Until now the two were kept equal by a comment in
  the example vault. A drift produced a 401, which Prometheus reports as a target that is
  down - the same symptom as an Orthanc that was never deployed at all.

  The monitoring role's preflight now refuses to deploy on a mismatch and names the
  accounts involved, never the password. It compares hashes so no plaintext can appear in
  output at any verbosity, and it skips the comparison when `orthanc_users` is absent -
  a monitoring-only playbook pointed at an Orthanc deployed elsewhere is legitimate.

- **The VM test switches the Orthanc scrape on** (#76, #62). It defaults to off, so every
  run until now proved only that the feature is a no-op while disabled: the scrape job, its
  `basic_auth` and the three Orthanc alert rules had no coverage at all. The new
  `test/lib/orthanc-scrape-check.sh` applies `site.yml` with the switch on, checks the run
  is idempotent, checks Prometheus actually has a healthy `orthanc` job - and then feeds the
  preflight a deliberately wrong password to prove it refuses, and that its output does not
  contain the password. A gate that has never refused anything cannot be told apart from one
  that does not work.

- **`scripts/check-variable-docs.py`, run on every push** (#72). It also compares each
  Prometheus scrape target against the Compose template of the role that owns the container
  (#80) - the target names another role's container and the port inside it, and both ends
  are literals with no shared source. Fails when a role variable
  is neither documented under `docs/` nor recorded as internal, when a recorded name no
  longer exists, or when an entry carries no reason.

  It also compares the literals that must agree across roles. This kit has **no cross-role
  variable reads at all** - not one variable is dereferenced outside the role that defines
  it - so each cross-role relationship is a value duplicated into a second variable with a
  comment saying "must match". That is a convention rather than something Ansible enforces:
  every role's variables are visible to every other role in the same play, defaults and
  `vars/` alike. The three legs of `linumed-base-metrics` and the two textfile directories
  are now compared rather than trusted.

- **`linumed_base_roles` selects a subset of the seven roles to deploy** (#86). Defaults
  to all seven; an operator can, for example, deploy everything except `orthanc` on a site
  with no imaging. It is a play variable in `site.yml`, not a role variable - it never
  appears in a role's `defaults/main.yml`, so it adds nothing to the surface ADR 0008
  measures.

  Ansible tags were considered and rejected: the selection would then live on the command
  line, and an operator who deployed a subset and later ran plain `site.yml` would
  silently get the full stack back, with no record anywhere of what the host was meant to
  be. A list in the inventory keeps that record where the rest of the host's configuration
  already lives, and a typo in it aborts the run instead of being silently ignored.

  Three preflights in `site.yml`'s `pre_tasks` guard the selection: an unknown role name,
  a missing dependency (`docker` for any Compose role, `common` for `monitoring` unless its
  ufw deny rule is off, `monitoring` for `orthanc`/`bridgelink` with their metrics switches
  on), and - deliberately - a role that is *not* selected but has already run on this
  host. The last one refuses rather than removes: `docs/operations/teardown.md` argues at
  length why automated removal on a production host would be guesswork, and this respects
  that rather than reinventing it. The check probes exactly what that page's own removal
  procedure deletes, so following it never trips a false alarm.

  `node-baseline.yml` is now a thin wrapper setting `linumed_base_roles: [common, docker,
  backup]` and importing `site.yml`, rather than a hand-maintained second role list - the
  previous form had already drifted once, silently, for four months, when the `orthanc`
  role landed and nobody updated the duplicate.

### Fixed

- **`orthanc` and `bridgelink` used to fail on a missing metrics network with Compose's
  raw error instead of a clear one** (#86). `docker compose config` does not resolve
  `external: true` networks, so a host with `orthanc_metrics_enabled` or
  `bridgelink_exporter_enabled` on but no `monitoring` role failed deep inside
  `docker_compose_v2` with "network declared as external, but could not be found". Both
  roles now check for the network themselves, after monitoring would have run in the same
  play, and name the actual problem.

- **A host with no Compose role got a restore test that reported success forever without
  comparing anything** (#86). `backup_restore_test_diff_paths` defaults to
  `/opt/linumed-base`, which never exists on such a host - exactly the shape
  `node-baseline.yml` already ships. The weekly `diff -rq` then died under
  `set -euo pipefail`, and the trap still wrote `restore_test_success 0` with no way to
  tell "restore failed" from "there was nothing to diff". Caught at deploy time now, the
  same way `backup_paths` already was - and `node-baseline.yml` sets
  `backup_restore_test_enabled: false` by default, because it has no way to know what
  `backup_paths` will be on a given node and cannot pick a diff path that means anything.
  The CI run for this exact combination went from silently green to loudly red the moment
  the preflight above was added, which is what caught this before it shipped.

- **Three statements in the public README and the deployment page had gone stale since
  Orthanc landed** (found while preparing #74). The "if you run Kubernetes" paragraph
  listed only `caddy`, `monitoring` and `bridgelink` as Compose-coupled - `orthanc` is too;
  `docs/operations/deployment.md` said `site.yml` applies "all six roles", which has been
  seven since v0.4.0; and the quick start said the example vault lists "the six variables
  with no safe default" - it lists ten secrets, of which eight abort `site.yml` outright
  and two only once the Orthanc scrape is on (#73 measured this).

  The system requirements table has the same problem and it cannot be fixed by editing:
  it opens with "Measured, not estimated" and its "full stack" row was measured before the
  `orthanc` role existed. Re-measuring is #84; until then a note under the table says
  plainly that Orthanc is not in those numbers, rather than leaving a figure that claims a
  measurement it no longer has.

- **The pin table in `docs/operations/updates.md` no longer drifts, because it can no
  longer drift** (#81). Two tags were behind the roles (`grafana/grafana:13.1.3` against
  13.1.4, `postgres:17.10-alpine` against 17.11) and three images were missing from it
  entirely - `bridgelink_exporter_image`, `orthanc_image`, `orthanc_postgres_image`.

  The table carried a note saying it "will drift", and while it was only a convenience that
  was a defensible trade. It stopped being defensible when ADR 0010 made that table the
  documentation keeping those thirteen variable *names* inside the v1.0 promise: a row that
  claims a wrong version is not trustworthy about the name either.
  `scripts/check-variable-docs.py` now compares every row against the roles on every push,
  and the note is gone because the claim it made is no longer true.

- **A comment in the backup role described the restic package install while sitting above
  `backup_restic_password_file`** (#82). Moved to the task it actually explains; the
  variable now has a comment about the variable, including that `docs/roles/backup.md`
  names the path literally in its manual restore procedure.

- **`mirth.properties.j2` stated the UID as a literal `65532` next to the variable name**
  (#83). It sits inside a Jinja comment, so the number never rendered anywhere - it was
  documentation that would have gone quietly wrong the moment the image changed the UID.
  Now it names `bridgelink_uid` and no number. Deliberately not `{{ bridgelink_uid }}`:
  inside a `{# ... #}` block that would not interpolate, and writing it that way would
  suggest it does.

- **The pre-1.0 surface measurement in ADR 0008 said "the six vault variables" while its own
  table said nine** (#73), and the audit figure of "30 undocumented variables" (#71) was too
  high because the search behind it could not see collapsed documentation rows such as
  `backup_retention_keep_daily/weekly/monthly`. Measured correctly it was 19. Both figures
  are corrected where they appeared, including `ARCHITECTURE.md`.

### Breaking

- **`orthanc_http_port` now only moves the host-side port; inside the container Orthanc
  always listens on 8042** (#80). It used to set both, and that quietly broke the Prometheus
  scrape: Prometheus reaches Orthanc by container name over the metrics network, so it
  cannot follow a change to the published port. `monitoring_orthanc_target` kept pointing at
  `:8042` and the scrape died with a connection refused - which Prometheus reports as a
  target that is down, the same symptom as an Orthanc that was never deployed.

  The variable's own comment already described it as the host-side tunnel port
  (`ssh -L 8042:127.0.0.1:8042`); the implementation did more than the documentation
  promised. The BridgeLink role never had the defect - its container side is a literal on
  both the admin port and the exporter - so this also makes the two roles consistent.

  **What changes for an existing deployment:** nothing, unless `orthanc_http_port` was set
  to something other than 8042. If it was, Orthanc now listens on 8042 inside the container
  and the chosen port is published on the host, which is what the documentation always
  described. Tunnels and modality configuration are unaffected.

## [0.4.0] - 2026-08-21

The release that completes the service set named in `ARCHITECTURE.md`, and adds the
maintenance the kit had been going without.

Orthanc was the last service named in `ARCHITECTURE.md` that did not exist; with it the kit
has seven roles. The rest of this release is what happens when you look at a working system
and ask what it *cannot* tell you yet: nothing checked the pinned images for
vulnerabilities, nothing said how to remove the kit again, and nothing had ever exercised a
feature that ships switched off.

Several of the defects below were found by tests written for something else in this same
release.

### Added

- **Orthanc: the DICOM archive, the last service named in `ARCHITECTURE.md` that did not
  exist** (#69). Orthanc (GPLv3) with its index in PostgreSQL and the pixel data on a Docker
  volume, running unprivileged, reachable only through an SSH tunnel until the operator
  deliberately opens the DICOM port.

  **The image choice went against the obvious one, and only measuring showed why.** Upstream
  frames its two image families by audience - `orthancteam/*` for "ops teams",
  `jodogne/*` for developers - which points at the first for a kit like this. But
  `orthancteam/orthanc` **cannot run as a non-root user**: its entrypoint fails on
  `/etc/hostid` and the container exits. For the component holding DICOM images and their
  metadata - names, dates of birth, referring physicians - that settled it.
  `jodogne/orthanc-plugins` runs as UID 65532 with the same core version and the same
  plugins. The comparison and what else was measured are in ADR 0009.

  **No exporter was needed.** Orthanc serves Prometheus metrics natively at
  `/tools/metrics-prometheus` - 46 of them, including study counts, disk size, pending jobs
  and logged errors. That is the opposite of the answer BridgeLink gave in #60, and the
  reason that pre-check is now mandatory when adding a service: here it saved building
  anything. Three alert rules ship dormant until the metrics appear.

  **The DICOM listener is not published by default.** Modalities cannot reach the archive
  until an operator turns it on, and no modality is trusted until it is listed - a published
  container port bypasses ufw, and what arrives on it is patient data. Same reasoning as
  BridgeLink's channel listeners.

- **`node-baseline.yml`: the runtime-agnostic part of the kit is now deployable on its
  own** (#70). Since ADR 0007 the README told operators running Kubernetes that `common`,
  `docker` and `backup` were theirs to use on their cluster's nodes - true, but with no way
  to actually deploy them, because `site.yml` was the only playbook and no task carries an
  Ansible tag. It was a claim derived from counting which roles ship a Compose file, which
  is the same shape of reasoning that produced the volume-name error in #68.

  It is now applied to the pristine VM on every relevant push, checked for idempotency, and
  checked for **effect** rather than exit code: ufw active, password authentication off,
  Docker running, backup timer enabled - and no service container started, which is the
  other half of the claim.

  The backup role gained a preflight that refuses to deploy when **none** of the configured
  `backup_paths` exists. The default covers this kit's own state, which is the wrong answer
  on a node whose data lives elsewhere; without the check, that mistake would first surface
  as a failed backup at 03:00. Deliberately "none" rather than "all": in `site.yml` the
  backup role runs last, and an operator may legitimately list a path a service creates
  later.

- **The lifecycle questions now have answers** (#68). Three things a service provider asks
  before deploying anything, and which this repository could not answer:

  **How do you remove it?** New page `docs/operations/teardown.md`, with a complete,
  measured inventory of what the kit leaves on a host - 17 paths, six packages, the Docker
  volumes, ufw rules and tunnel users. There is deliberately no uninstall playbook: `ufw`,
  `fail2ban` and Docker may have been there beforehand, and an automated teardown would be
  guessing on a production host.

  The procedure is **executed, not just written** - `test/vm-test.sh` runs it against the
  throwaway VM as its last act and asserts the page's own verification commands. That
  caught a dangerous error on the first run: the page told operators to find the data
  volumes with `grep linumed-base`, which matches nothing, because Compose names volumes
  after the project and not after `container_name`. Followed literally, it would have read
  as "there is no data here" while every volume was still in place.

  **What happens at a Debian major release?** The supported path is a reinstall and a
  restore, not an in-place `dist-upgrade` - stated as a position, with the reasoning, in
  `docs/operations/updates.md`. Debian 13 has support until August 2028, so this is a
  question with runway; it just needed an answer.

  **One host or several?** One. `docs/operations/deployment.md` now says so, with the
  specific reasons, and states the consequence plainly: no high availability.

- **ADR 0008 defines what the v1.0 stability guarantee will cover** (#66). Correcting the
  old "breaking changes only from v1.0 onward" fixed *when* the promise starts; this fixes
  *what it applies to*, which is the half that matters. Tagging 1.0 without it would mean
  committing to an obligation of unknown size - and unlike a bug, an over-broad promise
  cannot be quietly fixed afterwards.

  The surface was measured, not estimated: 125 role variables, deploy paths, 11 container
  names, two shared Docker networks, this kit's own metric names, 13 alert rule names, four
  systemd units, the six variables that have no default, and the Grafana dashboard and
  datasource UIDs. That last one was nearly missed - every panel in an operator's own
  dashboard references a datasource by UID, so renaming `prometheus` or `loki` would break
  work this kit never sees.

  Deliberately not covered: pinned image versions, which have to keep moving. A default
  value may change without a major bump but must be called out as breaking if it changes
  behaviour on an existing host.

  What remains before the tag is **removal, not addition**, because 1.0 freezes whatever
  exists at that moment - starting with variables that should not be carried forever.

- **Pinned container images are now scanned for known vulnerabilities** (#67).
  `SECURITY.md` has always listed "pinned image versions with known vulnerabilities that
  have a fixed version available" as in scope for a security report, and nothing in the
  repository ever checked. On the day the scanner was written, all eleven pinned images
  carried fixable HIGH/CRITICAL findings - 129 distinct image/CVE pairs.

  `scripts/scan-images.py` runs weekly in CI, and deliberately is not a plain
  `trivy && exit $?`. A finding is only actionable if a newer tag would clear it, and being
  behind does not guarantee that: bumping Grafana 13.1.3 to 13.1.4 cleared 5 of 18
  findings, bumping Postgres 17.10 to 17.11 cleared none. So the script scans the candidate
  before demanding the bump, treats a newer *series* (13.1 to 13.2) as a decision rather
  than a security patch, and requires anything remaining on an already-current image to be
  recorded with a reason and a date in `security/accepted-image-findings.txt`. A check that
  is permanently red stops being read.

  Two pins were bumped as a result (Grafana, PostgreSQL), and the exporter's image pin was
  corrected: `python:3.13-alpine` looks pinned but is a floating series tag that moves on
  its own. It is now `python:3.13.15-alpine`.

- **ADR 0007 records why there is no Kubernetes support** - and says what that costs. The
  exclusion existed in three places and gave a reason in none of them: the roadmap deferred
  to `CONVENTIONS.md`, and `CONVENTIONS.md` simply asserted it. An exclusion without
  recorded reasoning cannot be defended when asked about, and cannot be revisited
  intelligently later.

  The decision stands, on the same criterion that removed SSO and a mesh-VPN role in
  ADR 0003: a cluster is a subsystem the institution has to supply, and this kit has to
  work after the playbook runs on a machine the operator already has. The ADR states the
  cost plainly - **one host means no high availability** - and names the conditions under
  which it would be reopened, as a separate repository rather than a flag in this one.

  It also records something previously invisible: `common`, `docker` and `backup` are
  runtime-agnostic, so a Kubernetes shop can use the node baseline for the machines under
  its cluster. Only `caddy`, `monitoring` and `bridgelink` are Compose-coupled.

  The README gained a **"What it deliberately does not do"** section covering this, the
  access model, and the FOSS-only rule - up front, because the fastest way to evaluate a
  kit is to find out early whether it is the wrong one.

### Changed

- **`ARCHITECTURE.md` no longer promises "certification prep" for v1.0.** The term appeared
  exactly once in the entire repository and was defined nowhere - an undefined reference to
  certification in a public healthcare repository raises an expectation nobody committed
  to. If a specific certification becomes a goal, it gets named, scoped and given an issue.

- **The roadmap now says what is still open and why** (#66, #67, #68, #69). It was
  entirely retrospective: every stage described work already finished, so "what is left?"
  had no answer in the repository at all. It now names the open items, and for each the
  reason it is open - something that could not be decided earlier without guessing,
  something only visible once a second person operates the kit, or a responsibility
  `SECURITY.md` accepts with no mechanism behind it.

  The most consequential of those is the third: nothing here has ever checked the pinned
  container images for known vulnerabilities, although `SECURITY.md` lists exactly that as
  in scope. Measured on 2026-08-20, all eleven pinned images carry fixable HIGH/CRITICAL
  findings.

  v0.4 also gained content beyond Orthanc, and `ARCHITECTURE.md`'s versioning strategy was
  updated to match.

### Fixed

- **Image pulls are retried instead of failing the playbook on the first hiccup.** A pull
  failure here fails the whole run, and on this infrastructure that is a measured recurring
  problem rather than a theoretical one: issue #43 was opened after half the full-stack VM
  runs on one day failed pulling from Docker Hub, and a CI run on 2026-08-20 died with
  `invalid tar header` while the pull-through cache fetched a freshly bumped Grafana tag for
  the first time - the same pull succeeded seconds later. Both pre-pull tasks now retry
  three times. A genuinely missing image still fails.

### Breaking

- **Two new variables have no default, so every existing inventory needs them** before
  `site.yml` will run: `orthanc_db_password` and `orthanc_users` (at least one account).
  The orthanc role's preflight aborts without them.

  Nothing was removed and nothing was renamed - but by the definition this project adopted
  in ADR 0008, enlarging the set of variables that have no default *is* a breaking change,
  because it breaks a deployment that was previously complete. The example vault
  (`ansible/inventory/example/group_vars/linumed/vault.yml.example`) lists both.

  `orthanc_users` is Orthanc's only user store. An empty map with authentication enabled
  locks the instance out of its own REST API, including its healthcheck and the metrics
  scrape - which is why an empty one is refused rather than accepted.

## [0.3.0] - 2026-08-20

The release where the product got its own name, and where the monitoring stack started
observing the one component it had been blind to. No new role.

Two of the defects below were found by a test written *for* the new feature rather than by
the feature itself, and neither was in the feature: one had been silently breaking every
Prometheus configuration change since the monitoring role was written, the other made the
new exporter unreachable. Both are recorded as rules in `CONVENTIONS.md`, because both had
a precedent in this repository that had simply never been carried over.

### Added

- **BridgeLink now reports application metrics to Prometheus** (#60). Until now the only
  BridgeLink data Prometheus held came from cAdvisor - CPU, RAM and network of the
  container. Those cannot distinguish a busy engine from a stalled one: a channel that is
  deployed but stopped, or a destination queue that has stopped draining, looks exactly
  like an idle healthy container. For an HL7/FHIR integration engine that is the failure
  mode that matters most, because it is silent.

  BridgeLink serves no `/metrics` endpoint of its own, so the `bridgelink` role gained a
  small exporter sidecar that queries the engine's REST API: per-channel and per-connector
  state, message counters by outcome, queue depth, JVM heap. Six alert rules ship with it
  in the monitoring role, dormant until the metrics appear (the same pattern as the backup
  rules).

  **Opt-in, and it stays that way**: the exporter authenticates against BridgeLink's own
  user database, which this kit does not manage - that user only exists after the operator
  logs into the Administrator for the first time. Set `bridgelink_exporter_enabled` and
  `monitoring_scrape_bridgelink` together once it does; see `docs/roles/bridgelink.md`.

  Prometheus reaches the exporter by container name over a shared Docker network
  (`linumed-base-metrics`, created by the monitoring role), not over a host port. No port
  is published for it beyond a loopback one for manual debugging. The Node Exporter job's
  `host.docker.internal` arrangement deliberately was not copied: it works only because
  Node Exporter is a native service ufw can protect, and a published container port would
  bypass the firewall (#64). This does mean the monitoring role has to run before the
  bridgelink role on a host - `site.yml` already orders them that way.

  `prometheus-community/json_exporter` was tested first and rejected: BridgeLink's JSON is
  serialised from its XML model, so a single-channel installation renders a list as an
  object and json_exporter's JSONPath silently matches nothing while still reporting the
  scrape as successful. The exporter reads the XML representation instead, which has no
  such ambiguity.

- **`vm-test` now exercises the BridgeLink exporter with the switch on** (#62). The
  existing double-run applies `site.yml` with role defaults, and the exporter defaults to
  off - so it proved the feature is a no-op while disabled, and nothing more. The enable
  path had never run through Ansible at all. A third pass now creates the BridgeLink user
  over the REST API (a throwaway VM has no operator to do it), re-applies with the
  exporter on, and checks the secret's ownership, the container healthcheck,
  `bridgelink_up`, and that Prometheus's new `bridgelink` job is healthy.

  Worth generalising: anything added behind a default-off flag ships with zero coverage
  unless a test deliberately turns it on.

- **Architecture diagrams are pre-rendered SVGs and were redrawn** (#65). The Mermaid
  diagrams in `ARCHITECTURE.md` were rendered by JavaScript in the reader's browser, which
  meant the site's theme reached the MkDocs build and nothing else - the same diagram
  looked different on GitHub and in Forgejo. They are now committed SVGs under `docs/img/`,
  rendered from sources in `docs/diagrams/` by `scripts/render-diagrams.sh`, and identical
  everywhere. The vendored `mermaid.min.js`, its init script and its stylesheet are gone,
  and with them the class-name workaround that only existed to stop the theme from
  fetching a renderer off a CDN at runtime.

  The target-architecture figure was also redrawn, because no amount of theming was going
  to fix it: it drew arrows at the boundary of the Docker group, including one from that
  group to a node inside itself, which renders as a label with no arrow attached. It is now
  two figures - what runs where, and what reports to whom - and the second says more than
  the original did, since the metric paths are actually visible.

  A trade-off worth stating: a static SVG cannot follow the site's light/dark toggle the
  way runtime rendering did. The diagrams render as a light card that stays legible on
  either background, which is the price of looking the same on all three surfaces.

  CI re-renders the diagrams on every docs build and fails if the committed SVGs are out of
  date, so a source edited without re-rendering cannot ship.

### Fixed

- **Prometheus config changes now actually reach Prometheus** (#63). Since the monitoring
  role was written, `prometheus.yml` and `alert-rules.yml` were bind-mounted as individual
  files. A single-file bind mount binds the inode, and Ansible's `template` module writes a
  temp file and renames it into place - creating a new one. The container went on reading
  the orphaned old copy, so **every configuration and alert-rule change after the first
  deploy silently did nothing**: the playbook reported `changed`, validation passed, the
  `/-/reload` handler answered 200, and Prometheus kept running the config from day one.
  Nothing reported an error anywhere.

  Both files now live in `{{ monitoring_deploy_dir }}/prometheus/` and that *directory* is
  mounted, which restores the intended behaviour while keeping the zero-downtime reload.
  The role also removes the two files from their old top-level location, so the next person
  debugging a config that "does not apply" cannot find and edit the copy that no longer
  matters.

  Only Prometheus was affected. Loki, Alloy and Alertmanager are updated by restarting
  their container, and a restart re-resolves the bind mount - it is Prometheus's
  deliberate HTTP reload, chosen for zero downtime, that made it the sole victim. Same
  failure class as the Caddyfile mount in #44/#48; the precedent existed and had simply
  never been applied here.

  **If you deployed an earlier version:** any Prometheus config or alert-rule change you
  made since the first deploy never took effect. The next playbook run applies all of them
  at once.

- **Documented the ownership the BridgeLink secret files actually need** (#60). The role's
  README and the hand-run reference in `docker/bridgelink/` both described
  `secrets/mirth.properties` as root-owned `0600`. A file-based Docker secret keeps the
  host's ownership when it is mounted, and the hardened image runs as UID 65532, so
  following that instruction produces `AccessDeniedException: /run/secrets/mirth_properties`
  and a restart loop - which, because the image supports no healthcheck, Compose still
  reports as a successfully started stack. The Ansible role always set the ownership
  correctly; only the documentation was wrong, and only the manual path was affected.

### Changed

- **The product is now called Linumed Base.** It was released as "Linumed OS" through
  `v0.2.0`; the name was wrong, because this is a collection of Ansible roles that
  configure a standard Debian install, not an operating system, a distribution or a
  bootable image. Renamed while nothing was published and nothing was installed anywhere -
  see ADR 0006 for the full reasoning and for what was deliberately *not* renamed.

  **What this means for you:** identifiers changed with the name. Container names are now
  `linumed-base-*`, the default deploy path is `/opt/linumed-base`, and the shared Docker
  network is `linumed-base-external`. There are no known installations of the earlier
  releases, so no migration path is provided - if you did install `v0.1.0` or `v0.2.0`,
  treat this as a fresh deployment rather than an upgrade.

  Git history and the `v0.1.0` / `v0.2.0` tag messages keep the old name on purpose. Those
  releases happened under it, and rewriting published history to pretend otherwise would
  be dishonest.

### Breaking

- **Every identifier changed with the product's name** (ADR 0006). Containers are
  `linumed-base-*`, the default deploy path is `/opt/linumed-base`, and the shared Docker
  network is `linumed-base-external`. There are no known installations of `v0.1.0` or
  `v0.2.0`, so no migration path is provided - treat an existing one as a fresh deployment
  rather than an upgrade.
- **Prometheus's configuration moved from `{{ monitoring_deploy_dir }}/prometheus.yml` and
  `alert-rules.yml` to `{{ monitoring_deploy_dir }}/prometheus/`** (#63). The role deletes
  the files at the old paths on the next run, so no manual migration is needed - but
  anything referencing the old location, including an operator's own tooling, has to follow
  the move. Edits at the old paths have no effect. This is the same shape of move as the
  Caddyfile in v0.2.0, and for the same underlying reason.

## [0.2.0] - 2026-08-17

Operational maturity rather than new services: the v0.1 role set stayed as it was, and
the gaps a repository audit surfaced got closed - real users instead of shared logins,
tests that verify behaviour instead of configuration, and a restore test that actually
restores.

### Added

- **Tunnel-only SSH users** (`common_ssh_tunnel_users`) - shell-less accounts restricted
  by `sshd` itself to exactly the loopback ports listed, so someone who should read a
  dashboard no longer needs a shell on a machine that processes patient data (#41).
- **Individual Grafana users** (`monitoring_grafana_users`) with Viewer/Editor/Admin
  roles, provisioned through Grafana's HTTP API, replacing the shared admin login as the
  way everyone views dashboards and logs (#42).
- **Optional OIDC for Grafana** (`monitoring_grafana_oidc_*`) pointing at an institution's
  *existing* identity provider. No provider is bundled, and empty settings change nothing
  (ADR 0003, #42).
- **Shared Docker network for Caddy** (`caddy_external_network_name`, default
  `linumed-base-external`) so Caddy can reverse-proxy a container in an operator's own,
  separate Compose stack by service name - without publishing a port or touching ufw
  (#39).
- **Automated weekly restore test** in the `backup` role: restores into a throwaway
  target, diffs against the live source, and reports the result as its own Prometheus
  metrics, with `RestoreTestFailed` and `RestoreTestStale` alert rules. A restore test
  that silently stops running is now as visible as one that fails (#36).
- **VM provisioning and idempotency checks in CI** - a full `site.yml` double-run against
  a real libvirt/KVM VM, not just linting (ADR 0004, #33). Since #45 it triggers itself on changes under `ansible/`, `docker/`, `test/` and `scripts/`.
- **Health checks** for Alertmanager, cAdvisor, docker-socket-proxy and Alloy. All four
  had been assumed impossible; all four turned out to have a working option once actually
  tested. `grafana/loki` remains the single genuine exception (#38).
- **Smoke test for the `docker/` references**, which previously had no coverage of any
  kind (#46, #48).
- **`SECURITY.md`** - private reporting channel, realistic response times, and an
  explicit scope boundary against upstream software (#47).
- **MkDocs documentation site** (Material theme) with a cross-role operations handbook
  under `docs/operations/` (#26).
- **Optional Docker Hub pull-through cache** (`docker_registry_mirrors`) for test runs
  (#43).

### Changed

- **Documentation language is English** (ADR 0002). `ARCHITECTURE.md` and all
  `docs/roles/*.md` were translated; ADR 0001 stays German on purpose, as a record of a
  decision as it was made (#30).
- **`docker/<role>/` is a manual-testing reference, not a required mirror** of the Ansible
  templates - the templates are the single source of truth (ADR 0005, #37).

### Fixed

- **Caddyfile changes never reached the running container after the first deploy.** The
  Caddyfile was bind-mounted as a single file, which attaches to that file's inode, while
  Ansible's `template` module rewrites atomically - so the container kept serving the
  original file forever, with `caddy reload` reporting success and the health check
  staying green throughout. Now the containing directory is mounted instead (#44).
- **The `docker/caddy` reference was left broken by that same fix** - its
  `Caddyfile.example` stayed in the old location, so following the directory's own
  instructions produced a crash-looping Caddy (#48).
- **The osinfo-db in the CI job container predated Debian 12/13**, breaking
  `virt-install` in the VM test workflow (#33).

### Breaking

- **The Caddyfile moved from `{{ caddy_deploy_dir }}/Caddyfile` to
  `{{ caddy_deploy_dir }}/conf/Caddyfile`** (#44). The role deletes the file at the old
  path on the next run, so no manual migration is needed - but anyone who edited that
  file directly, or whose own tooling references the old path, has to follow the move.
  Edits to the old location have no effect.

## [0.1.0] - 2026-08-14

First tagged release. Complete v0.1 role set, each verified against a real Debian 13 VM.

### Added

- **`common`** - SSH hardening (#1), ufw (#3), fail2ban (#10), unattended-upgrades (#5),
  NTP/timezone (#11), and an `ssh.socket` override instead of aborting on socket
  activation (#15).
- **`docker`** - Docker Engine and the Compose plugin from the official repository, as a
  shared prerequisite for every Docker-based role (#17).
- **`caddy`** - reverse proxy with automatic ACME/TLS, Caddyfile generated from
  `caddy_sites`, validated before it takes effect and reloaded without downtime (#6).
- **`monitoring`** - Prometheus, Grafana, Loki, Grafana Alloy, Alertmanager, cAdvisor and
  a native Node Exporter. Only Grafana and Prometheus get a host port, both on loopback
  (#8, #9). Optional Alertmanager SMTP delivery, all-or-nothing (#22); Alloy reaches the
  Docker API only through a read-only socket proxy (#21).
- **`bridgelink`** - HL7 v2 / FHIR R4 integration engine, an MPL-2.0 fork of Mirth
  Connect, which went proprietary in March 2025 (ADR 0001, #12).
- **`backup`** - restic via systemd timer, any restic backend, with the result exported as
  Prometheus metrics (#7).
- **`scripts/bootstrap.sh`** - establishes the `python3`/`sudo` baseline on a minimal
  netinst install, where neither is guaranteed, plus a separate netinst test path
  (#13, #14, #25).
- **Complete example inventory** with an Ansible Vault template (#27, #28).

### Fixed

- **Node Exporter was DOWN in Prometheus on every fresh install** - ufw blocked
  Prometheus's own scrape, and both VM tests stayed green because neither had ever asked
  Prometheus whether its targets were reachable (#40).
- **`.gitignore` had excluded the entire example inventory since the initial commit** -
  every clone got an empty directory (#27).
- **The README quick start ran from the wrong directory**, so `ansible.cfg` was never
  loaded and the first task failed with "role common not found". Every automated test
  implicitly did the right thing, which is why nobody noticed (#29).
