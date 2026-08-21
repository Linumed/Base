# ADR 0008: What the v1.0 stability guarantee covers

**Status:** accepted · **Date:** 2026-08-20, surface re-measured 2026-08-21 (#73) · **Affects:** every role; `ARCHITECTURE.md`; `CONVENTIONS.md`; issues #66, #71, #73

## The question answered here

Until 2026-08-20, `ARCHITECTURE.md` said "breaking changes only from v1.0 onward". That
was backwards for a 0.x project and the repository had already broken it twice - v0.2.0
moved the Caddyfile, v0.3.0 renamed every identifier. The sentence was corrected to say
what Semantic Versioning actually means: before 1.0 there is no stability guarantee, and
from 1.0 a breaking change requires a major version bump.

That fixed **when** the promise starts. It left open **what it applies to**, which is the
part that matters. A version number is not a promise on its own; the promise is "these
specific things will not change under you". Without writing that down, tagging 1.0 means
committing to an obligation of unknown size - and unlike a bug, an over-broad promise
cannot be quietly fixed later.

## Context

The surface was measured rather than estimated. The figures below were re-measured on
2026-08-21 (issue #73); the "was" column is the original 2026-08-20 measurement, kept
because the size of the drift in one day is itself the argument for re-measuring before
the tag rather than after.

| Surface | Size (2026-08-21, seven roles) | Was (2026-08-20, six roles) |
|---|---|---|
| Role variables in `defaults/main.yml` | **138** interface + 8 internal, seven roles | 125 across six, no split |
| Container names (`linumed-base-*`) | **13** | 11 |
| Shared Docker networks | 2 (`linumed-base-external`, `linumed-base-metrics`) | 2 |
| Deploy paths | `/opt/linumed-base/{caddy,bridgelink,monitoring,`**`orthanc`**`}` | three of them |
| Metrics from this kit's own exporters | `bridgelink_*`, `backup_*`, `restore_test_*` | unchanged |
| Alert rule names | **16** | 13 |
| systemd units | 4 (`backup`, `restore-test`, each `.service` and `.timer`) | 4 |
| Variables a plain `site.yml` run aborts without | **9** | "6 with no default" |
| Grafana dashboard and datasource UIDs | 3 dashboards, plus `prometheus` and `loki` | unchanged |
| Docker volume names | **11**, project-derived rather than `linumed-base-*` | 9 |

Three of those rows need a word beyond the number.

**The variable count was never 125.** The pattern used to count them missed every name
containing a digit, which is all seven `common_fail2ban_*` - so the 2026-08-20 figure was
low for the six roles it claimed to cover, before Orthanc added 18 more. Correctly counted,
those six roles held **129**, the seven held 147 when the audit ran, and **146** after #75
removed the one variable nothing read. A measurement that is wrong in the same direction as
the estimate it replaced is worth naming, because the point of measuring was to stop
guessing.

**Orthanc adds no metric names of this kit's own.** It serves
`/tools/metrics-prometheus` natively, so the names on that endpoint are upstream's and
change when Orthanc changes - this kit neither owns nor can promise them. What this kit
does own are the three alert rules built on top (`OrthancDown`, `OrthancErrorRate`,
`OrthancJobsStuck`), and those are in the count above. The distinction matters for anyone
reading the "own exporters" row as "all metrics you will see".

**"Vault variables with no default" was not a measurable category.** Every one of them has
a default - the empty string, or `{}` for `orthanc_users`. What the row meant is the thing
an operator actually feels: a plain `site.yml` run aborts in preflight without it. Measured
that way it is nine (`backup_repository`, `backup_restic_password`, `bridgelink_db_password`,
`bridgelink_keystore_keypass`, `bridgelink_keystore_storepass`, `bridgelink_server_id`,
`monitoring_grafana_admin_password`, `orthanc_db_password`, `orthanc_users`). A further ten
are asserted only once an opt-in switch arms them - the BridgeLink exporter, Alertmanager
SMTP, Grafana OIDC - and are deliberately not counted here, because they cannot stop a
default deployment.

Not all of these are equally exposed. The distinguishing question is not "is it visible?"
but **"can an operator have built something on it that silently stops working?"** Two
examples make the line concrete:

- `linumed-base-external` exists precisely so that an operator's own, separate Compose
  stack can join it by name (ADR 0003, issue #39). Renaming it breaks that stack with no
  error from this kit at all.
- The Grafana **datasource** UIDs `prometheus` and `loki` are referenced by every panel in
  any dashboard the operator builds themselves. That surface was nearly missed when
  drawing up this list, which is a good illustration of why it had to be measured.

## Options considered

**Promise nothing specific, tag 1.0 anyway.** Rejected. That is what the old sentence
effectively did, and it is worse than no promise: readers assume the ordinary meaning of
1.0 and are then surprised.

**Promise everything in the repository.** Rejected. It would freeze pinned image versions,
which must move - issue #67 exists precisely to keep them moving - and internal task names
nobody depends on. A promise that cannot be kept is not a promise.

**Name the surface explicitly (chosen).** Slower to write, but it is the only version that
can be checked before a release rather than argued about after one.

## Decision

From `v1.0.0`, a change to any of the following requires a **major** version bump, and is
called out under `### Breaking` in `CHANGELOG.md`:

1. **Role variable names, their meaning and their type.** Removing one, renaming one, or
   changing what it does.
2. **Deploy paths** under `/opt/linumed-base/`. Operators back these up and point their own
   tooling at them; v0.3.0 broke this twice and both were real breaks.
3. **Container names and shared network names.** These are documented integration points.
4. **Metric names emitted by this kit's own exporters** - `bridgelink_*`, `backup_*`,
   `restore_test_*` - including their label names. Dashboards and alerts get built on them.
5. **Alert rule names.** Operators route on them in Alertmanager.
6. **Grafana dashboard UIDs and datasource UIDs.** They appear in URLs and in every
   operator-built panel.
7. **systemd unit names.** Operators write drop-in overrides against them.
8. **Docker volume names.** They hold the data, and an operator's own backup or migration
   tooling addresses them by name. Note they are *not* `linumed-base-*` - Compose derives
   them from the project, so they are `monitoring_prometheus_data`,
   `bridgelink_bridgelink_db_data` and so on. This item was missing from the first version
   of this list and was found by the teardown test in #68, which is a second illustration
   of why the surface had to be measured rather than recalled.
9. **The set of variables that have no default** - the nine a plain run aborts without,
   re-measured 2026-08-21 (#73); this said "the six vault variables" until then, against
   this ADR's own table. Adding a
   seventh breaks every existing inventory, so it is a breaking change even though nothing
   was removed.

### Explicitly not covered

- **Pinned image versions.** They have to move, and the weekly scan (#67) exists to make
  them move. A version bump of an upstream component is never a breaking change of this
  kit, even when the upstream itself breaks something - that belongs in `### Changed` with
  a warning, not in the major number.
- **Default *values*, with one restriction:** a changed default is not automatically a
  major bump, but it must appear under `### Breaking` if it changes behaviour on an
  existing host. Image pins are exempt from even that, or every scan result would produce
  a changelog entry.
- **Internal structure:** task names, handler names, file layout inside a role, template
  organisation.
- **Documentation wording and structure**, including this file.
- **Anything upstream owns:** log formats, Grafana's own UI, BridgeLink's API.

## Consequences

**Adding a role gets harder, deliberately.** Every new variable is a promise from the
moment 1.0 is tagged. That is the intended effect: it forces the naming question to be
answered before release rather than regretted after.

**Some changes become impossible until 2.0.** If a variable turns out to be badly named,
it stays. The mitigation is to fix such things *before* 1.0, which is the point of the
next section.

**138 variables is a large promise.** It is the honest size of the current surface, and
naming it is better than discovering it later. Whether every one of them deserves to be
covered is a question for the pre-1.0 audit, not for this decision - the default is that
they are covered, and taking one out requires saying so.

## Before tagging 1.0

The guarantee freezes whatever exists at that moment, so the work before the tag is
removal, not addition:

- ~~**Audit the 125 variables**~~ **Done (#71, 2026-08-21).** Of the 147 variables the audit
  measured, exactly one is read by nothing - `monitoring_grafana_analytics_enabled`, removed
  in #75, leaving 146. There is no removal list beyond it.

  **This ADR named `monitoring_retention_days` as the known example of dead weight, and
  that was wrong.** The measurement contradicts it: the variable is read in both templates
  that need it (`loki-config.yml.j2`, `docker-compose.yml.j2`), documented twice in
  `docs/roles/monitoring.md` including the warning that it overrides *both* retention
  values at once, and used by `CONVENTIONS.md` as the example of the naming convention. It
  is a working, documented shortcut for the common case, not a dangling remnant. Removing
  it would cost a breaking change and a documentation example to save one line. It stays.

  The error is worth leaving visible rather than editing away: this ADR argued for
  measuring instead of estimating, and then estimated this one item from memory.
- ~~**Decide whether any variables are internal**~~ **Done (#72, 2026-08-21):**
  [ADR 0010](0010-internal-versus-interface-variables.md). Eight are - the two `*_uid`/`*_gid`
  pairs and the two `*_db_name`/`*_db_user` pairs - listed in `ansible/internal-variables.txt`
  with a reason each. The promise is therefore 138 interface variables, not 146.

  The premise this item was written on was wrong: Ansible *does* have a mechanism
  (`vars/main.yml` outranks inventory `group_vars`, measured). It is deliberately not used,
  because it enforces by discarding an operator's input in silence - the failure mode of
  #44, #63 and #78. `scripts/check-variable-docs.py` enforces in CI instead, where it can be
  loud, and also checks the cross-role literals that until now were held together by nothing
  but a comment saying "must match".

  The rule this item asked for is now stated: for the 13 `*_image` variables, **the value
  moves, the name does not.**

- ~~**Close the lifecycle questions (#68).**~~ **Done 2026-08-20.** Promising stability
  while being unable to say what happens at a Debian major upgrade is a promise about the
  wrong thing.

## When to revisit this decision

- **A surface turns out to be missing from the list.** Add it - the list is meant to be
  complete, and finding a gap before 1.0 is a success, not a failure.
- **After 1.0, if an item proves too expensive to keep.** That is a 2.0 conversation and
  belongs in its own ADR, not in a quiet edit here.

## Sources

- Issue #66 - the gap this closes
- [ADR 0003](0003-loopback-only-access-no-bundled-identity-provider.md) - why
  `linumed-base-external` is an integration point rather than an implementation detail
- [ADR 0006](0006-linumed-base-not-linumed-os.md) - the v0.3.0 rename, and the reasoning
  for why it was acceptable then and would not be after 1.0
