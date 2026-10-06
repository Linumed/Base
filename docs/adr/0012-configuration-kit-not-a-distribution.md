# ADR 0012: A configuration kit, not a distribution

**Status:** accepted · **Date:** decided spring 2026, recorded 2026-10-06 · **Affects:** the shape of the whole project; README; `CONVENTIONS.md`; [ADR 0006](0006-linumed-base-not-linumed-os.md); issue #112

## The question answered here

Linumed did not start as an Ansible kit. The original plan was **LinumedOS**: a
Debian-based distribution for hospitals. Somewhere in spring 2026 that plan was dropped in
favour of what this repository is - a set of Ansible roles that configure a *standard*
Debian installation.

That is the oldest decision in the project and the one everything else rests on, and it
was never written down. README and `CONVENTIONS.md` only deny the alternative ("not a
custom Linux distribution"); [ADR 0006](0006-linumed-base-not-linumed-os.md) explains
why the *name* followed the decision months later, and takes the decision itself as
given. An exclusion with no recorded reasoning is the gap
[ADR 0007](0007-docker-compose-not-kubernetes.md) describes for Kubernetes - it cannot be
defended when someone asks, and invites being reversed out of habit.

**This record is written after the fact.** The decision predates the repository: the
first commit (2026-05-25) already describes "an Ansible-based IaC kit that turns a
standard Debian 13 installation" into the platform. There are no notes from the time.
What follows separates the maintainer's account of what happened from the reasoning
added while writing this down, and labels which is which.

## What happened (maintainer's account)

Until spring 2026 the working assumption was that building a distribution was simply a
matter of doing it. The first practical step was a VM: a Debian installation on which
the first configuration changes were made by hand.

That step is what changed the plan. The changes being made were *configuration* of a
standard Debian - and a distribution around them would have been the maximum possible
overhead for what the project actually set out to offer: a hardened, monitored, backed-up
host for clinic infrastructure. In spring 2026 the project switched to the Ansible line.

## Why a distribution is that overhead (analysis, 2026-10-06)

The account above names the cost in one word. Spelled out, a distribution - even a thin
Debian derivative - commits its maintainer to things that have nothing to do with
hospital infrastructure:

- **A place in the security path.** Debian's security team ships fixes to Debian users.
  A derivative either passes them through untouched - in which case it adds nothing at
  package level - or rebuilds and republishes them, which puts one person between
  Debian's security team and a hospital's servers. For a single maintainer, that is a
  latency and availability promise that cannot be kept through holidays or illness.
- **Release engineering.** Installer images per point release, a signed package
  repository and its keys, mirrors, a support horizon that someone will plan a hospital's
  hardware cycle around.
- **A trust question with the wrong answer.** The audience is IT service providers who
  run infrastructure for clinics. "Stock Debian, configured" is something they can audit
  in an afternoon. "Our own distribution, maintained by one person" is something they
  have to take on faith.

None of that work would have touched what makes the project useful. Everything the
original plan was meant to deliver - hardening, the integration engine, monitoring,
encrypted backups - is configuration and containers on top of an unmodified system.

## Options considered

**A · A Debian-based distribution (the original plan).** Rejected for the reasons above:
maximum overhead relative to the product, and a maintenance load one person cannot carry.

**B · A configuration kit over stock Debian.** Chosen. The operating system, its packages
and its security updates stay Debian's; this project owns only what it adds.

**Middle grounds that were *not* evaluated at the time** - a preseeded installer ISO, a
Debian Pure Blend, or a single apt repository with meta-packages. They are listed so
nobody reads their absence as a judgement. Each would reintroduce part of A's cost -
images to rebuild, a repository and keys to maintain - for a gain the kit already gets
from `scripts/bootstrap.sh` and a stock netinst image. The netinst/preseed path exists
today as a *test* (`test/vm-test-netinst.sh`), not as a product.

## Consequences

**What this buys.** Security updates come from Debian through `unattended-upgrades`,
with nobody from this project in between. A new Debian release is a new target to test,
not a rebase. Everything this project changes on a host is readable in one place - the
roles - rather than spread across patched packages.

**What this costs.** There is no "install this ISO and you are done": an operator needs a
control node with Ansible, runs `bootstrap.sh` on a fresh minimal install, then the
playbook. Anything that would require a *modified* package is out of reach by
construction. And the kit is bound to Debian's lifecycle - when Debian 13 leaves
security support, so does every host still running it.

**The name lagged behind.** The repository carried the old name through two tagged
releases (`v0.1.0`, `v0.2.0`) before [ADR 0006](0006-linumed-base-not-linumed-os.md)
renamed it - with README and `CONVENTIONS.md` opening, in the meantime, with a denial of
what the name suggested.

**It set the pattern.** The later exclusions - no Kubernetes
([ADR 0007](0007-docker-compose-not-kubernetes.md)), no bundled identity provider
([ADR 0003](0003-loopback-only-access-no-bundled-identity-provider.md)), Orthanc removed
([ADR 0011](0011-orthanc-removed-not-part-of-base.md)) - apply the same test this one
did first: does the addition serve what the project offers, or does it mostly create
something to maintain?

## When to revisit

- **A requirement that configuration cannot meet** - a patched package, a kernel the
  hospital's hardware needs that Debian does not ship. The answer then is the smallest
  step that meets it (one package, one repository), not a distribution.
- **The project stops being maintained by one person**, and a real group commits to the
  security path described above. Wanting a bootable image is not by itself a reason.

## Sources

- The maintainer's account, recorded 2026-10-06 in issue #112.
- First commit `3c40c31` (2026-05-25) - its README already describes the kit as configuring
  a standard Debian 13 installation.
- [ADR 0006](0006-linumed-base-not-linumed-os.md) - the rename that followed, and the
  measured state of the name before it.
- [ADR 0007](0007-docker-compose-not-kubernetes.md) - the argument that an unexplained
  exclusion is a gap, applied here to the oldest one.
