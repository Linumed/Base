# Upgrading from an earlier version

**There is no separate upgrade playbook, and this page is what makes that a measured
claim rather than an assumption.** The command is the same one used for the first deploy:

```bash
ansible-playbook -i inventory/<myhospital> playbooks/site.yml --ask-vault-pass
```

Pull the new version, run that, done. What follows is why that is actually true, not just
plausible - and what to expect when it runs.

## Why this needed measuring

Before `v1.0.0`, "git pull, run `site.yml` again" was the honest answer, but nobody had
tried it. Idempotency across *one* apply of the same version and idempotency across a
*version boundary* are different claims: a changed default, a renamed file, a template
that moves a value from a variable to a literal can all produce a real - if harmless -
`changed` the first time a newer version runs against an older deployment. None of that
shows up in the double-run every commit already gets, because both runs there are the
*same* version.

`test/lib/upgrade-check.sh` closes that gap: on every relevant push, the CI VM is deployed
with the previous tagged release first, then upgraded to the commit under test, with the
number of changed tasks on that first post-upgrade apply reported explicitly - one more
step in the same `test/vm-test.sh` sequence that already double-runs every deploy.

## What actually happened, measured (`v0.4.0` → `v1.0.0`, 2026-08-22)

The first upgrade this kit ever went through, by hand, before the automated check existed
(the `orthanc` role named below no longer exists - removed in #92/[ADR
0011](../adr/0011-orthanc-removed-not-part-of-base.md) - this is historical evidence about
how upgrades behave, kept as written):

```
v0.4.0 first apply (fresh host):        ok=127  changed=77  failed=0
v1.0.0 apply over that same host:       ok=119  changed=2   failed=0
v1.0.0 applied again (idempotency):     ok=118  changed=0   failed=0
```

Two changes, both explained by the same cause:

```
TASK [orthanc : Deploy the Orthanc configuration secret]   changed
HANDLER [orthanc : Restart orthanc]                        changed
```

[Issue #80](https://github.com/Linumed/Base/issues/80) made `orthanc_http_port`'s
container-internal side a fixed literal instead of a templated variable, so the
*value* an existing deployment already had (`8042`, the default) did not change - but the
*file content* did, because the template itself changed. Ansible correctly detected that
and restarted Orthanc to apply it. One container, one restart, no data involved, no
manual step needed.

**The general shape to expect:** a small number of `changed` tasks tied to specific,
explained entries under `### Breaking` or `### Changed` in [CHANGELOG.md](../changelog.md)
- not zero, but not a surprise either, if the changelog was read first. Every entry names
its issue for exactly this reason.

## Before upgrading

1. **Read the `CHANGELOG.md` entries between your current version and the target**,
   specifically anything under `### Breaking`. That section exists so this step is a
   five-minute read, not a guess.
2. **Back up first regardless.** The restic backup this kit already runs covers
   `/opt/linumed-base` - see [Backup & Restore](backup-restore.md). An upgrade is not
   expected to need it, and that is exactly when skipping it is tempting.
3. **Pull the new version**, same as the first clone.
4. **Run `site.yml`** with the same inventory and vault used before - nothing about
   upgrading changes how those are supplied. See
   [Updates](updates.md) if the change is only to a pinned image version rather than to
   this repository itself; that is a narrower, more frequent case than a full version
   upgrade.

## What this does not cover

**Skipping versions.** The measured example and the automated check both upgrade from
the immediately preceding tagged release. Going from, say, `v1.0.0` straight to `v1.3.0`
applies every change in between in one pass rather than one release at a time, which is
untested territory - each `### Breaking` entry was written and verified against the
release immediately before it, not against an arbitrary earlier one. Upgrading one
release at a time is the only path this page can vouch for.

**Anything before `v1.0.0`.** The stability guarantee in
[ADR 0008](../adr/0008-what-the-v1-0-stability-guarantee-covers.md) starts at that tag.
Releases before it changed identifiers outright (`v0.3.0` renamed every one of them) with
no migration path provided, by design - see that release's `### Breaking` entry.

## Keeping this page and its test current

`test/lib/upgrade-check.sh` upgrades from a fixed tag, deliberately not "whatever the
latest tag happens to be" - an automatic pick would silently start testing a different
upgrade the moment a new tag lands. **That tag has to be bumped by hand as part of
preparing each release after this one**, or this check keeps testing an increasingly old
upgrade instead of the one that actually matters. The script's own header comment is
where that edit happens.
