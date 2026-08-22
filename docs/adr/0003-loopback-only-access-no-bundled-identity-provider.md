# ADR 0003: Loopback-only access, and no bundled identity provider

**Status:** accepted · **Date:** 2026-08-14, criterion sharpened 2026-08-22 · **Affects:** every role; `ARCHITECTURE.md`; `CONVENTIONS.md`; issues #31, #32, #34

## The question answered here

`ARCHITECTURE.md` promised a shared Docker network (`linumed-net`) so that Caddy could
route to every service, and named SSO via Authentik as the content of v0.2. Neither was
built. This records that both are now deliberately dropped, what replaces them, and why a
kit aimed at hospitals ships *less* here rather than more.

## Context

Every service in Linumed Base binds to `127.0.0.1` or publishes no host port at all. Grafana,
Prometheus and the BridgeLink admin interface are reached with `ssh -L`. Caddy proxies
nothing by default (`caddy_sites: []`); it exists for the operator's own applications.

This was not an accident, and not an unfinished state. On **2026-08-10** the question "how
should Grafana be reachable?" was decided explicitly in favour of "loopback only, access via
SSH tunnel". The alternative on the table was "via Caddy, with a subdomain", described at
the time as requiring a shared Docker network, making Grafana's own authentication the only
protective layer, and demanding a ufw/GDPR trade-off because Loki logs can contain personal
data. A configurable middle ground was rejected as well. BridgeLink then followed the same
pattern.

The reason this ADR exists at all is that the decision was made but never written down, so
`ARCHITECTURE.md` kept describing the rejected design as the target picture. A roadmap
drafted on 2026-08-14 consequently treated `linumed-net` as an unfinished task and SSO as
the natural next step - reviving a design that had already been turned down, because nothing
recorded that it had been.

## Options considered

**A · SSH tunnel (the status quo).** Only the SSH port is open. Strong, well-understood
authentication; no additional component; nothing exposed. Two real weaknesses: reading a
dashboard requires a shell on a host that processes patient data, and Grafana ships with a
single shared admin login, so there is no record of who saw what.

**B · Caddy plus a bundled Authentik.** Solves identity and audit properly: real users,
roles, MFA, central revocation. Costs an internet-facing HTTP surface in front of services
handling patient data, four additional containers, and a single point of compromise that
spans every site. BridgeLink's Java admin client does not do browser-based authentication,
so `forward_auth` likely does not cover the primary admin path anyway. Availability couples
the ability to diagnose an incident to the identity provider still being up - so the SSH
tunnel is kept as the break-glass path regardless, meaning both models are maintained
forever.

**C · Mesh VPN (Headscale/WireGuard).** Technically the most elegant: services stay bound to
loopback, nothing is exposed, revocation is central. It is what the Linumed development
server actually does. **Rejected on scope, not on merit.** A mesh needs a coordination
server, clients on every accessing device, and someone to operate both. Linumed Base ships
none of that. The role would do nothing on its own, the institution's monitoring access
would depend on infrastructure the kit neither delivers nor runs, and if the service
provider hosts the coordination plane, the blast radius spans every site they serve - the
opposite of on-premise by design. Mesh networking is a layer *above* a hardened Debian host
and belongs to the operator, not to the base system.

The criterion that decided it was not in any document and is now: **after the playbooks run,
the system works, without the institution having to supply a second subsystem.** A component
that only becomes useful once someone else provides a coordination server or a directory is
not a shipped feature; it is a documented gap.

### The criterion has three levels, not two (added 2026-08-22)

As first written, this reads as a yes-or-no test, and applied that way it rejects too much.
`caddy` serves nothing until `caddy_sites` is set; BridgeLink transports nothing until
channels exist; Orthanc receives nothing until a modality is pointed at it and
`orthanc_publish_dicom_port` is deliberately turned on. By a binary reading all three fail,
which is plainly the wrong answer - that is what infrastructure *is*.

What the criterion is actually about is **what is missing**:

| | Roles | What is missing |
|---|---|---|
| **1. Works on its own** | `common`, `docker`, `monitoring`, `backup` | Nothing. Hardening, a container runtime, observability and backups need no input to start doing their job. |
| **2. Ready but empty** | `caddy`, `bridgelink`, `orthanc` | **Content**, supplied by the operator in the course of normal use: sites, channels, images. |
| **3. Useless without a second system** | *rejected: Authentik, a mesh-VPN role, a clinical data repository* | **Another system**, which somebody has to procure, run and integrate before this one does anything. |

