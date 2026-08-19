# Troubleshooting

A symptom-first index across roles. Each role's own page has a more detailed **Pitfalls**
section - this page exists so a symptom that could come from any of several roles has one
place to start, instead of guessing which role's page to open first.

## "the role 'X' was not found"

`ansible-playbook` was run from the repository root instead of `ansible/`.
`ansible/ansible.cfg` sets `roles_path`, and Ansible only loads an `ansible.cfg` from the
current working directory - `cd ansible` first. Every command in this repo, including
`ansible-lint` and `ansible-vault`, assumes that working directory. (Found the hard way
in the README's own quick start - see issue #27.)

## Playbook aborts in a preflight with "refusing to..."

Not a bug - several roles deliberately abort rather than deploy into an unsafe or
half-configured state: `common` (no non-root sudo user with a key before disabling root
login), `monitoring` (no Grafana password, or a half-configured Alertmanager SMTP setup),
`bridgelink` (any of its four required secrets missing), `backup` (no repository or
password set). The fail message says which variable is missing; see
[Deployment](deployment.md) and the required-variables table in
[the README's quick start](https://github.com/Linumed/Base#quick-start) for where
those belong (`group_vars/linumed/vars.yml` vs. `vault.yml`).

## A service is running but I can't reach it, even from the LAN

Working as designed. Every Linumed Base management interface binds to `127.0.0.1` or has
no host port at all - see [Access](access.md) and
[ADR 0003](../adr/0003-loopback-only-access-no-bundled-identity-provider.md). Use an SSH
tunnel.

## A container port is reachable from the LAN even though ufw denies it

**Docker bypasses ufw.** A container port published via `ports:` is reachable despite
active ufw rules, because Docker's own iptables/nftables rules sit ahead of ufw's in the
chain. This isn't a bug in a specific role, it's how Docker's networking works on this
platform - see the security model in [Architecture](../architecture.md#security-model).
The fix is never "add a matching ufw rule"; it's "don't publish the port, or bind it to
`127.0.0.1`".

## A Prometheus target is DOWN that should be up

Check `curl -s localhost:9090/api/v1/targets` first - the exact command is in
[monitoring: Observability stack](../roles/monitoring.md#verification). A green Ansible
run says nothing about this; see
[Deployment: verifying a deployment actually worked](deployment.md#verifying-a-deployment-actually-worked).
If it's specifically the `node` job: this is issue #40's exact symptom
(`monitoring_node_exporter_allow_from` missing or wrong), see
[monitoring: pitfalls](../roles/monitoring.md#pitfalls).

## A second playbook run reports changes when nothing should have changed

A hard requirement for every role in this repo (`CONVENTIONS.md`), so this is worth treating
as a real bug, not routine noise. Known historical causes, in case one matches: a
container with no `command:` override not being pre-pulled before the Compose apply
computes its config hash (hit twice - Grafana/cAdvisor originally, docker-socket-proxy
later, see [monitoring: pitfalls](../roles/monitoring.md#pitfalls)); a `Caddyfile`
change that should trigger a live reload showing up as `changed` regardless (expected,
see [caddy: pitfalls](../roles/caddy.md#pitfalls)). If neither matches, run with `--diff`
and look at what the module actually reports before assuming it's environmental.

## BridgeLink's container is "running" but nothing works

Container status alone means nothing for BridgeLink specifically - the hardened image
can't have a healthcheck (no shell in the image), so Compose considers a container
"done" the moment it starts, including one that's crash-looping. Check the API, not
`docker ps` - see [bridgelink: verification](../roles/bridgelink.md#verification).

## `systemctl reload`/`restart` times out over SSH, looks like a hung service

Almost always a missing `become: true` on that specific task, not a real hang - Ansible
without `become` routes the systemd call through PolicyKit, which waits for an
interactive prompt that never arrives over SSH. Looks exactly like a D-Bus or hardware
problem; isn't. See [docker: pitfalls](../roles/docker.md#pitfalls) for where this was
first found and fixed, and check the task in question for `become: true` before
suspecting anything else.

## I changed a variable and nothing happened

Confirm it landed where you think it did. `group_vars/linumed/vars.yml` and
`group_vars/linumed/vault.yml` are merged automatically by Ansible for the `linumed`
group, but a variable set in the wrong file, the wrong group, or shadowed by a
role default with higher precedence than expected won't error - it silently doesn't
apply. `ansible-inventory -i <your-inventory> --list` shows what a host actually
resolves to; check there before assuming a bug in the role.
