# ADR 0008: What the v1.0 stability guarantee covers

**Status:** accepted · **Date:** 2026-08-20 · **Affects:** every role; `ARCHITECTURE.md`; `CONVENTIONS.md`; issue #66

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

The surface was measured rather than estimated (2026-08-20):

| Surface | Size |
|---|---|
| Role variables in `defaults/main.yml` | 125 across six roles |
| Container names (`linumed-base-*`) | 11 |
| Shared Docker networks | 2 (`linumed-base-external`, `linumed-base-metrics`) |
| Deploy paths | `/opt/linumed-base/{caddy,bridgelink,monitoring}` |
| Metrics from this kit's own exporters | `bridgelink_*`, `backup_*`, `restore_test_*` |
| Alert rule names | 13 |
| systemd units | 4 (`backup`, `restore-test`, each `.service` and `.timer`) |
| Vault variables with no default | 6 |
| Grafana dashboard and datasource UIDs | 3 dashboards, plus `prometheus` and `loki` |

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
8. **The set of variables that have no default** - the six vault variables. Adding a
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

**125 variables is a large promise.** It is the honest size of the current surface, and
naming it is better than discovering it later. Whether every one of them deserves to be
covered is a question for the pre-1.0 audit, not for this decision - the default is that
they are covered, and taking one out requires saying so.

## Before tagging 1.0

The guarantee freezes whatever exists at that moment, so the work before the tag is
removal, not addition:

- **Audit the 125 variables** for ones that should not be carried forever.
  `monitoring_retention_days` is the known example: an escape hatch that exists only so
  that a variable name from an earlier documentation draft would not point at nothing. It
  is dead weight today and a permanent obligation after 1.0.
- **Decide whether any variables are internal** rather than part of the interface. There is
  no visibility mechanism in Ansible, so this needs a naming convention or an explicit list -
  and it has to exist before the freeze, not after.
- **Close the lifecycle questions (#68).** Promising stability while being unable to say
  what happens at a Debian major upgrade is a promise about the wrong thing.

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
