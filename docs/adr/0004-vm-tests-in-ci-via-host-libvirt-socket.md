# ADR 0004: VM tests in CI via the host's libvirt socket

**Status:** accepted · **Date:** 2026-08-14 · **Affects:** `.forgejo/workflows/`, `test/vm-test.sh`, the Forgejo runner configuration on `linumed-dev`; issue #33

## The question answered here

`CLAUDE.md` states the CI target as "pipelines run locally on the dev server: ansible-lint,
libvirt/KVM VM provisioning (`test/vm-test.sh`), idempotency checks". Only `ansible-lint`
runs. The VM tests exist, work, and catch real bugs - but only when started by hand.

Getting them into CI is not a workflow-YAML problem. A CI job needs to create virtual
machines, and how it is granted that ability is a security decision. This records which
mechanism was chosen, and why the more isolated-looking option was rejected.

## Context

Measured on `linumed-dev`, 2026-08-14.

**The runner does not run jobs on the host.** `/srv/data/runner/config.yml` declares a
single label, `docker:docker://node:24-bookworm`, so every job step runs in a fresh
container from that image. That image contains none of what `test/vm-test.sh` needs:

```
$ docker run --rm node:24-bookworm sh -c 'command -v virt-install virsh qemu-img cloud-localds ansible'
(nothing)
```

The runner itself is a container too (`code.forgejo.org/forgejo/runner:12.13.2`,
`privileged: false`, `network: host`), so "run the job on the host instead" would mean
running it inside that Alpine container, which is no closer to libvirt than the job
container is.

**KVM is gated by group, not by capability.** `/dev/kvm` is `crw-rw---- root:kvm`, and only
`m0nit0r` is in `kvm`. An unprivileged container reaches it as soon as the device is passed
through - confirmed by running `qemu-system-x86_64 -accel kvm` in a plain container with
`--device /dev/kvm`: it got past acceleration setup and failed only on a deliberately
invalid kernel path. No `privileged: true` is required for either option below.

**The decisive measurement.** The libvirt socket is `srw-rw-rw-` and authorisation is
handled by polkit (`60-libvirt.rules` grants the `libvirt` group). A plain, unprivileged
container with nothing but the socket bind-mounted connects successfully:

```
$ docker run --rm -v /var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock \
    debian:trixie sh -c 'virsh -c qemu:///system list --all'
 Id   Name   State
--------------------
```

That is full control over the host's VMs, from an otherwise unprivileged container, with no
flags.

**The context that reframes it.** The runner already sets `docker_host: "automount"`, and
its own configuration comment states the intent: "Job-Container bekommen
/var/run/docker.sock automatisch". Access to the Docker socket is root-equivalent on the
host - this repository already argues exactly that in issue #21, which is why Grafana Alloy
was put behind a socket proxy rather than given the socket directly. **Any workflow that
runs on this runner therefore already has host-root-equivalent capability**, entirely
independently of this decision.

**Runtime, measured today.** Three roles (`common`, `docker`, `monitoring`) against a fresh
VM, on this hardware (i5-2400, 4 cores, 15 GB RAM):

