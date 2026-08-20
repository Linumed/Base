# Removing Linumed Base from a host

**There is no uninstall playbook, and this page is the reason that is a defensible answer
rather than a gap.** What the kit puts on a host is listed here completely, so removing it
is a known quantity - and so that anyone evaluating the kit can see what they would be
taking on before they run it.

Nobody should have to guess how to get software off a machine. That question decides
whether a service provider tries the kit at all.

## Why no uninstall playbook

An uninstall role would have to decide what a host looked like *before* - and it cannot
know. Three of the things this kit configures are not its own:

- **`ufw`, `fail2ban` and `unattended-upgrades` may have been installed already.** Removing
  them because Linumed Base configured them would leave a host less protected than it was
  found. The `common` role deliberately never uninstalls: `common_fail2ban_enabled: false`
  stops and disables the service, it does not purge the package.
- **SSH hardening is not additive-only in effect.** Undoing it means deciding what the
  previous policy was, which is not recorded anywhere.
- **Docker may be carrying the operator's own containers.** Removing Docker to undo the
  `docker` role could destroy workloads this kit never knew about.

An automated teardown would therefore be guessing on a host that is, by definition, in
production. A documented one is slower and safe.

## What gets left behind

Measured against the roles, not recalled (2026-08-20). Everything this kit creates outside
of package installs is prefixed, which is what makes a manual removal tractable.

### Files and directories

| Path | Role |
|---|---|
| `/opt/linumed-base/` | all Compose-based roles - configs, secrets, Compose files |
| `/etc/ssh/sshd_config.d/10-linumed-hardening.conf` | common |
| `/etc/ssh/sshd_config.d/90-linumed-tunnel-users.conf` | common (tunnel users) |
| `/etc/systemd/system/ssh.socket.d/listen.conf` | common (only if the SSH port was changed) |
| `/etc/fail2ban/jail.d/10-linumed-sshd.conf` | common |
| `/etc/apt/apt.conf.d/51-linumed-unattended-upgrades` | common |
| `/etc/apt/apt.conf.d/20auto-upgrades` | common |
| `/etc/systemd/timesyncd.conf.d/10-linumed.conf` | common |
| `/etc/apt/keyrings/docker.asc` | docker |
| `/etc/apt/sources.list.d/docker.list` | docker |
| `/etc/docker/daemon.json` | docker (log rotation) |
| `/etc/default/prometheus-node-exporter` | monitoring |
| `/var/lib/prometheus/node-exporter/` | monitoring (textfile metrics) |
| `/usr/local/bin/linumed-base-backup.sh` | backup |
| `/usr/local/bin/linumed-base-restore-test.sh` | backup |
| `/etc/systemd/system/linumed-base-backup.{service,timer}` | backup |
| `/etc/systemd/system/linumed-base-restore-test.{service,timer}` | backup |

### Packages installed

`docker-ce` and its plugins, `fail2ban`, `restic`, `ufw`, `unattended-upgrades`,
`prometheus-node-exporter`. Any of these may have been present beforehand.

### State that is not a file

