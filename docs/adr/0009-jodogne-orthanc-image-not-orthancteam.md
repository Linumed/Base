# ADR 0009: `jodogne/orthanc-plugins` as the Orthanc image, not `orthancteam/orthanc`

**Status:** obsolete since [ADR 0011](0011-orthanc-removed-not-part-of-base.md) · **Date:** 2026-08-21 · **Affects:** `orthanc`; issue #69

> **2026-08-23:** the `orthanc` role this ADR was written for no longer exists in this
> kit (#92/ADR 0011), so this decision no longer applies to anything Linumed Base
> deploys. **Obsolete, not superseded:** ADR 0011 did not pick a different image, it
> removed the question. The measurement below is unaffected by that and still holds - it
> is cited by
> [docs/operations/orthanc-recommendation.md](../operations/orthanc-recommendation.md)
> for anyone running Orthanc themselves.

## The question answered here

Orthanc is published as two actively maintained image families, and the project recommends
neither over the other - they are aimed at different audiences. Picking one is therefore a
decision, not a lookup, and the same kind of decision ADR 0001 made for the integration
engine.

## Context

Both were measured on 2026-08-21 rather than compared from their descriptions:

| | `orthancteam/orthanc:26.8.1` | `jodogne/orthanc-plugins:1.13.0` |
|---|---|---|
| Orthanc core | 1.13.0 | 1.13.0 |
| Maintainer | the Orthanc team's ops-facing images | Sébastien Jodogne, the original author |
| Configuration | environment variables *or* config file | config file |
| PostgreSQL index/storage plugins | yes | yes |
| DicomWeb, Explorer 2, worklists | yes | yes |
| **Runs as a non-root user** | **no** | **yes** |
| Prometheus endpoint | yes | yes |

The upstream documentation frames the difference as audience: `orthancteam/*` for "ops
teams and end-users", `jodogne/*` for "software developers and researchers". By that
description alone, the ops-facing image is the obvious pick for this kit.

Measuring changed the answer.

## The finding that decided it

**`orthancteam/orthanc` cannot run as an unprivileged user.** Started with
`user: "65532:65532"`, its entrypoint fails and the container exits:

```
/docker-entrypoint.sh: line 24: /etc/hostid: Permission denied
Status: exited, ExitCode: 1
```

The same configuration under `jodogne/orthanc-plugins` starts normally, serves HTTP, and
runs as UID 65532 - verified against a full PostgreSQL-backed deployment, not just a
smoke start:

```
DatabaseBackendPlugin: /usr/local/share/orthanc/plugins/libOrthancPostgreSQLIndex.so
laeuft als: uid=65532 gid=65532 groups=65532
```

That matters more here than anywhere else in this kit. Orthanc holds **DICOM images and
their metadata** - names, dates of birth, referring physicians - which is the most
sensitive data anything in Linumed Base touches. Running that component as root while
BridgeLink runs as UID 65532 (ADR 0001, deliberately a hardened image) would be an
inconsistency the documentation could not defend.

## Options considered

**`orthancteam/orthanc` as-is, running as root.** Rejected. It contradicts the hardening
this kit claims, in the role where the claim matters most.

**`orthancteam/orthanc` with a workaround** - pre-creating `/etc/hostid`, or overriding the
entrypoint. Rejected: it means maintaining a patch against an upstream startup script that
is free to change, to obtain a property the alternative image has for free.

**Building our own image.** Rejected for the reason ADR 0001 gives - an image this repo
builds is one it must also scan, host and keep patched. `jodogne/orthanc-plugins` is
published by the project's original author, carries the same core version, and is current.

**`jodogne/orthanc-plugins` (chosen).**

## Decision

The `orthanc` role deploys **`jodogne/orthanc-plugins`**, running as UID 65532 with
`no-new-privileges`, its index in PostgreSQL and its DICOM files on a Docker volume.

## Consequences

**Configuration is a JSON file, not environment variables.** That suits this repo: the
config carries the database password, and a file can be mounted as a Docker secret while
an environment variable is readable by anyone who can run `docker inspect`. The same
reasoning as BridgeLink's `mirth.properties`, and the same trap applies - a file-based
secret keeps the host's ownership, so it must be owned by UID 65532 or the container dies
in a restart loop (#61).

**No Orthanc Explorer 2 by default.** It is present in the image but not loaded unless the
configuration names it. Neither image loads plugins on its own; the `Plugins` array decides,
which is what makes "the image bundles a lot" a non-issue: only what is listed is active.

**Plugin licensing stays the operator's decision at the edges.** The core and the plugins
this role enables are GPL/AGPL. The images bundle further plugins - viewers, an S3 storage
backend, an "education" plugin - that are simply not loaded here. Anyone enabling more
should check what they are enabling; this repo's FOSS-only rule covers what it ships, not
what an operator adds.

**If the choice is ever revisited**, the trigger is `orthancteam/orthanc` gaining non-root
support, or `jodogne/*` falling behind on releases. Both were current within days of each
other when this was written.

## What was checked and is worth not re-checking

- **Orthanc has a native Prometheus endpoint**, `/tools/metrics-prometheus`, enabled by
  default and returning 46 metrics including study counts, disk size, pending jobs and
  logged error counts. **No exporter is needed** - the opposite of the answer BridgeLink
  gave in #60, and the reason that pre-check is now a required part of adding a service.
- The endpoint requires authentication, like the rest of the REST API.
- The image has neither `curl` nor `wget`, but does have `bash`, so the healthcheck speaks
  raw HTTP over `/dev/tcp` - the same technique the monitoring role uses for Alloy. It
  accepts **401 as alive**: an unauthenticated request proves the HTTP server is serving,
  which is what a liveness check is for.

## Sources

- [ADR 0001](0001-bridgelink-statt-mirth-connect.md) - the same shape of decision for the
  integration engine, and the source of the "no image we have to build ourselves" criterion
- Issue #69
