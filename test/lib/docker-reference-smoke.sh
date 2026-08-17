#!/usr/bin/env bash
# Shared by test/vm-test.sh: smoke-test the hand-maintained Compose references under
# docker/ (issue #46), which nothing else in this repo touches.
#
# Why this exists at all: ADR 0005 decided docker/<role>/ is a manual-testing reference,
# not a contractual mirror of the Ansible template, and deliberately rejected building a
# full drift comparison. That trade-off is still right - but it left docker/ with zero
# coverage of any kind, and issue #48 is what that cost: the #44 fix moved the Caddyfile
# bind mount to a directory in both places and left docker/caddy/Caddyfile.example behind
# in the old location, so following that directory's own instructions broke at the `cp`
# step and left Caddy crash-looping against an empty bind-mounted directory (measured).
# ansible-lint doesn't read it, the site.yml VM test doesn't deploy it, and it stayed
# broken until someone re-read the repo by hand.
#
# So this is deliberately NOT the rejected drift check. It only answers the one question
# the reference exists to answer: if I follow this directory as documented, do I get a
# working service? That is cheap, and it is exactly what would have caught #48.
#
# Runs inside the test VM, not on the CI runner: the VM already has Docker (installed by
# the docker role during site.yml) and is thrown away afterwards, so no Docker socket has
# to be exposed to the job container. That keeps the runner's valid_volumes allowlist as
# narrow as it is (ADR 0004) instead of widening it for a test.
#
# docker/bridgelink/ is deliberately not covered: a JVM plus PostgreSQL is minutes of
# runtime and several hundred MB for a check whose whole point is being cheap. If it ever
# breaks the same way, that's the argument for adding it - not before.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY.

run_docker_reference_smoke_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="vmtest@${VM_IP}"

  echo "==> Smoke-testing docker/caddy reference (issue #46)"

  ssh "${ssh_opts[@]}" "${remote}" 'rm -rf ~/docker-ref && mkdir -p ~/docker-ref'
  scp -q "${ssh_opts[@]}" -r "${REPO_ROOT}/docker/caddy" "${remote}:~/docker-ref/"

  # High, loopback-bound ports: the caddy role deployed by site.yml already owns 80/443
  # on this VM, and binding a second stack to 0.0.0.0 would contradict this repo's own
  # firewall doctrine even in a throwaway guest. Compose accepts "IP:PORT" on the left of
  # the mapping, so the existing ${CADDY_HTTP_PORT} substitution carries the address too.
  ssh "${ssh_opts[@]}" "${remote}" 'cd ~/docker-ref/caddy \
    && cp conf/Caddyfile.example conf/Caddyfile \
    && printf "CADDY_HTTP_PORT=127.0.0.1:18080\nCADDY_HTTPS_PORT=127.0.0.1:18443\n" > .env \
    && sudo docker compose -p dockerrefsmoke up -d'

  local config
  # The real assertion: the site block from Caddyfile.example has to be in the loaded
  # config. Asserting on the loaded config rather than on container state is deliberate,
  # even though #48 itself did crash the container (measured: Restarting, since Compose
  # created the missing bind target as an empty directory and Caddy exits without a
  # Caddyfile). A Caddy running against a *stale* config file is the issue #44 failure
  # mode, and that one keeps the container up and the healthcheck green - the healthcheck
  # hits the admin API, which answers regardless of what was loaded. Checking the config
  # covers both; checking container state covers only one.
  config="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sleep 8; sudo docker compose -p dockerrefsmoke -f ~/docker-ref/caddy/docker-compose.yml \
       exec -T caddy wget -qO- http://127.0.0.1:2019/config/' 2>/dev/null || true)"

  ssh "${ssh_opts[@]}" "${remote}" \
    'cd ~/docker-ref/caddy && sudo docker compose -p dockerrefsmoke down -v >/dev/null 2>&1; rm -rf ~/docker-ref' || true

  if ! echo "${config}" | grep -q 'example.linumed.local'; then
    echo "FAIL: docker/caddy came up but served no configuration from conf/Caddyfile." >&2
    echo "      Loaded config was: ${config:-<empty>}" >&2
    echo "      This is the issue #48 failure mode - check that Caddyfile.example still" >&2
    echo "      sits in the directory the compose file bind-mounts (conf/)." >&2
    return 1
  fi

  echo "==> PASS: docker/caddy reference serves its own example configuration"
}
