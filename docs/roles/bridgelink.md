# bridgelink: HL7/FHIR integration engine

## Problem

Clinical systems talk to each other in HL7 v2, FHIR, DICOM and a good number of
home-grown formats. An integration engine receives messages, transforms them and routes
them onward - it's the connective tissue between HIS, LIS, PACS and everything else.
This role deploys **BridgeLink** with a PostgreSQL backend as a Docker Compose stack.

## Why BridgeLink and not Mirth Connect

**BridgeLink is not a replacement product, it's the same codebase under a different
name.** Same channel XML, same administrator, same transformers and connectors; the Java
packages are still called `com.mirth.connect`. Anyone who knows Mirth knows BridgeLink,
and channels are exportable between all variants.

Background: NextGen Healthcare moved Mirth Connect to a **purely commercial, proprietary
license in March 2025**, closing the source from 4.6 onward. The open-source line has
continued under new names since - Linumed Base follows that open line because the kit is
FOSS-only, and the last free Mirth version (4.5.2) gets no more security fixes.

The full reasoning, with every evaluated alternative, the downsides accepted along the
way (among them that RFPs say "Mirth Connect" and not "BridgeLink"), and the conditions
for revisiting it, is in
**[ADR 0001](../adr/0001-bridgelink-statt-mirth-connect.md)** - that document is meant as
the answer to "why not Mirth?" and can be quoted as such.

## If the institution wants to use licensed Mirth Connect

Linumed Base doesn't force a fork on anyone - it ships a FOSS default. Two paths:

**Reliable: take the channels with you.** Channels, code templates and transformers can
be exported from BridgeLink and imported into licensed Mirth Connect (or OIE), because
every variant shares the same codebase. An institution's actual integration work is
therefore not tied to this role. That's the dependable guarantee.

**Untested: swap the image.** `bridgelink_image` is a variable, and this role's
container conventions (`MP_*` variables, the `mirth_properties` secret) originally come
from NextGen's own `connect-docker`. Even so, swapping the image is **neither tested nor
guaranteed**: the install paths differ (`/opt/bridgelink` vs. `/opt/connect`), and we
don't know the distribution form for licensed 4.6+ images - on Docker Hub,
`nextgenhealthcare/connect` stops at 4.5.2. Anyone taking this route has to verify it
against their own license distribution.

## Variables

