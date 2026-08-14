# ADR 0002: English as the documentation language

**Status:** accepted · **Date:** 2026-08-14 · **Affects:** `docs/`, `README.md`, `ARCHITECTURE.md`, `CLAUDE.md`, issue #26

## The question answered here

Linumed is a German company selling a German product (Linumed Shifts) into German
clinics. Writing the documentation of its open-source infrastructure kit in English
looks, from the outside, like a mistake or like affectation. This records why it is
neither.

## Context

Two facts collide.

**Linumed OS is not German in substance.** It is a hardened Debian with Ansible and
Docker. Debian is an international operating system, the GDPR is EU-wide rather than
German, and nothing in the roles (`common`, `docker`, `caddy`, `monitoring`,
`bridgelink`, `backup`) encodes German law or German infrastructure. The only German
bracket around the project was the documentation language convention itself.

**The commercial product it was meant to feed is German-only.** The original business
rationale for Linumed OS was a "trojan horse": free kit, easy path to Linumed Shifts.
That coupling was decided against on 2026-08-13 - Linumed OS is to be positioned
internationally, decoupled from Shifts' DACH-only status, because the DACH expansion
for Shifts is blocked on the complexity of Austrian and Swiss working-time law and a
genuine internationalisation beyond DACH is a different question again (it is unclear
who the customer would even be). Linumed OS therefore has to stand on its own -
reputation and portfolio, possibly groundwork for a later internationalised Shifts.

The audience follows from that. The realistic primary audience is IT service providers
serving clinics, not clinic IT staff directly - they find projects through GitHub, not
through a vendor landing page. GitHub discovery is an English-language channel.

There is a third, smaller fact: **the repository does not currently obey its own rule.**
`CLAUDE.md` says "German for end-user docs, English for technical/developer docs", but
`README.md` is English, `ARCHITECTURE.md` is German, `CLAUDE.md` is English, ADR 0001 is
German although ADRs are developer documentation, and `docs/roles/*.md` are German. The
split was never applied consistently, so "keep the current convention" is not actually
an available option - there is no single current convention to keep.

## Options considered

**Keep German for end-user docs.** Zero migration cost today. Consistent with Shifts.
Rejected: it contradicts the positioning decision from 2026-08-13, and the cost of
switching grows with every document written - the operations handbook (#26) alone would
be a substantial document to write twice. Deferring the decision is the most expensive
option, not the cheapest.

**Bilingual, German and English side by side.** Serves both audiences. Rejected: two
copies of every document drift, and this project is maintained by one person. The repo
already demonstrates what happens - the `CLAUDE.md` language rule itself drifted from
reality without anyone noticing. Doubling the surface makes that worse, not better.

**English for new documents, keep existing German ones.** Pragmatic, no rewrite. Partly
adopted - see "Consequences": new material is English immediately, existing German docs
migrate as they are touched rather than in one campaign. What is rejected is leaving the
German documents German *permanently*, which would make the mixed state the end state.

**English throughout.** Chosen.

## Decision

English is the documentation language for this repository, for both end-user and
developer documentation. This supersedes the split rule in `CLAUDE.md`.

German remains correct for:

- **Commit messages** - unchanged, this is a workflow convention for the maintainer, not
  reader-facing documentation.
- **Linumed Shifts** - a separate, German-only product in a separate repository. This ADR
  says nothing about it.
- **Issues and internal notes** - the tracker is a working surface, not a published
  artefact.

## Consequences

**Accepted downsides.**

- The maintainer writes documentation in a second language. Precision suffers slightly,
  and reviewing one's own English is harder than reviewing one's own German.
- A German clinic administrator - a plausible reader - is served worse than before. This
  is a real cost, accepted because the identified primary audience is service providers
  who work in English-language tooling ecosystems anyway.
- Existing German documents are a migration debt: `ARCHITECTURE.md`, the ten
  `docs/roles/*.md` pages, and ADR 0001.

**Migration, deliberately not a campaign.** New documents are English from now on.
Existing German documents are translated when they are next substantially edited, or
when the MkDocs navigation is built (#26), whichever comes first. ADR 0001 stays German:
it is a record of a decision made at a point in time, and rewriting the record to match a
later convention would be backdating. Its German is not a bug to be fixed.

**Not affected.** No code, no variable names, no role behaviour. Code comments keep the
style of the file they are in, as before.

### When to revisit this decision

- **Linumed OS acquires a mainly German-speaking user base in practice** (issues,
  questions and contributions arriving in German). Then serving that audience beats the
  international ambition, and a German translation of the operations handbook becomes the
  first thing to add.
- **A certification or procurement process requires German documentation.** Public-sector
  and hospital procurement in Germany can demand it; that would be a hard requirement
  rather than a preference, and would force a bilingual setup regardless of the drift
  cost.
- **The international positioning is dropped** and Linumed OS is re-coupled to Shifts as
  a pure DACH upsell path.

## Sources

- Positioning decision of 2026-08-13, recorded in the project memory
  (`project_linumed_os_international_gtm`) - Linumed OS to be positioned internationally,
  decoupled from Shifts.
- `CLAUDE.md`, "Documentation" - the split rule this ADR supersedes.
- Issue #26 - operations handbook and MkDocs setup, the first document written under this
  decision.
