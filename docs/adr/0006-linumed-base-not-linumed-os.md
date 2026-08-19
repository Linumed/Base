# ADR 0006: The product is called Linumed Base, not Linumed OS

**Status:** accepted · **Date:** 2026-08-18 · **Affects:** the whole repository, the
Forgejo repository slug, container names, deploy paths, linumed.com; issue #51

## The question answered here

The project shipped two tagged releases as "Linumed OS". It is not an operating system.
This records why the name changed anyway, so the decision is not quietly reversed later
by someone who finds "OS" catchier.

## Context

Linumed Base is a collection of Ansible roles that configure a standard Debian 13
installation. It produces no bootable image, no installer, no distribution, and no
package repository. It does not replace, fork, or patch any part of the operating
system it runs on.

The strongest evidence that the name was wrong is in this repository's own files. Both
`README.md` and `CONVENTIONS.md` opened their product definition with a denial:

> It is NOT a custom Linux distribution and does NOT produce a bootable ISO.

and

> Linumed OS is not a custom Linux distribution.

**A name whose own definition has to begin by contradicting it is working against the
project.** Every first contact spent its opening sentence correcting an impression the
name had just created.

That cost is not evenly distributed. The intended audience is IT service providers who
run infrastructure for clinics - people who know exactly what a distribution is and what
a configuration management kit is. To that audience, calling the latter an "OS" reads
either as marketing inflation or as not knowing the difference. Both are expensive with
the group whose trust the project most depends on. It also attracts the wrong search
traffic: someone looking for a healthcare Linux distribution arrives, finds Ansible
roles, and leaves.

"Base" names what the thing actually is: the foundation an institution's own
applications - including Linumed Shifts - are deployed on top of. It reads naturally
next to "Linumed Shifts" as a product family, and it promises no distribution lifecycle,
ISO downloads or support horizon that a single maintainer could never honour.

## Why now, and not later

Measured on 2026-08-18, before any of it changed:

| | |
|---|---|
| Prose occurrences of "Linumed OS" | 67, across 32 files |
| Identifier occurrences of `linumed-os` | 128 |
| Container names | 11 |
| Deploy paths | `/opt/linumed-os` plus four subdirectories |
| **Ansible variables affected** | **none** - all role-prefixed (`common_*`, `monitoring_*`), none product-prefixed |
| Existing installations | **none** |
| Public references | **none** - the repository existed only on a private Forgejo instance |

The expensive parts of a rename are variable names and existing installations. Neither
applied. What remained was mechanical text replacement.

After publication (issue #50) the same change would cost redirects, broken inbound
links, and a breaking change for anyone who had already written container names into
their own scripts. The window was open exactly once, and this is when.

## Options considered

**A · Keep "Linumed OS".** Zero work. Rejected: the disclaimer stays in every
introduction forever, and the credibility cost recurs with every new reader in the
target audience. The name would also have to be defended each time someone asks why an
Ansible kit calls itself an operating system.

**B · "Linumed Core".** Accurate in tone, but implies being the core *of* a larger
product. This kit is not a component of Shifts; it is an independent foundation that
Shifts happens to run well on. Rejected as less precise than Base.

**C · "Linumed Base".** Chosen. Short, accurate, describes the role rather than
overselling the artefact, and pairs cleanly with Linumed Shifts.

The obvious criticism of C is that "Base" is bland and not independently searchable.
Accepted: in a house-brand system the brand carries recognition and the suffix only has
to be accurate. An inaccurate name that is memorable is worse than an accurate one that
is plain.

## Decision

The product is **Linumed Base**. Container names use the `linumed-base-` prefix, the
default deploy path on a managed host is `/opt/linumed-base`, and the shared Docker
network is `linumed-base-external`.

The repository is named **`Base`**, matching the existing `Shifts` repository - the
organisation already carries the "Linumed" part, so repeating it in the repository name
would be redundant. The working copy therefore lives at `/opt/base`, alongside
`/opt/shifts`.

**The deploy path deliberately does not follow that shortening.** `/opt/base` is fine on
a machine that only ever holds Linumed checkouts; on a clinic's server, a directory
called `base` says nothing about what put it there or who maintains it, while
`/opt/linumed-base` is self-documenting for whoever inherits the system. Short names for
our own working copies, descriptive names for anything that lands on someone else's
machine.

**Deliberately not renamed:**

- **Git history and the existing `v0.1.0` / `v0.2.0` tag messages.** Those releases
  were made under the old name. Rewriting published history to pretend otherwise would
  be dishonest, and rewriting pushed tags is bad practice regardless. `CHANGELOG.md`
  records the rename instead, so a reader who encountered the old name can connect the
  two.
- **The bare `linumed` namespace.** The inventory group `linumed`, the sshd drop-in
  `90-linumed-tunnel-users.conf`, `51-linumed-unattended-upgrades`, and
  `timesyncd_10-linumed.conf` identify the *vendor*, not the product. They exist to
  avoid colliding with distribution-provided files and stay stable across products.
  Renaming them would be churn with no benefit and would break nothing usefully.
- **ADR 0001's German filename and text**, for the reason given in ADR 0002.

## Consequences

**Checked before assuming it was safe:** nothing in this repository bakes the product
name into persisted state. `restic` tags snapshots with `auto`, not a product string, so
existing backup repositories would keep working. Docker volume names derive from each
stack's *immediate* directory (`caddy`, `monitoring`, `bridgelink`), not from the parent
path, so moving `/opt/linumed-os` to `/opt/linumed-base` does not orphan a volume. This
is the class of problem that made a comparable rename elsewhere in this organisation
leave three deliberate exceptions behind; here there are none, and that was verified
rather than hoped.

Prometheus job names change (`linumed-os-host` becomes `linumed-base-host`), which would
break metric continuity across the rename on a running installation. There are none, so
it costs nothing - but it is the reason this could not have been done after publication
without a migration note.

The local working copy path and this repository's Forgejo slug change together with the
content; anything pointing at the old slug has to be updated, including `origin` on every
clone.

## When to revisit

Only if the product's nature changes - if it ever does produce a bootable image or a
distribution, the name should be revisited in the other direction. A rename because a
different word sounds better is explicitly not a reason; that is what this ADR exists to
prevent.

## Sources

- Issue #51 - the rename, with the full measured blast radius.
- `README.md` and `CONVENTIONS.md` before this change - both opened their product definition
  with a denial of the name.
- ADR 0002 - the audience argument (international, GitHub-first) that makes the
  precision of the name matter to exactly the readers the project is written for.
