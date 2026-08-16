# ADR 0005: `docker/` is a manual-testing reference, not a required mirror

**Status:** accepted · **Date:** 2026-08-16 · **Affects:** `docker/`, `CLAUDE.md`, issue #37

## The question answered here

`CLAUDE.md` said "one Compose file per service stack under `docker/`" as if it were a
hard rule. Two of six Docker-based roles have one (`caddy`, `bridgelink`); `monitoring`
never got one; `backup` was named as missing in issue #37 even though it isn't Docker at
all. The rule existed, wasn't followed, and nothing said whether that was a bug or the
actual intent. This records which it is.

## Context

Every Docker-based role already templates its own `docker-compose.yml.j2` under
`ansible/roles/<role>/templates/` - that file is what `site.yml` actually deploys, with
secrets, generated config and Ansible variables wired in. `docker/caddy/` and
`docker/bridgelink/` exist *in addition* to that: a static, `.env`-driven version of the
same stack, meant for spinning a service up by hand without Ansible, for local
smoke-testing during development.

**Checked before deciding, not assumed:** the two existing pairs have not actually
drifted. `docker/caddy/docker-compose.yml`'s image tag matches
`caddy_image` in `ansible/roles/caddy/defaults/main.yml`
(`caddy:2.11.4-alpine`), and the same holds for both of `docker/bridgelink/`'s images.
The files are not identical - the Ansible-managed one carries Jinja variables and
Ansible-specific comments the static one doesn't - but the parts that matter for a
hand-test (image versions, port bindings, volume layout) still match.

**`backup` was named as a gap it isn't.** The `backup` role installs `restic` as a native
Debian package via `apt` - there is no Docker Compose stack in that role at all, and
therefore nothing a `docker/backup/` directory could mirror. Naming it as missing was a
category error in how the original rule was read, not a real gap.

**What a real `docker/monitoring/` would cost.** The monitoring role deploys seven
containers (Prometheus, Grafana, Loki, Alloy, Alertmanager, cAdvisor,
docker-socket-proxy) with several secrets (Grafana admin password, optional Alertmanager
SMTP credentials) and cross-service wiring (Prometheus's Alertmanager target, Loki's
retention compactor, Alloy's discovery config). An `.env`-driven parallel version would
need to reproduce all of that by hand, and - unlike `caddy`/`bridgelink`, which are
comparatively simple, mostly-static stacks - would need real, ongoing attention every
time the role's own template changes, or it silently becomes the exact kind of stale
reference this ADR is trying to prevent.

## Options considered

**A · Complete `docker/` for every Docker-based role, add drift protection.** Keeps the
original rule's promise. Rejected: `backup` has nothing to mirror, so "every role" is not
even a coherent target. For `monitoring`, the cost (duplicate secrets handling, ongoing
sync burden for a single-maintainer repository) is real and recurring, for a reference
whose value is "can smoke-test without Ansible" - useful, but not something worth a
standing maintenance tax on the most complex role in the repo. Drift protection itself
(a test comparing the rendered template against the static file) is nontrivial to build
well, precisely because the two are deliberately not byte-identical - it would need
normalization logic to compare only the parts that should match, which is its own
maintenance surface.

**B · Narrow the convention to what's actually true.** `docker/<role>/` is documented as
an optional, manually-maintained testing convenience for roles where the maintainer
judged it worth building, not a contractual mirror every role must have. The Ansible
template is unambiguously the source of truth. Chosen.

**C · Delete `docker/caddy/` and `docker/bridgelink/` entirely, keep only the Ansible
templates.** Removes the drift risk by removing the duplication. Rejected: both existing
references are current, used (their own role READMEs describe them as the way to
smoke-test locally), and cost nothing to keep as-is - deleting working, non-drifted
documentation to avoid a hypothetical future drift is overcorrection.

## Decision

`docker/<role>/`, where it exists, is a hand-maintained reference for manual testing -
not a required mirror of every Docker-based role, and not guaranteed to track every
detail of the Ansible-managed version. `ansible/roles/<role>/templates/docker-compose.yml.j2`
is unambiguously the source of truth for what actually gets deployed.

Kept as-is: `docker/caddy/`, `docker/bridgelink/` - both current, both worth keeping.

Not built: `docker/monitoring/`, `docker/backup/` (the latter doesn't apply - no Compose
stack in that role). No drift-detection tooling.

**What "keep in sync" means going forward for the two that exist:** when a role's
`defaults/main.yml` image pin changes, update the matching `docker/<role>/` file in the
same change if it's a small edit - don't chase every comment or structural change the
Ansible side picks up along the way. If the two ever do drift and nobody notices for a
long stretch, that is evidence the reference has stopped being useful and should be
deleted (option C), not evidence that automated drift protection was needed all along.

## Consequences

**Accepted downsides.**

- A newcomer running `docker/caddy/docker-compose.yml` by hand gets a slightly less
  documented experience than the Ansible-deployed version (fewer inline comments
  explaining *why*, since those accumulate on the Ansible side as issues get fixed).
- No automated guarantee the two stay in sync. The next image bump might update one and
  forget the other, and nothing will flag it until someone notices by hand.
- `monitoring` and any future complex, multi-secret role will likely never get a
  `docker/<role>/` reference, even though it could theoretically be useful for
  troubleshooting.

**What this doesn't change.** Both existing `docker/<role>/` directories keep the rules
that always applied to them: pinned image tags, named volumes, health checks,
`.env.example`. This ADR only removes the expectation that every role needs one.

### When to revisit this decision

- **A `docker/<role>/` file goes stale and causes real confusion** (someone follows it,
  gets a version that doesn't match what's actually deployed). That's the signal to
  either fix the sync process for real or delete the file - not to build drift-detection
  tooling preemptively.
- **A future role is simple enough** (few secrets, little cross-service wiring) that a
  `docker/<role>/` reference would cost little to add and maintain - add one then, on
  that role's own merits, not because of a blanket rule.
- **The project stops being solo-maintained.** The maintenance-cost argument in this ADR
  is explicitly about a single maintainer's time; a team might reasonably decide the
  completeness guarantee is worth the recurring cost.

## Sources

- Issue #37 - the original finding that started this.
- `ansible/roles/caddy/README.md`, `ansible/roles/bridgelink/README.md` - already
  describe their `docker/<role>/` counterpart as a manual-testing reference; this ADR
  makes that description the repo-wide rule instead of a per-role note.
