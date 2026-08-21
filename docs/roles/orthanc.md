# orthanc: DICOM archive

## Problem

An imaging department produces studies that have to be stored, found again, and handed to
whatever views them - and none of that should require sending patient images to a service
outside the building. Orthanc is a DICOM server: it speaks the protocol modalities already
speak, stores what they send, and exposes it over REST and DICOMweb.

This role deploys it with a PostgreSQL index, unprivileged, reachable only through an SSH
tunnel until the operator deliberately opens the DICOM port.

## Which image, and the finding that decided it

`jodogne/orthanc-plugins`, not `orthancteam/orthanc`. The upstream documentation points the
other way for an operations-focused kit - and measuring reversed it:
**`orthancteam/orthanc` cannot run as a non-root user.** Its entrypoint fails writing
`/etc/hostid` and the container exits.

For the component holding DICOM images and their metadata - names, dates of birth, referring
physicians - a root container is not a trade-off this kit is willing to make when an
alternative with the same core version and the same plugins runs unprivileged.

Full comparison, including what else was measured:
[ADR 0009](../adr/0009-jodogne-orthanc-image-not-orthancteam.md).

## Variables

All prefixed `orthanc_*`, in `ansible/roles/orthanc/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `orthanc_image` | `jodogne/orthanc-plugins:1.13.0` | Runs as UID 65532 - see ADR 0009 |
| `orthanc_postgres_image` | `postgres:17.11-alpine` | Index backend |
| `orthanc_http_port` | `8042` | REST/Explorer, bound to `127.0.0.1` only |
| `orthanc_dicom_port` | `4242` | DICOM listener **inside** the container |
| `orthanc_publish_dicom_port` | `false` | Publishing it to the host is a deliberate per-site decision |
| `orthanc_aet` | `LINUMED` | The AET modalities are configured against - changing it later means reconfiguring every device |
| `orthanc_db_password` | `""` (required) | Preflight aborts without it |
| `orthanc_users` | `{}` (required) | `{username: password}`; Orthanc has no other user store |
| `orthanc_plugins` | PostgreSQL index only | Nothing loads unless listed here |
| `orthanc_postgres_enable_storage` | `false` | Index in PostgreSQL, pixel data on a volume |
| `orthanc_metrics_enabled` | `true` | Joins the shared metrics network for Prometheus |
| `orthanc_stop_grace_period` | `30` | Seconds before a hard kill |

`orthanc_db_password` and `orthanc_users` belong in **Ansible Vault**.

## What gets changed

- `{{ orthanc_deploy_dir }}/docker-compose.yml`
- `{{ orthanc_deploy_dir }}/secrets/` (0700, root) holding `orthanc.json` and `db_password`.
  **`orthanc.json` is owned by UID 65532, mode 0400** - it carries the database password and
  every REST account, and a file-based Docker secret keeps the host's ownership. Root-owned
  means a restart loop, the same trap as BridgeLink (#61).
- Containers `linumed-base-orthanc` and `linumed-base-orthanc-db`, volumes for the DICOM
  files and the database.

## Monitoring: no exporter

**Orthanc serves Prometheus metrics itself**, at `/tools/metrics-prometheus`, enabled by
default - 46 metrics including `orthanc_count_studies`, `orthanc_disk_size_mb`,
`orthanc_jobs_pending` and `orthanc_logged_errors_count`.

That is worth stating because the answer went the other way for BridgeLink, which needed a
purpose-built exporter (#60). Asking the question early is now a fixed part of adding a
service; here it saved building anything.

Turn on the scrape in the monitoring role - both switches, deliberately separate:

```yaml
monitoring_scrape_orthanc: true
monitoring_orthanc_user: "metrics"
monitoring_orthanc_password: "{{ vault_orthanc_metrics_password }}"
```

The account has to exist in `orthanc_users`. Prometheus reaches the container by name over
the shared metrics network, not over a host port - see [issue #64] for why a published port
would not work and an all-interfaces one would bypass ufw.

Three alert rules ship dormant until the metrics appear: `OrthancDown`, `OrthancErrorRate`,
`OrthancJobsStuck`. There is deliberately **no** disk-size alert - what counts as too large
depends entirely on a retention policy this kit does not set, and `DiskSpaceLow` on the host
covers the case that actually breaks something.

## Access

```bash
ssh -L 8042:127.0.0.1:8042 <user>@<host>
# then: http://localhost:8042/
```

## The DICOM port is not published, deliberately

`orthanc_publish_dicom_port` is `false`. Modalities cannot reach the archive until it is
turned on, and that is the intended default:

- A published container port **bypasses ufw entirely**, so opening it is not covered by the
  firewall the `common` role configures.
- What arrives on that port is patient data. Which devices may send, from which network
  segment, is a decision about the institution's network, not something a playbook default
  should make.

The same reasoning as BridgeLink's channel listeners. When it is turned on, also fill in
`DicomModalities` - the shipped configuration trusts **no** sender
(`DicomAlwaysAllowStore: false`), so an unknown modality is rejected rather than silently
archived.

## Verification

Container status says nothing here - the same lesson the bridgelink role paid for. The role
checks these itself and fails if they do not hold:

```bash
# Is the HTTP server serving? 401 without credentials is the expected answer.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8042/system

# Is it running on PostgreSQL rather than the built-in SQLite? This is the one that
# silently goes wrong: Orthanc starts happily on SQLite if the plugin fails to load.
curl -s -u <user>:<pass> http://127.0.0.1:8042/system | grep DatabaseBackendPlugin

# Are metrics being served?
curl -s -u <user>:<pass> http://127.0.0.1:8042/tools/metrics-prometheus | head
```

## Pitfalls

- **Orthanc falls back to SQLite without complaining.** If the PostgreSQL plugin is not
  listed in `orthanc_plugins`, or fails to load, Orthanc starts anyway with its built-in
  database - and everything looks fine until the second host, the first restore, or the
  first performance problem. The role verifies `DatabaseBackendPlugin` after deploying for
  exactly this reason.
- **The healthcheck needs `bash`, not `sh`.** The image has no `curl` or `wget`, so the
  check speaks raw HTTP over bash's `/dev/tcp`. `CMD-SHELL` runs `/bin/sh` (dash), where
  that does not exist - the first version of this healthcheck failed every probe with
  `cannot create /dev/tcp/...: Directory nonexistent`. `CMD` with an explicit `bash`, and
  single-quoted YAML so `\r\n` survives parsing.
- **Changing `orthanc_aet` later is not free.** Every modality configured to send here
  references it.
- **The image bundles far more plugins than are enabled.** Viewers, an S3 storage backend,
  an education plugin. None of them load unless named in `orthanc_plugins`. Enabling one is
  a decision about attack surface and about its licence.

## GDPR

This role handles the most sensitive data in the kit, and more directly than any other.

- **DICOM metadata is personal data even before the image is looked at.** Patient name, date
  of birth, referring physician and accession number travel in the header of every instance.
  There is no configuration in which this archive holds anonymous data by default.
- **No retention policy is set.** How long studies stay is an obligation the institution has
  and this kit cannot guess. Orthanc keeps what it is given until told otherwise.
- **No seed, no example data, ever.** Not even to reproduce a fault - construct a synthetic
  study instead. The same rule as the rest of the repository, and it matters most here.
- **The backup role snapshots the DICOM volume.** That means the encrypted restic
  repository contains patient images. Where it lives, and who can decrypt it, is part of the
  institution's processing record - see `docs/roles/backup.md`.