- **Docker volumes and images.** The volumes hold Prometheus, Loki and Grafana data,
  BridgeLink's appdata and its PostgreSQL database. **This is where the data is** - do not
  remove them before the backup has been verified.

  **They are not named `linumed-base-*`.** Containers are, because the Compose files set
  `container_name` explicitly; volumes are not, so Compose derives their names from the
  project, which is the directory under `/opt/linumed-base`:

  | Role | Volumes |
  |---|---|
  | caddy | `caddy_caddy_data`, `caddy_caddy_config` |
  | monitoring | `monitoring_prometheus_data`, `monitoring_loki_data`, `monitoring_grafana_data`, `monitoring_alertmanager_data` |
  | bridgelink | `bridgelink_bridgelink_appdata`, `bridgelink_bridgelink_extensions`, `bridgelink_bridgelink_db_data` |

  This page originally told you to look for them with `grep linumed-base`, which finds
  nothing - so it read as "there is no data here" while every volume was still in place.
  The VM test caught it on the first run (issue #68).
- **ufw rules** added by the roles: the SSH port, Caddy's 80/443, and the Node Exporter
  allow/deny pair.
- **The restic repository**, wherever `backup_repository` points. Outside the host if it is
  remote, and deliberately not touched by anything here.
- **Shell-less tunnel users** created via `common_ssh_tunnel_users`.

## Removing it, in order

Order matters: stopping the backup first prevents a scheduled run from firing mid-teardown.

```bash
# 1. Stop the timers before anything else
sudo systemctl disable --now linumed-base-backup.timer linumed-base-restore-test.timer

# 2. Stop and remove the service stacks
for stack in bridgelink monitoring caddy; do
  [ -d "/opt/linumed-base/$stack" ] && \
    sudo docker compose -f "/opt/linumed-base/$stack/docker-compose.yml" down
done

# 3. Data. Irreversible - verify the backup first, see backup-restore.md
# Volumes are named after the Compose project, NOT linumed-base - see the table above.
sudo docker volume ls --format '{{.Name}}' \
  | grep -E '^(caddy|monitoring|bridgelink)_'   # look before removing
# sudo docker volume rm <each one>

# 4. Files, including the secrets under /opt/linumed-base/*/secrets/
sudo rm -rf /opt/linumed-base
sudo rm -f /etc/ssh/sshd_config.d/10-linumed-hardening.conf \
           /etc/ssh/sshd_config.d/90-linumed-tunnel-users.conf \
           /etc/fail2ban/jail.d/10-linumed-sshd.conf \
           /etc/apt/apt.conf.d/51-linumed-unattended-upgrades \
           /etc/systemd/timesyncd.conf.d/10-linumed.conf \
           /etc/default/prometheus-node-exporter \
           /usr/local/bin/linumed-base-backup.sh \
           /usr/local/bin/linumed-base-restore-test.sh \
           /etc/systemd/system/linumed-base-*.service \
           /etc/systemd/system/linumed-base-*.timer
sudo systemctl daemon-reload
```

**Restart `ssh` last, and keep a second session open while you do.** Removing the hardening
drop-in changes the port and the authentication policy back to the distribution defaults; if
the port changes and something goes wrong, an open session is the only way back in.

```bash
sudo systemctl restart ssh   # keep another session open
```

### What the commands above deliberately leave

Not oversights - each one would make the host worse or is not this kit's to decide:

- **`/etc/apt/apt.conf.d/20auto-upgrades`** keeps unattended security updates running.
  Removing it silently stops them, which is the last thing an abandoned host needs.
- **`/etc/apt/sources.list.d/docker.list` and `/etc/apt/keyrings/docker.asc`** stay because
  Docker itself stays. Remove them only if Docker is going too.
- **`/etc/docker/daemon.json`** holds log rotation. Removing it lets container logs grow
  without limit again.
- **`/etc/systemd/system/ssh.socket.d/listen.conf`** exists only if the SSH port was
  changed. Remove it *only together with* the hardening drop-in and in the same
  keep-a-session-open manner, or the port the sockets listen on and the port the config
  expects can end up disagreeing.
- **Packages and ufw rules**, for the reasoning at the top. Whether `ufw` should keep denying
  by default after Linumed Base is gone is a decision about that host, not about this kit.

## Verifying it is gone

```bash
systemctl list-units 'linumed-base-*'          # expect nothing
sudo docker ps -a --filter name=linumed-base   # expect nothing
ls /opt/linumed-base 2>/dev/null               # expect "No such file"
sudo sshd -T | grep -E '^(port|passwordauthentication)'
```

The last one is the check worth doing: it shows the SSH policy actually in effect, which is
what a stale drop-in would otherwise hide.

## This procedure is executed, not just written

`test/vm-test.sh` runs the steps on this page against the throwaway VM as its final act,
after every other check, and asserts the verification commands above come back clean -
including reconnecting over SSH after the restart the warning is about. The VM is destroyed
immediately afterwards, so the run costs almost nothing.

The reason for bothering: a removal procedure that has never been executed is prose that
looks verified because it is detailed. If this page and the roles drift apart - a new file
in a new role, say, that nothing here removes - the test fails rather than the operator
finding out on a production host.
