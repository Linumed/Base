# ADR 0010: Internal variables are a documented list, not an enforced one

**Status:** accepted · **Date:** 2026-08-21 · **Affects:** every role; `CONVENTIONS.md`; [ADR 0008](0008-what-the-v1-0-stability-guarantee-covers.md); issue #72

> **2026-08-23:** several worked examples below use `orthanc_*` variables. The `orthanc`
> role they belonged to was removed in #92/[ADR 0011](0011-orthanc-removed-not-part-of-base.md).
> The principle this ADR establishes is unaffected; the examples and the counts derived
> from them (e.g. "27 variables", "three legs") describe the six-role kit as it stood on
> 2026-08-21 and are left as written rather than restated for the current role set.

## The question answered here

[ADR 0008](0008-what-the-v1-0-stability-guarantee-covers.md) settled *what* the v1.0
promise covers and stated the default plainly: "the default is that they are covered, and
taking one out requires saying so." It left one thing open, because it could not be decided
without looking at the variables one by one - **are all of them really interface?**

All 146 role variables live in `defaults/main.yml`, which means all 146 are overridable and
all 146 are promised. Some of them are neither meant to be set nor safe to set:
`orthanc_uid` is dictated by the container image, and a different value produces the
restart loop issue #61 documented. Freezing that name until 2.0 promises something nobody
asked for.

This ADR draws the line, and — the harder half — decides **how the line is held**.

## Context

Two premises the issue started from turned out to be wrong, and both are worth recording
because either one would have produced a different, worse decision.

**"Ansible has no visibility mechanism" is false.** `vars/main.yml` outranks inventory
`group_vars` and `host_vars`; only `-e` extra-vars and role parameters beat it. Measured,
not read: a role variable moved there ignores an inventory value that would have overridden
it in `defaults/`. So enforcement was genuinely available, and the decision below is a
choice rather than a limitation.

