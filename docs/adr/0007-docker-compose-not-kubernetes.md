# ADR 0007: Docker Compose, not Kubernetes

**Status:** accepted · **Date:** 2026-08-20 · **Affects:** `caddy`, `monitoring`, `bridgelink`, and every future service role; `CONVENTIONS.md`; `ARCHITECTURE.md`

## The question answered here

Kubernetes was excluded in three places in this repository - `CONVENTIONS.md` twice,
`docs/ROADMAP.md` once - and **none of them gave a reason**. The roadmap deferred to the
convention; the convention simply asserted it. An exclusion with no recorded reasoning
cannot be defended when someone asks, and cannot be revisited intelligently when
circumstances change. It also invites being quietly reversed out of habit, which is the
failure mode this repository explicitly guards against elsewhere.

Hospitals do run Kubernetes. The question is not whether it exists in this market - it
does - but whether this kit should target it.

## Context

Linumed Base turns one standard Debian host into a hardened base: SSH hardening, a
firewall, automatic security updates, a reverse proxy, an HL7/FHIR integration engine, an
observability stack, and encrypted backups. The service roles deploy Docker Compose
stacks.

Kubernetes solves a different problem. It schedules workloads across nodes, distributes
load, restarts and reschedules on failure, and rolls out updates without downtime. Those
are real and valuable properties - for an application platform with variable load and
availability requirements.

What this kit deploys is not that. It is a small, fixed set of infrastructure services on
a single machine: one reverse proxy, one integration engine, one monitoring stack, one
backup timer. There is nothing to schedule and nothing to distribute. Running them under
an orchestrator would add a scheduler to a problem that has no scheduling in it.

The kit's security model is also host-level and not portable: everything binds to
`127.0.0.1`, ufw governs what may be reached, and access goes through an SSH tunnel
(ADR 0003). Under Kubernetes those controls live in the cluster - NetworkPolicies with a
CNI that supports them, no Service or Ingress plus `kubectl port-forward` - and the
cluster is not something this kit owns or configures.

## Options considered

**Compose only (chosen).** One deployment model, one security model, one set of documentation.

**Compose plus optional Kubernetes manifests or Helm charts in this repository.** Rejected.
This would not be a switch, it would be a second product: charts, a different security
model, a cluster in CI, its own operations handbook, and every future role written twice.
At the maintenance budget this project has, that reliably produces two half-maintained
halves. ADR 0005
already narrowed this repository's scope on exactly that basis, deciding that
`docker/<role>/` references for all six roles cost more than they returned.

**Kubernetes only.** Rejected on the criterion ADR 0003 established and this decision
applies consistently: a component that only becomes useful once the institution supplies
a coordination server or directory is not a feature, it is a documented gap. **A
Kubernetes variant requires the institution to supply a cluster.** The same criterion that
removed SSO, `linumed-net` and a mesh-VPN role from this kit removes Kubernetes from it
too. That is not a coincidence - it is what the criterion is for.

**A separate repository, later, if it is ever warranted.** Kept open. It would share the
decisions recorded in these ADRs, not the code - see "When to revisit" below.

## Decision

Service roles deploy **Docker Compose stacks on a single host**. Kubernetes, Helm and k8s
manifests do not enter this repository.

## Consequences

### What this buys

**It works after the playbook runs, on a machine the operator already has.** No cluster,
no control plane, no CNI decision, no storage class. That is the property this kit is
built around, and the one an evaluator can verify in an afternoon on a spare server.

**It stays debuggable by one person at three in the morning.** `docker compose logs`,
`docker inspect`, `systemctl status`, `ufw status`. The service provider maintaining a
clinic's infrastructure does not need cluster expertise to work out why a channel stopped.

**The security model is enforceable by the kit itself.** ufw, loopback binding and SSH
tunnels are host-level controls the roles configure directly and the VM test verifies. In
a cluster those guarantees would depend on components this kit does not install and cannot
check.

### What this costs, stated plainly

**No high availability.** One host means a single point of failure. If an HL7 interface
must survive the loss of a machine, this kit does not provide that, and no amount of
Compose configuration changes it. That is a genuine functional limitation, not a matter of
taste, and it belongs in any evaluation.

**No rolling updates, no scheduling, no resource limits across nodes.** An update means a
container restart. For the services here that is seconds, but it is downtime.

**Service providers who standardise on Kubernetes will see Compose as a step backwards.**
That reaction is understandable and this decision accepts it rather than arguing with it.

### The part that is not exclusive, and is easy to miss

**A hospital running Kubernetes still needs hardened Debian nodes.** Half of this kit does
not care what runs on top:

- `common` - SSH hardening, ufw, fail2ban, unattended-upgrades, NTP. No Docker dependency
  at all.
- `backup` - restic. `backup_paths` is a variable, and was deliberately written to back up
  "whatever is actually present" rather than assuming particular roles.
- `docker` - installs the container runtime, which a node needs either way.

Only `caddy`, `monitoring` and `bridgelink` are Compose-coupled. So "Kubernetes is out of
scope" does not mean "there is nothing here for you" - it means the *service stacks* are
Compose. The node baseline is not, and a Kubernetes shop can use it for the machines under
its cluster.

That subset has its own playbook since 2026-08-20: `ansible/playbooks/node-baseline.yml`
(issue #70). It is applied to the pristine VM on every relevant push, checked for
idempotency, and checked for **effect** - ufw active, password authentication off, Docker
running, backup timer enabled, and no service container started. Until that existed, the
paragraph above was a claim rather than a feature, and it is worth noting that the claim
came first: it was written from counting which roles ship a Compose file, which is the same
shape of reasoning that produced the volume-name error in #68.

### What transfers even though the code does not

The decisions here are not Compose-specific, and a future Kubernetes effort would inherit
them: management interfaces are not publicly exposed; secrets are files, not environment
variables; configuration lives in a mounted directory rather than a mounted file (#63 -
and note that Kubernetes has the same trap in a different shape, since a ConfigMap volume
updates in place *except* under `subPath`); a component that requires the institution to
supply a subsystem does not ship.

## When to revisit this decision

Any one of these is reason to reopen it:

- **A concrete deployment needs high availability for the integration engine.** Not "would
  be nice" - an actual requirement in an actual project. That is the one gap Compose
  cannot close.
- **The audience shifts.** If service providers serving clinics standardise on Kubernetes
  to the point where a Compose kit is not evaluated at all, the market has answered the
  question.
- **The service set grows beyond what one host sensibly carries.** Today it is four
  stacks; that is comfortably a single machine.

If it is reopened, the answer is a **separate repository**, sharing these decisions and
this documentation, not a flag in this one. Two deployment models inside one repository
produce two that do not work rather than one that does.

## Sources

- [ADR 0003](0003-loopback-only-access-no-bundled-identity-provider.md) - the
  "must work without the institution supplying a subsystem" criterion this decision applies
- [ADR 0005](0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md) - the
  precedent for narrowing scope rather than completing it, on single-maintainer grounds