Level 2 is not a weakness and is not what this ADR rejects. The distinction is whether the
missing piece is content or a system - and, for content, whether the operator already has it.
A radiology department without imaging devices is not a scenario; an institution without a
directory server is an everyday one.

Level 3 is the failure this ADR is about, and the added cost is not the component itself but
the project that has to happen before it is worth anything.

**How to use this when a new role is proposed:** name what the role needs before it does its
job, and decide which of the three that is. Level 3 needs an ADR arguing why it is an
exception, not a paragraph explaining that it would be nice to have.

## Decision

**Access stays as it is: everything on loopback, reached through an SSH tunnel.** Option A,
not as an interim compromise but as the architecture.

**No identity provider is bundled.** Authentik is not added; neither is Keycloak or any
substitute.

**No mesh VPN role is added.**

**`linumed-net` is dropped** in the sense it was written: a shared network for exposing
Linumed Base services through Caddy. Issues #31, #32 and #34 are closed accordingly.

Three things are adopted instead, all of which stay inside existing roles and add no
component:

1. **Tunnel-only SSH users.** `sshd` can restrict an account to a single forwarding target
   and deny it a shell. Verified in a throwaway container on 2026-08-14:

   ```
   Match User viewer
       PermitTTY no
       AllowTcpForwarding local
       PermitOpen 127.0.0.1:3000
       ForceCommand /usr/sbin/nologin
   ```

   ```
   ssh viewer@host whoami            -> This account is currently not available.
   ssh -N -L 19000:127.0.0.1:3000    -> HTTP 200          (Grafana)
   ssh -N -L 19090:127.0.0.1:9090    -> administratively prohibited  (Prometheus)
   ```

   This is *finer* granularity than option B would have provided at the proxy layer, and it
   is enforced by `sshd` itself.

2. **Real Grafana users instead of one shared admin.** Grafana has local users, teams and
   roles. The shared admin is a provisioning gap, not a missing SSO feature.

3. **OIDC as an optional connection point, not a shipped provider.** Many institutions
   already run a directory. A few optional variables pointing at an *existing* identity
   provider cost no containers and change nothing while unset.

## Consequences

**Accepted downsides.**

- On-call from a phone does not work. Diagnosing an alert needs a machine with an SSH key.
- Offboarding still means removing keys per host. Tunnel-only accounts shrink what a
  forgotten key opens - one port instead of a shell - but do not centralise revocation.
- No MFA on the access path.
- Institutions wanting dashboard access for staff who cannot use SSH are not served. The
  target audience is IT service providers, so this is accepted rather than solved.

**What this buys.** No internet-facing management surface, no additional CVE or patch
surface, no dependency on a component the kit does not ship, and no availability coupling
between diagnosing an incident and an identity provider being reachable.

**Composability, the property that mattered most.** Because everything stays bound to
loopback, Linumed Base runs over whatever network the operator already has - a corporate VPN,
a mesh, a jump host, the hospital LAN - without knowing about any of it. A service provider
running a mesh across their fleet still gets option C; it is simply their decision, one
layer up, instead of freight carried by the base system. Options B and C would each have
dictated a network architecture to every institution.

**Explicitly still open, and not covered by this ADR.** Caddy cannot currently reach a
containerised application the operator deploys in its own Compose stack. Measured on
2026-08-14: an app published on `127.0.0.1:8080` answers the host with HTTP 200 and a
Caddy-like container with nothing, because host loopback is not the gateway address a
container arrives on. That is the *second* job `linumed-net` was carrying, it is unrelated
to exposing Linumed Base services, and it does not go away with this decision. Tracked as
**#39**.

### When to revisit this decision

- **A customer needs browser-based dashboard access for people without SSH**, for example
  clinical staff looking at their own metrics. Then option B has to be reconsidered on its
  merits, because no amount of SSH hardening produces a browser login.
- **Linumed Base grows a component that must be reachable from outside by design** - a patient-
  or partner-facing endpoint rather than an admin interface. The reasoning here covers
  management interfaces only.
- **`sshd` restrictions turn out to be insufficient in practice**, for instance if operators
  routinely need more than one forwarded port and the configuration becomes unmanageable.

## Sources

- Session transcript of 2026-08-10 - the original access decision and the rejected
  alternatives.
- Verification runs of 2026-08-14 on the maintainer's dev host: tunnel-only `sshd`
  configuration, and
  container-to-host reachability for a loopback-published port.
- `ansible/roles/caddy/defaults/main.yml` - "both stacks need a shared Docker network […]
  not automated by this role yet".
- Issues #31 (shared network), #32 (Caddy route to BridgeLink), #34 (Authentik role), #39
  (Caddy to operator containers).
