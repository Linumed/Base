# docker

Docker Engine and the compose plugin (`docker compose`), installed from the official
Docker apt repository. Closes issue #17 - every Docker-based role (caddy, and later
mirth-connect, monitoring) needs this and previously had to fail with a clear preflight
message instead of installing it.

## Variables

See `defaults/main.yml`, all prefixed `docker_*`.

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
- Does not configure the Docker registry, buildx builders, or rootless mode - out of
  scope for v0.1.

## Log rotation

`docker_log_max_size` / `docker_log_max_file` cap container log growth via
`/etc/docker/daemon.json` - unbounded json-file logs are a real way to fill a small disk
on a long-running host.
