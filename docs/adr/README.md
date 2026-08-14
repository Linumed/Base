# Architecture Decision Records

Decisions that shape how Linumed OS is built and that will plausibly be questioned
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