| Run | Scope | Wall clock |
|---|---|---|
| Reproduction (#40) | single apply | 6 min 19 s |
| Fix verification | double apply + target checks | 6 min 51 s |
| Phase-3 verification | single apply + target check | 5 min 35 s |

A full `site.yml` double-run adds BridgeLink (JVM image plus PostgreSQL) and `backup`, so it
is substantially longer. Two of the four full-stack attempts made today never got that far:
both died pulling `grafana/loki:3.7.6` from Docker Hub - once with a corrupted layer
(`unpigz: crc32 mismatch`), once with `net/http: timeout awaiting response headers`. Neither
was a code failure.

## Options considered

**A · Mount the host's libvirt socket into the job container.** The job installs
`virtinst`/`libvirt-clients` and talks to the libvirtd already running on the host. Verified
above to work unprivileged. VMs appear alongside any the maintainer started by hand.

**B · Run libvirtd inside the job container.** Needs a purpose-built job image carrying
libvirt, QEMU and OVMF, `/dev/kvm` passed through, and almost certainly `NET_ADMIN` so
`virt-install` can create the tap devices and NAT bridge its default network requires.
Looks better isolated, and was the initially preferred option here.

**Rejected on the evidence.** The isolation it appears to buy is largely illusory on this
runner: a job that wanted to reach host libvirt could simply use the Docker socket it
already has and start a privileged container. So option B pays a real, recurring cost - a
fat custom image to build and maintain, pulled or rebuilt on slow hardware every run, plus
a nested dnsmasq/bridge setup that is its own source of hard-to-diagnose failures - to close
a door that stands open next to it. Isolation that can be trivially bypassed is
documentation, not security.

**C · Give the runner a host-mode label so jobs run outside a container.** The tooling is
all installed on the host already and this would need no image work. Rejected because the
runner is itself a container: a host-mode job would execute inside
`code.forgejo.org/forgejo/runner`, an Alpine image with neither libvirt nor `/dev/kvm`.
Making this work means running the runner natively under systemd instead - a larger change
to a component that currently works, and one that would have to be redone if the runner ever
moves to another machine.

**D · Leave the VM tests out of CI entirely.** Not unreasonable, and there is precedent:
`test/vm-test-netinst.sh` says so in its own header ("NOT part of regular CI […] Run before
releases"). Rejected as the whole answer, because #40 is precisely the class of bug that a
manual-only test lets through - it survived months of green pipelines. But the reasoning
behind that precedent is adopted for *when* the tests run, below.

## Decision

**Option A: the job container gets the host's libvirt socket bind-mounted**, and installs
the libvirt client tooling it needs. No `privileged`, no `/dev/kvm` passthrough, no custom
image.

**The VM tests do not run on every push.** They get their own workflow with a deliberate
trigger (manual dispatch, and optionally a schedule), separate from the `ansible-lint`
workflow, which continues to run on every push and pull request. Rationale: a full run is
minutes of a shared, four-core machine that also carries Forgejo, the staging stack and the
monitoring stack, and the failure mode of running it too eagerly is that it gets disabled
after the third flaky red build - which is how a test stops protecting anything.

## Consequences

**Accepted downsides.**

- A CI job can create, modify and destroy any VM on this host, including ones started by
  hand for unrelated work. `test/vm-test.sh` cleans up by name via a `trap`, so the
  realistic risk is a wrongly-scoped `virsh` command in a future edit, not day-to-day
  operation - but it is a real risk that option B would not have had.
- VM tests and interactive work now contend for the same libvirtd, the same `/dev/kvm` and
  the same RAM. Two full runs in parallel will not fit comfortably.
- The tests will be run less often than a per-push trigger would give.

**This decision rests on a property of the runner, not of libvirt.** It is defensible
*because* `docker_host: automount` already grants job containers root-equivalent access. If
that ever changes - the socket removed, jobs moved behind a socket proxy the way Alloy was
in #21, or the runner reconfigured for untrusted workloads - then mounting the libvirt
socket stops being a marginal addition and becomes the widest hole in the setup. **Revisit
this ADR at that point, not later.** The `automount` behaviour was read from the runner's
configuration and its comment; confirm it against a real job when the workflow is built.

**Docker Hub is the reliability bottleneck, not the code.** Half of today's full-stack
attempts failed on image pulls. A per-push trigger would have made that failure rate
visible as flaky CI. Before the workflow is trusted, the pull path needs addressing -
a pull-through registry mirror on this host, or the Forgejo registry that already exists
here, is the obvious candidate and is worth its own issue.

**Not affected.** `test/vm-test.sh` and `test/vm-test-netinst.sh` keep working unchanged
when started by hand; nothing about this decision changes how they are invoked locally.
`vm-test-netinst.sh` stays out of CI entirely, as its header already states.

### When to revisit this decision

- **The Docker socket stops being mounted into job containers** (see above) - the single
  most important trigger.
- **The runner starts building anything untrusted**, such as workflows from forks or
  contributors. The current reasoning assumes every workflow that runs here is
  maintainer-authored.
- **The runner moves off this machine**, or the dev server stops being the place where VM
  tests run.
- **Runtime becomes the binding constraint** - if a full run grows past what a deliberate
  trigger makes tolerable, the answer is likely to split the suite (per-role smoke tests
  frequently, full `site.yml` rarely), not to change the access mechanism.

## Sources

- Measurements of 2026-08-14 on `linumed-dev`: runner configuration
  (`/srv/data/runner/config.yml`), `docker inspect forgejo-runner`, `/dev/kvm` ownership,
  libvirt socket permissions and `60-libvirt.rules`, and the two container reachability
  probes quoted above.
- Timing from four VM runs performed the same day while fixing #40.
- Issue #21 - the repository's own position that Docker socket access is root-equivalent,
  and the socket-proxy pattern adopted because of it.
- Issue #33 - the open item this ADR unblocks.
- `test/vm-test-netinst.sh` header - the existing precedent for a deliberately non-CI test.
