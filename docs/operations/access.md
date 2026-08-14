# Access

Every Linumed OS management interface binds to `127.0.0.1` or publishes no port at
all - none of them are reachable from the network directly, by design. See
[ADR 0003](../adr/0003-loopback-only-access-no-bundled-identity-provider.md) for the
full reasoning and what would change it. This page is the practical "how do I actually
get to it" reference.

## The pattern: SSH port forwarding

Every service below uses the same shape:

```bash
ssh -L <local-port>:127.0.0.1:<remote-port> <user>@<host>
```

Then open `http://localhost:<local-port>` (or `https://` for BridgeLink) in a browser
on your own machine. The tunnel only exists for the lifetime of that SSH session.

| Service | Command | Then open |
|---|---|---|
| Grafana | `ssh -L 3000:127.0.0.1:3000 <user>@<host>` | `http://localhost:3000` |
| Prometheus | `ssh -L 9090:127.0.0.1:9090 <user>@<host>` | `http://localhost:9090` |
| BridgeLink admin | `ssh -L 8443:127.0.0.1:8443 <user>@<host>` | `https://localhost:8443` (self-signed cert, expected) |

Loki and Alertmanager have no host port at all, not even on loopback - they're reachable
only from other containers in the same Compose network by service name. Debugging them
directly needs a temporary container sharing that network namespace; see
[monitoring: Observability stack](../roles/monitoring.md#verification) for the exact
command.

## Who can get in

Access control here is entirely at the SSH layer: whoever has a working SSH key for a
sudo-capable user on the host can reach every one of these services. There is currently
no per-service authentication beyond what the service itself provides (Grafana's login,
BridgeLink's admin login) - Prometheus, Alertmanager and cAdvisor have none at all. A
person with the SSH key effectively has access to everything.

## Known gap

Caddy - the reverse proxy this kit ships - is for the **operator's own applications**,
not for these management interfaces. Today it also can't reach a container the operator
runs in a separate Compose stack without extra, currently undocumented network setup
(tracked as [#39](https://github.com/linumed/linumed-os/issues/39)). That's unrelated to
the access model above; even once #39 is resolved, Grafana/Prometheus/BridgeLink stay
off Caddy's routes on purpose.
