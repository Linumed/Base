# Architecture Decision Records

Decisions that shape how Linumed Base is built and that will plausibly be questioned
later - recorded with context, evaluated alternatives, and the consequences accepted
along the way.

The goal is not completeness. What lands here meets these criteria:

- The decision needs explaining from the outside (someone asks "why not X?").
- Reversing it would be expensive or have consequences for operators.
- The reasoning isn't readable from the code.

Everything else belongs as a comment at the relevant spot, not here.

| No. | Decision | Status |
|---|---|---|
| [0001](0001-bridgelink-statt-mirth-connect.md) | BridgeLink instead of Mirth Connect as the integration engine | accepted (2026-08-11) |
| [0002](0002-english-as-documentation-language.md) | English as the documentation language | accepted (2026-08-14) |
| [0003](0003-loopback-only-access-no-bundled-identity-provider.md) | Loopback-only access, no bundled identity provider | accepted (2026-08-14) |
| [0004](0004-vm-tests-in-ci-via-host-libvirt-socket.md) | VM tests in CI via the host's libvirt socket | accepted (2026-08-14) |
| [0005](0005-docker-directory-is-a-manual-testing-reference-not-a-mirror.md) | `docker/` is a manual-testing reference, not a required mirror | accepted (2026-08-16) |
| [0006](0006-linumed-base-not-linumed-os.md) | The product is called Linumed Base, not Linumed OS | accepted (2026-08-18) |
| [0007](0007-docker-compose-not-kubernetes.md) | Docker Compose, not Kubernetes | accepted (2026-08-20) |
| [0008](0008-what-the-v1-0-stability-guarantee-covers.md) | What the v1.0 stability guarantee covers | accepted (2026-08-20) |
| [0009](0009-jodogne-orthanc-image-not-orthancteam.md) | `jodogne/orthanc-plugins` as the Orthanc image | accepted (2026-08-21) |
| [0010](0010-internal-versus-interface-variables.md) | Internal variables are a documented list, not an enforced one | accepted (2026-08-21) |
