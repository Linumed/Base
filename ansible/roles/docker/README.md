# docker

Docker Engine and the compose plugin (`docker compose`), installed from the official
Docker apt repository. Closes issue #17 - every Docker-based role (caddy, and later
bridgelink, monitoring) needs this and previously had to fail with a clear preflight
message instead of installing it.

## Variables

See `defaults/main.yml`, all prefixed `docker_*`.

## `python3-requests`

Installed alongside the apt-repo prerequisites (`ca-certificates`, `curl`, `gnupg`), not
because Docker needs it, but because `community.docker`'s API-based modules
(`docker_image`, `docker_container`, `docker_container_exec` - used by caddy, monitoring,
bridgelink) import `requests` on the *target* host. It was missing here until issue #24:
the genericcloud image `test/vm-test.sh` uses has it anyway, as a transitive dependency
of cloud-init, which hid the gap from CI. `test/vm-test-netinst.sh` (issue #14) runs
against a real minimal install without that crutch and would have caught it.

## Why the official Docker repo, not Debian's own `docker.io` package

Debian's `docker.io` package trails upstream Docker releases and, more importantly,
ships an older `docker-compose` (v1, Python) or none at all on some releases - this repo
standardizes on Compose v2 (`docker compose`, with a space), which only comes from the
`docker-compose-plugin` package in Docker's own repo.

## Trixie fallback

Docker's apt repo can lag a new Debian stable release by weeks or months. This role
probes `https://download.docker.com/linux/debian/dists/trixie/Release` and falls back to
the `bookworm` line (`docker_apt_release_fallback`) if Trixie isn't published yet -
Docker's Debian packages have historically been release-agnostic enough for this to work
in practice. Revisit `docker_apt_release` once a native Trixie repo exists.

## What this role does not do

- Does not open any ufw ports - Docker manages its own iptables/nftables rules for
  published container ports, independently of ufw. See the `common` role's ufw
  documentation for the "Docker bypasses ufw" caveat: anything published via `ports:` in
  a compose file is reachable regardless of ufw state unless bound to `127.0.0.1`.
- Does not run or provision a private registry, buildx builders, or rootless mode - out
  of scope for v0.1. It can *point* the daemon at an existing pull-through mirror
  (`docker_registry_mirrors`, see below), but doesn't stand one up.

## Log rotation

`docker_log_max_size` / `docker_log_max_file` cap container log growth via
`/etc/docker/daemon.json` - unbounded json-file logs are a real way to fill a small disk
on a long-running host.

## Registry mirrors

`docker_registry_mirrors` (default `[]`, no behavior change) adds a `registry-mirrors`
entry to `/etc/docker/daemon.json` when set - a list of pull-through cache URLs Docker
tries before Docker Hub. `/etc/docker/daemon.json` is built via Ansible's `combine` +
`to_nice_json` rather than a hand-written template, so the key is fully absent (not
present-but-empty) when unset - an empty `"registry-mirrors": []` in the config is valid
JSON but changes Docker's resolution behavior in a way `[]`-by-omission doesn't.

This exists for `test/vm-test.sh` (issue #43): every fresh test VM otherwise pulls the
full image set straight from Docker Hub, and that pull was measured to be the least
reliable part of a full-stack VM run, not any role. **Not something a real installation
needs to set** - it's wired up by the test tooling, pointed at a `registry:2` cache
running on the dev server itself (`docker_registry_mirrors:
["http://192.168.122.1:5000"]`, the libvirt default-network gateway address, reachable
from every test VM). A Forgejo package registry cannot serve this role: it's a
namespaced push/pull registry, not an implementation of Docker's registry-mirror
protocol - only a plain `registry:2` configured with `proxy.remoteurl` (or an equivalent)
does that.
