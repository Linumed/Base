# Security Policy

Linumed Base provisions infrastructure that healthcare institutions run patient-relevant
systems on. A vulnerability here can affect environments where the operator has limited
freedom to patch quickly, so this document says plainly how to report one and what to
expect in return.

## Reporting a vulnerability

**Report privately, by email: security@linumed.com**

**Do not open a public issue for a security problem.** Issues in this repository are
public once the repository is; a report there is a disclosure, not a report.

Useful in a report, roughly in order of usefulness:

- Which role, script or template is affected, and which version or commit.
- What an attacker gains, and what access they need to start with (unauthenticated from
  the network, an existing tunnel user, a local account on the host, ...). This matters
  more than a severity score.
- Steps to reproduce, ideally against a throwaway VM the way `test/vm-test.sh` builds
  one.
- Whether the finding is already public elsewhere.

Reports in German or English are equally welcome.

## What to expect

The numbers below are what this project can actually honour, not a service-level
agreement, and there is no paid support tier that changes them:

- **Acknowledgement of receipt within 7 days.** If you have heard nothing after that,
  assume the mail did not arrive and follow up.
- **An initial assessment within 30 days** - whether the report is accepted, and a rough
  idea of the fix timeline.
- **Credit in the release notes** if you want it, or none if you prefer.

Please allow a reasonable period for a fix before publishing. There is no fixed embargo
demanded here and no bug bounty offered.

## Which versions get fixes

Only the latest release. This project has no long-term-support branches; there is no
capacity to maintain several in parallel, and saying otherwise would be worse than
saying nothing. Update to the current release before reporting, if you can.

## Scope

Linumed Base is a set of Ansible roles plus Compose stacks. That shapes what a security
report against *this* repository can be about.

**In scope:**

- The roles, playbooks, templates and scripts in this repository - insecure defaults,
  a hardening step that does not do what it claims, secrets ending up somewhere readable,
  a firewall or SSH rule with a hole in it.
- Documentation that leads an operator into an insecure configuration by following it.
- Pinned container image versions with known vulnerabilities that have a fixed version
  available. This is checked weekly in CI by `scripts/scan-images.py`, and findings that
  cannot be fixed from here - because the image is already on its newest upstream tag - are
  recorded with a reason in `security/accepted-image-findings.txt` rather than left
  unstated. If you find one that is neither fixed nor recorded, that is a valid report.

**Out of scope here** (report these to their own maintainers):

- Vulnerabilities in the upstream software this kit deploys - Caddy, Grafana, Prometheus,
  Loki, BridgeLink, PostgreSQL, restic, Docker itself. A *pin* that leaves a known-fixed
  vulnerability in place is in scope; a flaw in the software as such is not ours to fix.
- Anything the operator runs *on top of* Linumed Base. This kit provides the base; the
  applications, their data and their own exposure remain the operator's responsibility.

## What this kit does and does not protect

Stated here so a report can be judged against the actual design intent, not an assumed
one:

- **Management interfaces are bound to `127.0.0.1` and reached through an SSH tunnel.**
  There is no bundled identity provider and no reverse-proxy route to any of this kit's
  own admin UIs - a deliberate decision, see
  [ADR 0003](docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md). "Grafana
  has no login page on the public internet" is the design, not a finding.
- **A published Docker container port bypasses ufw.** This is Docker's behaviour, not a
  defect in this repository; the roles work around it by binding to loopback. A role that
  publishes a port on `0.0.0.0` without saying so *is* a finding.
- **Secrets belong in Ansible Vault**, never in the inventory in plain text. The roles
  refuse to deploy without the required ones being set. A code path that logs or echoes a
  secret is a finding.
- **Physical access, network segmentation, and the operator's own backup key custody**
  are outside what any playbook can enforce.