All variables are prefixed `bridgelink_*` and live in
`ansible/roles/bridgelink/defaults/main.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `bridgelink_image` | `innovarhealthcare/bridgelink:26.6.0-dhi-slim` | Hardened image (Debian 13, no shell, non-root UID 65532) |
| `bridgelink_postgres_image` | `postgres:17.10-alpine` | Backend database |
| `bridgelink_admin_port` | `8443` | Bound to `127.0.0.1` only - access via SSH tunnel |
| `bridgelink_db_password` | `""` (required) | The role aborts in its preflight without a value |
| `bridgelink_keystore_storepass` | `""` (required) | Keystore password - **don't change after the first start** |
| `bridgelink_keystore_keypass` | `""` (required) | Key password inside the keystore - same rule |
| `bridgelink_server_id` | `""` (required) | Generate once with `uuidgen` and keep it stable permanently |
| `bridgelink_max_heap_mb` | `512` | JVM maximum heap |
| `bridgelink_stop_grace_period` | `35` | Seconds before a hard kill - deliberately above Docker's 10s default |
| `bridgelink_exporter_enabled` | `false` | Prometheus exporter sidecar - opt-in, see [Monitoring](#monitoring) |
| `bridgelink_exporter_image` | `python:3.13.15-alpine` | Pinned upstream image; the exporter script is bind-mounted into it |
| `bridgelink_exporter_port` | `9151` | Bound to `127.0.0.1` only - for debugging by hand, **not** how Prometheus scrapes it |
| `bridgelink_exporter_metrics_network` | `linumed-base-metrics` | Shared Docker network created by the monitoring role; must match `monitoring_metrics_network_name` |
| `bridgelink_exporter_user` | `""` (required if enabled) | A **read-only** BridgeLink user, not `admin` |
| `bridgelink_exporter_password` | `""` (required if enabled) | Ansible Vault |
| `bridgelink_exporter_verify_tls` | `false` | Only set true if the keystore holds a certificate that validates |

The four required values belong in **Ansible Vault**, never in plaintext in a checked-in
inventory.

## What gets changed

- `{{ bridgelink_deploy_dir }}/docker-compose.yml`
- `{{ bridgelink_deploy_dir }}/secrets/` (0700, root) holding `mirth.properties` and
  `db_password` - the password files are plaintext, that's how file-based Docker secrets
  work. `mirth.properties` is owned by UID 65532 (0400), or the hardened container can't
  read it.
- Containers `linumed-base-bridgelink` and `linumed-base-bridgelink-db`, volumes for app
  data, custom extensions and the database.
- With `bridgelink_exporter_enabled`: additionally
  `{{ bridgelink_deploy_dir }}/bridgelink_exporter.py`, the
  `secrets/exporter_password` file (UID 65532, 0400) and the container
  `linumed-base-bridgelink-exporter`.

## Access

```bash
ssh -L 8443:127.0.0.1:8443 <user>@<host>
# then: https://localhost:8443
```

The certificate is self-signed (BridgeLink generates its own keystore on first start) -
the browser warning is expected here, and the traffic already runs through the SSH
tunnel anyway.

For administration there's the separate **Administrator Launcher** (also MPL-2.0) or
**WebAdmin** as its own container. The chosen `-slim` image deliberately no longer
includes the old Swing client.

## Verification

Container status alone says **nothing** here (see pitfalls). What counts:

```bash
# Does the engine actually respond - returns the version number
curl -sk -H 'X-Requested-With: check' https://127.0.0.1:8443/api/server/version

# Is the database backend healthy
docker inspect linumed-base-bridgelink-db --format '{{ "{{" }}.State.Health.Status{{ "}}" }}'

