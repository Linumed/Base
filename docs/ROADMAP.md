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
| Caddy cannot reach the operator's own containers - no working path documented | [#39](../../issues/39) |
| CI: run the VM provisioning and idempotency checks, not just lint | [#33](../../issues/33) |
| Suspected: node_exporter scrape blocked by ufw on a fresh install | [#40](../../issues/40) |

[#39](../../issues/39) is the second job `linumed-net` was quietly carrying. Caddy exists to
reverse-proxy the *operator's* applications, and today an application published on
`127.0.0.1` is unreachable from the Caddy container (measured), while publishing on
`0.0.0.0` contradicts the kit's own firewall doctrine. The likely answer is a small opt-in
external network plus an example that actually works - not the shared network that was just
rejected.

[#40](../../issues/40) matters beyond the individual bug: `test/vm-test.sh` verifies that
the playbook runs, not that Prometheus can reach its targets. A green run currently says
nothing about a working scrape.

## Stage 4 - v0.2: access hardening and the operational gaps

With SSO gone, v0.2 gets the content the audit actually surfaced.

| | Issue |
|---|---|
| Tunnel-only SSH users, no shell | [#41](../../issues/41) |
| Real Grafana users plus optional OIDC connection | [#42](../../issues/42) |
| Automate the restore test | [#36](../../issues/36) |

[#41](../../issues/41) and [#42](../../issues/42) close the two genuine weaknesses of the
tunnel model without adding a component. The `sshd` restriction is verified rather than
assumed: an account limited with `PermitOpen` reaches Grafana and is refused Prometheus with
`administratively prohibited`, and `ForceCommand` denies it a shell. That is finer
granularity than a proxy-level login would have given.

[#36](../../issues/36) stays because `ARCHITECTURE.md` calls recovery tests a GDPR
requirement, and this is the last release at which it can still be part of v0.2 rather than
a permanent "later".

[#35](../../issues/35) - re-measuring the system requirements - is closed along with the
Authentik role: without four additional containers there is nothing to re-measure. It
returns if the stack grows.

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
  started, no issues. Passpin is a separate product and is not developed in this repository.
- **A bundled identity provider, a shared `linumed-net`, or a mesh-VPN role.** All three
  evaluated and rejected on 2026-08-14, see
  [ADR 0003](adr/0003-loopback-only-access-no-bundled-identity-provider.md). Connecting
  Grafana to an *existing* provider via OIDC is in scope ([#42](../../issues/42)); shipping
  one is not.
- **Application software** (HIS, DMS, document management). Out of scope by design.
  Institutions bring their own applications; Linumed OS provides the secure base.
- **Kubernetes, bootable images, PXE.** Excluded by `CLAUDE.md`, not revisited here.
