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

So the honest description is: **the roles work, the product does not yet onboard anyone.**
That is what Stage 1 fixes, and it is why SSO is not next despite `ARCHITECTURE.md` naming
it as v0.2.

## Stage 1 - Operability, ending in the v0.1.0 tag

Nothing here is a new feature. This stage makes the claim already published in the README
("feature-complete and verified") true from an operator's point of view.

| | Issue |
|---|---|
| Complete the example inventory, fix the quick start | [#27](../../issues/27) |
| Document the Ansible Vault workflow, add an example vault | [#28](../../issues/28) |
| Tag `v0.1.0` | [#29](../../issues/29) |

**Acceptance for the stage, not just the issues:** one deployment against a fresh VM
performed strictly from the README, without repository knowledge. Not a code review, an
actual run. Only then does the tag get set - a tag someone can check out and not put into
service is worse than no tag.

## Stage 2 - Documentation foundation

`CLAUDE.md` has required MkDocs from the beginning; there is no `mkdocs.yml`. The
documentation sources exist and are good, but nothing builds or navigates them.

| | Issue |
|---|---|
| MkDocs setup and operations handbook | [#26](../../issues/26) |
| Translate the existing German docs per ADR 0002 | [#30](../../issues/30) |

The language question was settled first, deliberately: writing the operations handbook in
German and then internationalising would mean writing it twice. See
[ADR 0002](adr/0002-english-as-documentation-language.md).

## Stage 3 - Network architecture, the SSO prerequisite

`ARCHITECTURE.md` describes a shared `linumed-net` as the target picture. It does not
exist; every Compose stack has its own isolated network, and the `caddy` role's defaults
say so explicitly ("not automated by this role yet").

| | Issue |
|---|---|
| Introduce `linumed-net`, refactor caddy/monitoring/bridgelink onto it | [#31](../../issues/31) |
| Caddy route to BridgeLink - or delete it from the diagram | [#32](../../issues/32) |
| CI: run the VM provisioning and idempotency checks, not just lint | [#33](../../issues/33) |

**This is the actual blocker for v0.2.** Authentik integration - whether native OIDC or
`forward_auth` - requires Caddy to reach both the identity provider and the protected
service. Neither is possible while the stacks are isolated from each other. Building the
SSO role first would mean building it against a topology that does not exist yet.

[#31](../../issues/31) needs an ADR before implementation: today's "publish nothing, bind
everything to `127.0.0.1`" default is what defuses the Docker-bypasses-ufw trap, and a
shared network changes reachability between stacks. That trade-off gets written down, not
decided in passing.

[#33](../../issues/33) belongs here rather than in Stage 1 because Stage 3 is the first
change that touches every Docker role at once - exactly the kind of refactor where a
manual test run is the wrong safety net.

## Stage 4 - v0.2, SSO via Authentik

| | Issue |
|---|---|
| `authentik` role, preceded by an integration-pattern ADR | [#34](../../issues/34) |
| Re-measure the system requirements table | [#35](../../issues/35) |
| Automate the restore test | [#36](../../issues/36) |

Two things to settle before any code is written:

**Licensing.** FOSS-only is a hard constraint. Authentik has enterprise features behind a
commercial licence, and it has to be established - not assumed - that everything needed
here is in the free edition. If it is not, the premise of v0.2 falls and Keycloak/Zitadel
belong in the same ADR.

**Integration pattern per service.** Grafana speaks OIDC natively. Prometheus, Alertmanager
and cAdvisor have no authentication at all and can only be covered by `forward_auth` in
front of the proxy. BridgeLink ships its own user management, and whether the Mirth
codebase speaks OIDC needs checking rather than assuming - its Java admin client does not
do browser-based auth, which may rule `forward_auth` out for that path.

[#35](../../issues/35) is not bookkeeping: the README table is explicitly "measured, not
estimated", and Authentik adds four containers. Leaving it stale would quietly downgrade a
measured commitment into a guess.

[#36](../../issues/36) sits here because `ARCHITECTURE.md` calls recovery tests a GDPR
requirement, and Stage 4 is the last point at which it can still be called part of the v0.2
release rather than a permanent "later".

## Open convention questions

These are not blocked by anything and can be picked up whenever. Both are cases where the
repository states a rule it does not follow, which is worse than either following it or
changing it.

| | Issue |
|---|---|
| `docker/` holds only two of four stacks - complete it or narrow the rule | [#37](../../issues/37) |
| The healthcheck rule is ambiguous; four services have none | [#38](../../issues/38) |

## Deliberately not on this roadmap

- **v0.3 (Orthanc/DICOM)** and **Linumed Passpin** - named in `ARCHITECTURE.md`, no work
  started, no issues. Passpin is a separate product and is not developed in this
  repository; it will eventually replace the Authentik role.
- **Application software** (HIS, DMS, document management). Out of scope by design.
  Institutions bring their own applications; Linumed OS provides the secure base.
- **Kubernetes, bootable images, PXE.** Excluded by `CLAUDE.md`, not revisited here.
