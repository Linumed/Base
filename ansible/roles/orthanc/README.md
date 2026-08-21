# orthanc

Orthanc (GPLv3 DICOM server) plus its PostgreSQL index, as a Docker Compose stack
(issue #69). The last service named in `ARCHITECTURE.md` that did not exist.

## Which image, and why it was not the obvious one

`jodogne/orthanc-plugins`, not `orthancteam/orthanc`. Upstream frames the difference as
audience - `orthancteam/*` for "ops teams", `jodogne/*` for developers and researchers -
which points at the wrong one for this kit until you measure.

**`orthancteam/orthanc` cannot run as an unprivileged user.** Started with
`user: "65532:65532"` its entrypoint fails on `/etc/hostid` and the container exits. The
component holding DICOM data is the last place this kit would accept a root container, so
that decided it. Full comparison, and what else was checked:
**[ADR 0009](../../../docs/adr/0009-jodogne-orthanc-image-not-orthancteam.md)**.

## No exporter needed

Orthanc serves Prometheus metrics natively at `/tools/metrics-prometheus`, enabled by
default, 46 metrics including study counts, disk size, pending jobs and logged errors. That
is the opposite of the answer BridgeLink gave in #60 - and the reason "does it expose
metrics?" is now a required part of the pre-check when adding a service, rather than
something discovered after the role is built.

The endpoint sits behind Orthanc's own authentication, so the scrape job uses `basic_auth`.

## Variables

See `defaults/main.yml`, all prefixed `orthanc_*`. User-facing writeup with verification
steps: `docs/roles/orthanc.md`.

Two have **no default** and the preflight refuses to run without them: `orthanc_db_password`
and `orthanc_users` (at least one account). Orthanc has no other user store - an empty
`orthanc_users` with `AuthenticationEnabled` locks the instance out of its own REST API,
including the healthcheck and the metrics scrape.

## The configuration file *is* the secret

`orthanc.json` carries the database password and every REST account, so it is deployed as a
Docker secret - mode 0400, owned by **UID 65532**, never as environment variables. Same
reasoning and the same trap as BridgeLink: a file-based secret keeps the host's ownership,
and a root-owned file makes the container restart-loop (#61).

## Exposure

Only the HTTP/REST port is published, and only on `127.0.0.1` - reachable through an SSH
tunnel.

**The DICOM listener is not published by default** (`orthanc_publish_dicom_port`, off).
Modalities need it reachable, which is a per-site decision with real consequences: a
published container port bypasses ufw, and what arrives on that port is patient data.
Turning it on is the operator's deliberate act, exactly like BridgeLink's channel listeners.

No modality is trusted by default either - `DicomModalities` is empty and
`DicomAlwaysAllowStore` is false, so an unknown sender is rejected rather than silently
archived.

## What this role does not do

- Does not install Docker - see the `docker` role, which runs before it in `site.yml`.
- Does not publish the DICOM port (see above).
- Does not enable any viewer plugin. The image bundles several, plus an S3 storage backend
  and others; **neither Orthanc image loads anything on its own**, the `Plugins` array
  decides. Only the PostgreSQL index is enabled here. Anything added is attack surface and a
  licence to check.
- Does not set a retention policy. How long studies stay is a decision about the
  institution's obligations, not a default this kit can pick.
- Does not import or anonymise anything. An empty archive is the deliverable.
