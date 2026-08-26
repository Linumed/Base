# ADR 0011: Orthanc removed - not part of Linumed Base

**Status:** accepted · **Date:** 2026-08-23 · **Affects:** the removed `orthanc` role; `monitoring`; README; ADR 0003; ADR 0008; ADR 0009 (obsolete); issues #69, #90, #92

## The question answered here

Orthanc shipped as a role from v0.4.0 (#69) onward: a DICOM server plus its own
PostgreSQL index, deployed unprivileged, reachable only through an SSH tunnel until an
operator deliberately opened the DICOM port. This ADR records why it was removed again -
not deprecated, not gated behind a flag, removed - and what replaces it.

## Context

Three findings surfaced independently in the same week, while working two other issues
(#90 - a DSGVO/KRITIS access-log question - and a follow-up scope question that became
#92):

1. **No access identity in Orthanc's own logs, at any verbosity.** Tested against a real
   instance: default logging emits nothing per HTTP request; `--verbose` logs method,
   path and timing, never a username - identical output whether the request carried real
   credentials, wrong credentials, or none:

   ```
   I0823 05:28:40.037495 HTTP-1 ElapsedTimer.cpp:102] (http) GET /patients
   ```

   If an institution's RIS sits in front of Orthanc with a single shared REST account (a
   normal integration pattern, and the only pattern this kit's `orthanc_users` map
   actually supported), the identity of the person who looked at a study never reaches
   Orthanc. No amount of log shipping recovers an identity that was never logged.

2. **Real, unbounded persistence.** `StorageDirectory`/`IndexDirectory` pointed at a
   dedicated Docker volume. No auto-forwarding, no automatic deletion, no S3 offload
   turned on by default (the plugin exists in the image; nothing in this kit enabled it).
   The former role's own README called it "an archive" and stated plainly: "an empty
   archive is the deliverable." Patient data landed on the deployed host and stayed there
   until a human intervened - a genuine document store, not a stateless relay, regardless
   of whether an institution's mental model of "Orthanc" was "just a DICOM router."

3. **The self-contradiction those two facts add up to.** README states, and has stated
   since before Orthanc existed: *"No application software. No HIS, no DMS, no document
   management. Institutions bring their own applications; this provides the base they run
   on."* A DICOM archive with its own database, holding patient data indefinitely with no
   way to attribute an access to a person, is application software by that definition -
   not a grey area reached by squinting, but exactly what the sentence was written to
   keep out. Orthanc entered via #69 as "the last service named in ARCHITECTURE.md that
   did not exist" - momentum from an already-drafted architecture, not a decision weighed
   against this boundary at the time.

None of this is a defect in Orthanc the project. It is what this kit's deployment of it
actually was, measured rather than assumed - and once measured, it did not fit.

## Options considered

**A · Keep it, build the missing pieces (access audit, retention policy, RIS-integration
guidance).** Rejected. Building a real audit trail is exactly the kind of "another
system" ADR 0003's own criterion warns against absorbing - it would mean Base owning
identity/audit concerns that belong to whatever application (RIS, viewer) an institution
already runs, duplicating work and creating a second, likely inconsistent, source of
truth for "who accessed what."

**B · Keep it, narrow its role to a staging/relay point with mandatory offload.** Rejected
for this release. Technically coherent, but it is a design for a *different* piece of
software than what existed - a new auto-routing and lifecycle feature, not a
configuration change - and doing that well needs the kind of real-world DICOM-routing
experience this project does not have. Revisiting this as a future, deliberately-scoped
feature is not ruled out; shipping it disguised as "the same role, slightly adjusted" is.

**C · Remove it as a role, document it as an external recommendation with the full
findings attached.** Chosen. Consistent with what README already says the kit is. Anyone
who wants Orthanc still gets a considered starting point -
[docs/operations/orthanc-recommendation.md](../operations/orthanc-recommendation.md) -
including the image-choice reasoning (ADR 0009) and, unlike before, the three findings
above stated plainly rather than left for someone else to discover against a production
host.

## Consequences

**Breaking change against the ADR 0008 stability guarantee**, requiring a major version
bump: the `orthanc` role, its container names, its deploy path, and its share of the
frozen variable/alert/volume counts all disappear.

**No migration machinery was built for this, deliberately.** The kit has no users yet -
`v1.0.0` was tagged three days before this decision - so there is no installed base to
carry forward, and inventing an upgrade path for hypothetical hosts would have meant
maintaining code nobody runs. The role is simply gone. `docs/operations/teardown.md`
keeps its `orthanc` entries, which is enough for anyone who did deploy `v1.0.0`, and is
what the automated teardown check exercises anyway.

`monitoring` loses its Orthanc-specific scrape job, alert rule group
(`OrthancDown`/`OrthancErrorRate`/`OrthancJobsStuck`), and the credential-matching
preflight that existed only to keep `monitoring_orthanc_*` and `orthanc_users` in sync
(issue #76). All of it existed to serve a role that no longer exists.

`scripts/select-roles.sh` loses its one selection-time dependency rule (orthanc requires
monitoring) and becomes a flat, unconditional checklist over the remaining four optional
roles - simpler, not smaller in any way that matters, since none of the other four roles
has ever depended on another.

ADR 0009's image-choice analysis (`jodogne/orthanc-plugins` vs. `orthancteam/orthanc`) is
marked **obsolete, not superseded, and not deleted.** The distinction is deliberate: this
ADR did not decide the image question differently, it removed the question. The
measurement itself is untouched by that and still correct, which is why the ADR stays and
the recommendation page above cites it.

Issues #90 (access-log/DSGVO) and #92 (scope question) are both resolved by this decision
rather than by a technical fix - closed with a comment pointing here, not silently.

## What this does not change

ADR 0003's boundary is confirmed by this finding, not revised - "no application software"
already said this; Orthanc's inclusion was the thing out of step with it, not the
sentence.
