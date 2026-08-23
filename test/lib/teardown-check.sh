#!/usr/bin/env bash
# Shared by test/vm-test.sh: execute the documented teardown and check it leaves the host
# in the state docs/operations/teardown.md claims (issue #68).
#
# Why this exists: that page tells an operator how to remove the kit from a production
# host. A procedure of that kind, written and never run, is the same shape of problem as
# the exporter enable path in #62 - prose that looks verified because it is detailed. The
# VM is destroyed immediately after this anyway, so running the teardown on it costs
# nothing and turns the page from a description into something that has actually happened.
#
# Runs LAST, after every other check, because it removes the installation those checks
# depend on.
#
# What it does NOT do is re-derive the procedure. It runs the steps the page documents and
# asserts the page's own verification commands come back clean. If the two drift, this
# fails, which is the point.
#
# Not meant to be executed directly. Expects: VM_IP, SSH_KEY, ANSIBLE_USER.

run_teardown_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"

  echo "==> Running the documented teardown (docs/operations/teardown.md)"

  ssh "${ssh_opts[@]}" "${remote}" 'set -e
    sudo systemctl disable --now linumed-base-backup.timer linumed-base-restore-test.timer

    # orthanc stays in this loop even though the role was removed in #92/ADR 0011 - this
    # VM went through run_upgrade_from_previous_tag first, deploying v1.0.0 (which still
    # has it), so a leftover orthanc stack is real state here, not a stale assumption.
    # docs/operations/teardown.md keeps this entry for exactly this legacy-host case, and
    # this loop has to match that page verbatim - see this file's own header.
    for stack in orthanc bridgelink monitoring caddy; do
      [ -d "/opt/linumed-base/$stack" ] && \
        sudo docker compose -f "/opt/linumed-base/$stack/docker-compose.yml" down || true
    done

    # The real procedure asks a human to look before removing volumes; a throwaway VM has
    # no data worth that pause. Deliberately the SAME filter the page gives operators, so
    # this also checks the page is right: volumes are named after the Compose project, not
    # after container_name. The first version grepped for linumed-base, matched nothing,
    # and that is how the docs error was caught instead of shipped.
    volumes="$(sudo docker volume ls --format "{{.Name}}" | grep -E "^(caddy|monitoring|bridgelink|orthanc)_" || true)"
    [ -n "$volumes" ] || { echo "no project volumes found - the filter in the docs is wrong" >&2; exit 1; }
    echo "$volumes" | xargs -r sudo docker volume rm >/dev/null

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
  ' || { echo "FAIL: the documented teardown steps did not run cleanly" >&2; return 1; }

  # The page's own warning, exercised rather than trusted: removing the hardening drop-in
  # puts SSH back on the distribution defaults. The test inventory leaves common_ssh_port
  # at 22, so reconnecting has to keep working - and if a future change makes the port
  # configurable in the test, this is where that would surface.
  echo "==> Restarting ssh, then reconnecting - the step the page warns about"
  ssh "${ssh_opts[@]}" "${remote}" 'sudo systemctl restart ssh' || true
  local reconnect=""
  local attempt
  for attempt in $(seq 1 10); do
    if ssh "${ssh_opts[@]}" -o ConnectTimeout=5 "${remote}" true 2>/dev/null; then
      reconnect="ok"
      break
    fi
    sleep 3
  done
  if [ "${reconnect}" != "ok" ]; then
    echo "FAIL: could not reconnect after the documented ssh restart" >&2
    return 1
  fi
  echo "==> PASS: SSH still reachable after the teardown"

  echo "==> Checking the page's own verification commands"
  local units containers dir
  units="$(ssh "${ssh_opts[@]}" "${remote}" \
    "systemctl list-units 'linumed-base-*' --no-legend --all | wc -l")"
  containers="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sudo docker ps -a --filter name=linumed-base --format "{{.Names}}" | wc -l')"
  dir="$(ssh "${ssh_opts[@]}" "${remote}" \
    'test -e /opt/linumed-base && echo present || echo gone')"

  local failed=0
  [ "${units}" = "0" ] || { echo "FAIL: ${units} linumed-base units remain" >&2; failed=1; }
  [ "${containers}" = "0" ] || { echo "FAIL: ${containers} linumed-base containers remain" >&2; failed=1; }
  [ "${dir}" = "gone" ] || { echo "FAIL: /opt/linumed-base still exists" >&2; failed=1; }
  [ "${failed}" -eq 0 ] || return 1

  echo "==> PASS: teardown leaves the host as docs/operations/teardown.md describes"
}