**The count of undocumented variables was wrong.** An audit (#71) put it at 30 by searching
for each name in the role's own documentation page. That search cannot see the space-saving
forms the pages actually use — `backup_retention_keep_daily/weekly/monthly` is one row for
three variables, and `monitoring_alertmanager_group_wait` / `_group_interval` is one row for
two. Nor does it account for a variable being documented where an operator *sets* it rather
than where it is defined: the `monitoring_orthanc_*` credentials are documented on the
Orthanc page, which is the right place for them. Measured properly, 27 variables were
undocumented, of which 19 remained after the image pins were credited to
`docs/operations/updates.md`.

That second error is the reason this ADR ships with a script rather than only a list. A
classification produced by a search that was wrong once will be wrong again.

## The test

Taken unchanged from ADR 0008, because a second test would mean two lines that can drift:

> **Can an operator have built something on it that silently stops working?**

A variable is internal only when the answer is no *for a concrete reason* — the value is
dictated by something outside this repository, or changing it on an existing host breaks
that host with no migration path. "Nobody would want to change this" is not such a reason.
It is a guess about operators, and ADR 0008 already decided which way to guess.

Applied, eight variables are internal:

| Variables | Why they fail the test |
|---|---|
| `bridgelink_uid`, `bridgelink_gid`, `orthanc_uid`, `orthanc_gid` | The images run as UID/GID 65532 and the bind-mounted data must be owned by it. A different value is the #61 restart loop, in which the container dies without a useful error. |
| `bridgelink_db_name`, `bridgelink_db_user`, `orthanc_db_name`, `orthanc_db_user` | PostgreSQL runs inside each role's own Compose stack with no host port. Changing either on an existing host points the application at a database that does not contain its data — no migration path, no test. |

Everything else stays interface. Notably **the 13 `*_image` variables stay**, and a rule
that was implied but never written falls out here: **the value moves, the name does not.**
ADR 0008 excludes pinned image *versions* from the guarantee and #67 exists to keep them
moving — but the variable name is how an operator points this kit at their own registry or
mirror, and that must survive a minor release.

## Options considered

**A naming convention (`_internal_` prefix or a leading underscore).** Rejected: it renames
13-plus variables, which is itself a breaking change, costs `CONVENTIONS.md`'s naming
example, and enforces nothing — a renamed variable is exactly as settable as before.

**`vars/main.yml`.** Rejected, and this is the decision worth arguing, because it is the
only option that genuinely enforces.

It enforces by **discarding the operator's input in silence**. Someone who sets
`orthanc_uid` in their inventory gets no error, no warning, and no effect. That is not a
hypothetical objection in this repository: `docs/operations/troubleshooting.md` already
carries a section called "I changed a variable and nothing happened", warning operators
about precisely this shape of failure. And it is the shape this project has paid for three
times — a Caddyfile bind mount that silently stopped applying (#44), Prometheus
configuration changes that never reached the container while every signal stayed green
(#63), a release tag that never moved while the artefact behind it was rebuilt four times
(#78). Each was written up with the same sentence: a green signal over changed content.

A kit whose recurring lesson is "no silent success" should not install that failure mode on
purpose. Least of all against a risk that has not materialised: **none of the eight is set
anywhere today** — not in the example vault, not in the eleven host vars
`test/lib/site-idempotency.sh` writes, not in the four `-e` flags
`test/lib/bridgelink-exporter-check.sh` passes.

There is also no way to soften it. Ansible discards variable provenance —
`ansible/vars/manager.py` accepts a `source` argument in `_combine_and_track` and throws it
away, with the comment `# FIXME: this no longer does any tracking`. A preflight therefore
cannot ask "did this value come from the inventory?" and cannot turn the silence into a
loud refusal.

## Decision

**A documented list, checked in CI. No mechanism at runtime.**

1. `ansible/internal-variables.txt` holds the eight names, each with the reason it is not
   interface. Same shape and same purpose as `security/accepted-image-findings.txt`: not a
   way to hide something, a record that someone looked, decided, and said so.
2. `scripts/check-variable-docs.py` fails when a variable is neither documented under
   `docs/` nor on that list, when it is on both, when a listed name no longer exists in any
   role, or when an entry has no reason. It runs on every push.
3. A comment at each internal variable in `defaults/main.yml` says so and points here.

Enforcement moves to where it can be **loud**. A CI failure names the variable and the file;
a precedence trick names nothing.

The same script also checks the couplings that nothing checked before. There are **no
cross-role variable reads in this kit**: not one variable is dereferenced outside the role
whose `defaults/main.yml` defines it. Every cross-role relationship is instead a value
duplicated into a second variable with a comment saying "must match":
`monitoring_metrics_network_name`, `bridgelink_exporter_metrics_network` and
`orthanc_metrics_network` are three legs of one frozen constant, as are
`monitoring_node_exporter_textfile_dir` and `backup_textfile_dir`. The script compares the
literals. A comment is not a gate.

That this is a *convention* and not something Ansible enforces was measured after an
earlier draft of this ADR claimed the opposite. Variables from **every** role in a play are
visible to every other role in that play — role defaults and `vars/` alike, and regardless
of role order (ansible-core 2.19.4, verified with a two-role playbook). What `vars/` changes
is precedence, not visibility. So the roles could read each other's variables directly; they
deliberately do not, because a role that reaches into another role's namespace stops being
deployable on its own — which is the property `ansible/playbooks/node-baseline.yml` exists
for (#70).

For the same reason the coupled variables are **not** merged into one. A shared variable
needs a shared home — `group_vars`, which takes it out of the role, or a `meta` dependency,
which breaks `dependencies: []`. Both cost more than a duplicated literal does now that a
check watches it.

## Consequences

- **Being listed does not make a variable unsettable.** An operator who sets one still gets
  what they asked for. What they do not get is a promise that the name survives to 2.0.
  That is a weaker guarantee than `vars/` would give, and it is the point: the failure mode
  is a documented surprise, not a silent one.
- **The promise shrinks by eight**, from 146 variables to 138 interface variables plus 8
  recorded internal. Nothing was renamed, removed, or changed in behaviour, so this is not
  a breaking change.
- **Eleven variables gained documentation** they should have had already, among them
  `orthanc_metrics_network` — two of the three legs of the metrics-network constraint were
  documented and the third was not.
- **`CONVENTIONS.md` no longer says all role variables are covered.** It said so flatly;
  after this ADR it points here for the exception.
- **A new file must be maintained.** That is real cost, and it is why the script checks the
  list against reality rather than trusting it — the same reason
  `accepted-image-findings.txt` is machine-read rather than read by people.
- **`CONVENTIONS.md`'s "do not document what is obvious from the code" is narrowed**, not
  broken: what v1.0 freezes is by definition no longer only code. An operator cannot be
  expected to read `defaults/main.yml` to discover what they are promised.

## When to revisit this decision

- **If an operator actually sets one of the eight and is surprised.** That is the evidence
  this ADR lacks, and it would argue for `vars/` after all — with the silence accepted
  deliberately rather than by omission.
- **If the list grows past roughly a dozen.** At that size "internal" stops being a handful
  of exceptions and starts being a second interface, which deserves its own structure.
- **If Ansible gains variable provenance.** A preflight that could say "you set
  `orthanc_uid`, which is internal — remove it" would beat both options here, because it
  enforces *and* speaks.

## Sources

- [ADR 0008](0008-what-the-v1-0-stability-guarantee-covers.md) — what the guarantee covers,
  and the test reused above
- `docs/operations/troubleshooting.md`, "I changed a variable and nothing happened"
- Issues #44, #63, #78 — the silent-success failures this decision is shaped by
- Issue #71 — the variable audit, including the miscount corrected above