# Is the engine actually running against PostgreSQL (not the built-in Derby DB)?
docker logs linumed-base-bridgelink 2>&1 | grep -i "postgres"
```

The role runs this same check itself right after deployment and aborts if the engine
doesn't respond within five minutes.

## Monitoring

BridgeLink serves **no `/metrics` endpoint** - verified against `26.6.0-dhi-slim`, `GET
/metrics` is a 404. Without the exporter described here, the only thing Prometheus ever
sees for it is cAdvisor's container-level CPU, RAM and network. Those numbers cannot show
a stopped channel or a filling queue, which are precisely the failure modes that matter
for an integration engine: the container stays healthy, the CPU stays idle, and messages
quietly stop being delivered.

The role ships a small exporter (`ansible/roles/bridgelink/files/bridgelink_exporter.py`)
that runs as a sidecar in the BridgeLink stack, queries the engine's REST API and
translates it into Prometheus metrics.

### Enabling it

The exporter is **off by default**, and not out of caution: it needs a BridgeLink login,
and BridgeLink's user database belongs to the operator - it is created on first login to
the Administrator, after this role has run. There is no credential the role could invent.

1. Log into the Administrator once and create a user for monitoring. Give it read access
   only; the exporter issues nothing but `GET /api/channels/statuses` and
   `GET /api/system/stats`.
2. Put its credentials in Vault and set:

   ```yaml
   bridgelink_exporter_enabled: true
   bridgelink_exporter_user: "metrics"
   bridgelink_exporter_password: "{{ vault_bridgelink_exporter_password }}"
   ```

3. Turn on the matching scrape job in the monitoring role - **both switches are needed**,
   they are deliberately separate so a scrape job never points at a target that was never
   deployed:

   ```yaml
   monitoring_scrape_bridgelink: true
   ```

**Order matters here.** Prometheus reaches the exporter over a Docker network that the
*monitoring* role creates, so monitoring has to have run on this host before BridgeLink
does. `site.yml` already orders them that way - and it is the only playbook in the repo -
but applying just this role (with a playbook of your own - there are no Ansible tags to
select on) to a host with no monitoring stack fails on a missing external network once the
exporter is enabled.

### Metrics

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `bridgelink_up` | gauge | - | 1 if the API answered this scrape |
| `bridgelink_channel_state` | gauge | `channel`, `channel_id`, `state` | 1 on the active state, 0 on the rest |
| `bridgelink_connector_state` | gauge | + `connector`, `connector_type` | Same, per connector |
| `bridgelink_channel_messages_total` | counter | + `status` | `received` / `sent` / `filtered` / `error` |
| `bridgelink_connector_messages_total` | counter | + `status` | Same, per connector |
| `bridgelink_channel_queued_messages` | gauge | `channel`, `channel_id` | Queue depth |
| `bridgelink_connector_queued_messages` | gauge | + `connector` | Queue depth per connector |
| `bridgelink_channels_deployed` | gauge | - | Number of deployed channels |
| `bridgelink_jvm_memory_*_bytes` | gauge | - | Heap allocated / free / ceiling, from the engine's own view |
| `bridgelink_cpu_usage_ratio` | gauge | - | Process CPU as the engine reports it |
| `bridgelink_disk_*_bytes` | gauge | - | Free / total on the engine's data filesystem |

The counters come from Mirth's **lifetime** statistics, not the resettable ones shown in
the Administrator's dashboard. "Clear statistics" and a redeploy both zero the latter,
which would make a Prometheus counter run backwards and produce phantom spikes in
`rate()`.

Alert rules for these ship in the monitoring role and are dormant until the metrics exist
(same pattern as the backup rules): `BridgeLinkDown`, `BridgeLinkChannelNotStarted`,
`BridgeLinkConnectorNotStarted`, `BridgeLinkQueueBacklog`, `BridgeLinkErrorRate`,
`BridgeLinkHeapHigh`.

### Why a script instead of an off-the-shelf exporter

`prometheus-community/json_exporter` was the first candidate and was **rejected after
testing it against a real instance**. BridgeLink's JSON output is produced by
XStream/Jettison from its XML model, so a list containing exactly one entry serialises as
an object and a list of two or more as an array:

```
1 channel  -> {"list": {"channelStatistics": { ...single object... }}}
2 channels -> {"list": {"channelStatistics": [ ..., ... ]}}
```

json_exporter's JSONPath therefore matches nothing at all on a single-channel
installation - and it reports the scrape as successful while emitting zero metrics. A
monitoring gap that announces itself as healthy is worse than no monitoring. Measured with
`{.list.channelStatistics[*]}`, `{.list.channelStatistics}` and `{..channelStatistics}`;
all three produce metrics for two channels and silence for one. The XML representation has
no such ambiguity, which is why the exporter asks for `Accept: application/xml`.

The existing community exporters (`vynca/mirth_exporter`,
`teamzerolabs/mirth_channel_exporter`, `feathersct/mirth-prometheus-exporter`) target
Mirth 3.3-3.7, are unmaintained, and publish no pinned container image. `vynca`'s shells
out to the Mirth CLI, which does not exist in the `-dhi-slim` image at all.

The script is **standard library only** by design. That is what allows it to run inside a
pinned upstream `python` image with the file bind-mounted read-only, so this repo does not
have to build, scan and host a container image of its own for it. The read-only bind mount
of a repo-managed file is the documented exception to CONVENTIONS.md's "named volumes
only" rule.

### How Prometheus reaches it

By **container name over a shared Docker network**, not over the published port. The
exporter joins `linumed-base-metrics`, which the monitoring role creates and Prometheus
sits on, and the scrape target is `linumed-base-bridgelink-exporter:9151`.

The obvious alternative - publish a host port and scrape `host.docker.internal` like the
Node Exporter job does - does not work here, and the reason is worth understanding before
anyone "simplifies" it back (issue #64):

- A container port published on `127.0.0.1` is **not** reachable from another container
  via the host gateway. Measured: the request simply times out.
- Publishing it on all interfaces instead would make it reachable - and would bypass ufw
  completely, because Docker inserts its own rules ahead of the firewall's. That is the
  one thing this repo's network doctrine does not permit.
- The Node Exporter job gets away with `host.docker.internal` only because Node Exporter
  is a **native systemd service**, not a container, so ufw can actually protect its port.
  That is the half of the pattern that does not transfer.

The same reasoning applies in reverse, which is why moving the exporter into the monitoring
stack is not a way out either: BridgeLink's own admin port is on loopback for the same
doctrine. A shared network is the only arrangement that needs no host port at all.

`bridgelink_exporter_port` still publishes 9151 on loopback - for a human with `curl`, not
for Prometheus.

### Verification

```bash
# From the host - the exporter is on loopback
curl -s http://127.0.0.1:9151/metrics | grep bridgelink_up

