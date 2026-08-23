# Orthanc: recommended for DICOM, not a maintained role

**Orthanc was a role in this kit from v0.4.0 until it was removed in #92/[ADR
0011](../adr/0011-orthanc-removed-not-part-of-base.md).** If you're looking for a DICOM
server to pair with Linumed Base, this page recommends Orthanc anyway - with everything
this project found while running it, including the reasons it no longer ships one.

## Why it was removed, not just documented differently

README's own boundary says: *"No application software. No HIS, no DMS, no document
management. Institutions bring their own applications; this provides the base they run
on."* Three things this kit measured about its own Orthanc deployment put it on the wrong
side of that line:

1. **No access identity in the logs, at any verbosity.** Tested against a real instance:
   default logging produces nothing per request, and `--verbose` logs method, path and
   timing -

   ```
   I0823 05:28:40.037495 HTTP-1 ElapsedTimer.cpp:102] (http) GET /patients
   ```

   - never a username, regardless of whether the request carried real credentials, wrong
   credentials, or none. If a RIS sits in front of Orthanc with its own user directory and
   a single shared service account, the identity of who actually looked at a study never
   reaches Orthanc at all - no amount of log shipping recovers it.
2. **Real, unbounded persistence.** `StorageDirectory`/`IndexDirectory` pointed at a
   dedicated Docker volume. No auto-forwarding, no automatic deletion, no S3 offload
   enabled by default (the plugin exists in the image; this kit never turned it on). What
   arrived stayed on the host indefinitely - the former role's own README called it "an
   archive" and said "an empty archive is the deliverable". That is a genuine document
   store, not a stateless relay.
3. **The self-contradiction those two facts add up to.** A DICOM archive with its own
   PostgreSQL index, holding patient data with no retention limit and no way to say who
   accessed it, is application software by README's own definition - not a boundary case.

None of this is a defect in Orthanc. It is a defect in *this kit shipping it as a role*
without an audit story or a retention story - the same gap #90 (access-log/KRITIS) and
#92 (scope) both converged on independently in the same week.

## What was actually tested (from ADR 0009, preserved below)

`jodogne/orthanc-plugins`, not `orthancteam/orthanc`. The upstream documentation points
the other way for an operations-focused kit - measuring reversed it:
**`orthancteam/orthanc` cannot run as a non-root user.** Its entrypoint fails writing
`/etc/hostid` and the container exits. For the component holding DICOM images and their
metadata - names, dates of birth, referring physicians - a root container was not a
trade-off this kit was willing to make when an alternative with the same core version and
the same plugins runs unprivileged. Full comparison:
[ADR 0009](../adr/0009-jodogne-orthanc-image-not-orthancteam.md) (superseded by ADR 0011,
kept for the image-choice reasoning - still correct if you deploy Orthanc yourself).

## If you deploy it yourself: what to build in from day one

This kit's removed role got some things right that are worth keeping, and left gaps this
project would not sign off on again without fixing them first:

**Keep:**
- Unprivileged container (`jodogne/orthanc-plugins`, UID 65532) - the ADR 0009 finding
  still holds.
- `AuthenticationEnabled: true`, no shared "admin/admin" default, one account per
  consumer (don't reuse a human's account for a service scrape).
- DICOM port not published by default. A published container port bypasses `ufw`
  entirely, and what arrives on it is patient data - publishing it is a deliberate,
  per-site network decision, not a default.
- `DicomAlwaysAllowStore: false` and an explicit `DicomModalities` allowlist - no unknown
  sender should be trusted to store.
- File-based secrets (config file as a Docker secret, mode 0400, owned by the container
  UID), not environment variables - `docker inspect` can read env vars.

**Fix before you rely on it, which this kit's role never did:**
- **Decide who is authoritative for access identity before deployment, not after.** If a
  RIS sits in front, its own audit log is probably the only place a real access record
  can exist - verify that RIS actually keeps one, with per-user identity, before assuming
  Orthanc's logs (however verbose) will ever substitute.
- **Set a retention policy and enforce it**, not just "keep everything forever" by
  omission. How long is a question for the institution's own obligations, but *some*
  answer has to exist before the archive holds real patient data.
- **Decide whether this Orthanc is the archive-of-record or a staging point** with
  offload to a real VNA/long-term archive elsewhere. This kit's former role defaulted to
  "archive-of-record" by simply never configuring anything else - that was never a
  deliberate choice, just what happened when nobody set the S3 plugin up.

## Reference: the old role's configuration, as a starting point

Preserved as reading material for anyone bootstrapping their own Compose stack - not
maintained, not tested by this repository's CI, and will drift from any future Orthanc
release. Treat it as a documented starting point, not a supported artifact.

- Image: `jodogne/orthanc-plugins:1.13.0`, run as UID 65532, PostgreSQL index on
  `postgres:17.11-alpine`, no host port on the DICOM listener, REST/Explorer bound to
  `127.0.0.1` only.
- Config file (`orthanc.json`) mounted as a Docker secret carrying the database password
  and every REST account - `orthanc_users` is Orthanc's *only* user store; an empty map
  with authentication enabled locks the instance out of its own REST API, including its
  own healthcheck.
- Healthcheck needs `bash`, not `sh` - the image has no `curl`/`wget`, so a liveness probe
  has to speak raw HTTP over bash's `/dev/tcp`. `CMD-SHELL` runs `/bin/sh` (dash) on this
  image, where that syntax does not exist.
- Orthanc serves its own Prometheus metrics natively at `/tools/metrics-prometheus` - no
  exporter needed, but the endpoint sits behind Orthanc's own REST authentication, so a
  scrape job needs `basic_auth` with credentials that also exist in `orthanc_users`.
- **Orthanc falls back to SQLite without complaining** if the PostgreSQL plugin fails to
  load - verify `DatabaseBackendPlugin` after every deploy, not just container status.

The full former role - templates, tasks, defaults - is recoverable from this repository's
git history before #92 if you want a literal starting point rather than reconstructing it
from this page.

## GDPR / access-obligation notes carried over

- **DICOM metadata is personal data even before the image is looked at.** Patient name,
  date of birth, referring physician and accession number travel in the header of every
  instance. There is no configuration in which a populated archive holds anonymous data
  by default.
- **No seed, no example data, ever** - not even to reproduce a fault. Construct a
  synthetic study instead.
- **A backup of the storage volume contains patient images.** Where that backup lives,
  and who can decrypt it, belongs in the institution's processing record.
