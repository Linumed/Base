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

## Stage 3 - The access model, which is a decision and not a task

`ARCHITECTURE.md` describes a shared `linumed-net` as the target picture, and it does not
exist. That much is fact. But calling it an unfinished task would misrepresent the
history.

**On 2026-08-10 the opposite was decided, deliberately.** Asked how Grafana should be
reachable, the choice was "loopback only, access via SSH tunnel". The alternative on the
table was "via Caddy, with a subdomain", described at the time as requiring a shared
Docker network, making Grafana's own auth the single protective layer, and needing a
ufw/GDPR trade-off because Loki logs can contain personal data. A configurable middle
ground (`monitoring_expose_via_caddy`) was rejected as well. BridgeLink then followed the
same pattern: admin port on loopback, channel ports not published at all.

So `linumed-net` was never rejected as a technique - the use case that would have needed
it was. Today every component of Linumed OS is reachable only through an SSH tunnel into a
hardened host, and Caddy proxies nothing by default (`caddy_sites: []`); it is there for
the operator's own applications.

| | Issue |
|---|---|
| Revisit the access decision, then either build `linumed-net` or delete it from the docs | [#31](../../issues/31) |
| Caddy route to BridgeLink - or delete it from the diagram | [#32](../../issues/32) |
| CI: run the VM provisioning and idempotency checks, not just lint | [#33](../../issues/33) |

The open question is therefore not "when do we build the shared network" but **whether the
v0.1 access decision still holds**. If it does, `linumed-net` and the planned Caddy route
should be struck from `ARCHITECTURE.md` rather than implemented, so the target picture
stops promising something that was consciously not wanted. If it does not hold, the reason
belongs on record first - and that reason is a requirement about multi-user access for
service providers, not a networking detail.

[#33](../../issues/33) is independent of that and can proceed either way.

## Stage 4 - v0.2, SSO via Authentik

| | Issue |
|---|---|
| `authentik` role, preceded by an integration-pattern ADR | [#34](../../issues/34) |
| Re-measure the system requirements table | [#35](../../issues/35) |
| Automate the restore test | [#36](../../issues/36) |

**This stage is conditional on Stage 3, and may not survive it.** If everything stays
behind the SSH tunnel, SSO protects services that nobody can reach without an SSH key on a
hardened host in the first place - four additional containers for no security gain. SSO
only becomes meaningful if the services are meant to be reachable without a tunnel, which
is precisely the decision taken the other way on 2026-08-10. Deciding that consciously is
the prerequisite; if it stays as it is, v0.2 needs different content and the strongest
candidates are already filed ([#36](../../issues/36), [#33](../../issues/33),
[#26](../../issues/26)).

Two further things to settle before any code is written:

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
