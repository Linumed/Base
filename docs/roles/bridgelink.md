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
continued under new names since - Linumed OS follows that open line because the kit is
FOSS-only, and the last free Mirth version (4.5.2) gets no more security fixes.

The full reasoning, with every evaluated alternative, the downsides accepted along the
way (among them that RFPs say "Mirth Connect" and not "BridgeLink"), and the conditions
for revisiting it, is in
**[ADR 0001](../adr/0001-bridgelink-statt-mirth-connect.md)** - that document is meant as
the answer to "why not Mirth?" and can be quoted as such.

## If the institution wants to use licensed Mirth Connect

Linumed OS doesn't force a fork on anyone - it ships a FOSS default. Two paths:

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

The four required values belong in **Ansible Vault**, never in plaintext in a checked-in
inventory.

## What gets changed

- `{{ bridgelink_deploy_dir }}/docker-compose.yml`
- `{{ bridgelink_deploy_dir }}/secrets/` (0700, root) holding `mirth.properties` and
  `db_password` - the password files are plaintext, that's how file-based Docker secrets
  work. `mirth.properties` is owned by UID 65532 (0400), or the hardened container can't
  read it.
- Containers `linumed-os-bridgelink` and `linumed-os-bridgelink-db`, volumes for app
  data, custom extensions and the database.

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
docker inspect linumed-os-bridgelink-db --format '{{ "{{" }}.State.Health.Status{{ "}}" }}'

# Is the engine actually running against PostgreSQL (not the built-in Derby DB)?
docker logs linumed-os-bridgelink 2>&1 | grep -i "postgres"
```

The role runs this same check itself right after deployment and aborts if the engine
doesn't respond within five minutes.

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