# Is Prometheus actually scraping it?
curl -s http://127.0.0.1:9090/api/v1/targets \
  | grep -o '"job":"bridgelink"[^}]*"health":"[a-z]*"'
```

Automated coverage: `test/vm-test.sh` runs a third `site.yml` pass with the exporter
switched on (issue #62). It creates a BridgeLink user over the REST API first - a
throwaway VM has no operator to do it - then checks the secret's ownership, the container
healthcheck, `bridgelink_up`, and that Prometheus's `bridgelink` job is healthy. The two
default-off runs before it cannot see any of this, which is the general point: a feature
behind a default-off flag has no coverage until a test turns it on.

`bridgelink_up 0` means the exporter is alive but the engine is not answering - that is a
deliberate distinction. The exporter reports the failure as data rather than failing the
scrape, so "BridgeLink is down" stays separate from "the exporter is gone", and its
container healthcheck checks only its own liveness. Restarting the exporter because the
engine it watches is down would delete the metric that says so, exactly when it is needed.

## Pitfalls

- **"Container running" doesn't mean "engine running" here.** The hardened image can't
  have a healthcheck (no shell, no `wget`/`curl` in the image - the same situation as
  Loki). Docker Compose treats a container with no healthcheck as done the moment it's
  running - an engine that crashes on startup and sits in a restart loop looks like a
  successful deployment as a result. That's exactly what happened while this role was
  built. Which is why the role checks the API, not container status.
- **Don't change the keystore passwords after the first start.** BridgeLink generates a
  keystore on first start and encrypts it with these passwords. Change them later and the
  existing keystore becomes unreadable.
- **Keep `bridgelink_server_id` stable.** If the ID changes, BridgeLink believes it's a
  different server. That's why it's set explicitly as a variable instead of being left to
  the volume.
- **Channel ports are not published by this role.** An HL7 MLLP listener needs a port
  reachable from outside - that's a deliberate per-site decision with real security
  consequences, and a published container port bypasses ufw entirely (see
  `docs/roles/common-ufw.md`). Anyone opening channels to the outside has to do it, and
  secure it, themselves.
- **The exporter needs its own BridgeLink user, and the role cannot create it.**
  BridgeLink's user database is the operator's, and it only exists after the first
  Administrator login. Enabling `bridgelink_exporter_enabled` without credentials aborts
  in the preflight rather than deploying an exporter that authenticates as nobody.
- **Passwords are deliberately not in environment variables.** Env vars are readable by
  anyone allowed to run `docker inspect` and end up in the container config on disk.
  Hence file-based Docker secrets.

## GDPR

Unlike the rest of this repo's roles, an integration engine processes **real patient
data** in normal operation - HL7 messages carry names, dates of birth, diagnoses. That
has consequences beyond this role:

- **Message storage is configurable per channel.** BridgeLink stores messages by default
  for troubleshooting. How long, and how much, needs a deliberate per-channel decision
  (storage mode, pruning) - that's data minimization, not a defaults question. This role
  ships an empty engine; the channels and their retention are the institution's own
  integration work.
- **The database can therefore hold patient data.** For backups (the `backup` role, #7),
  that's the difference between "securing infrastructure" and "processing health data" -
  plan encryption and retention accordingly.
- **No channel is pre-configured**, so no data flows immediately after deployment.
  Processing only begins with the first channel.
