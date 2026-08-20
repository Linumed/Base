#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify that the node-baseline subset really is deployable on
# its own, and idempotently (issue #70).
#
# Why it needs its own check: the README tells operators running Kubernetes that `common`,
# `docker` and `backup` are theirs to use on their nodes. That was a claim derived from
# counting which roles ship a Compose file - true as far as it goes, and exactly the kind
# of reasoning that produced the volume-name error in #68. Only running it proves it.
#
# Deliberately runs FIRST, on the pristine VM, before site.yml:
#
#   * It is the honest scenario. Someone applying the baseline is applying it to a fresh
#     host, not to one that already has the full stack on it.
#   * Running it after site.yml would prove nothing about whether the subset can stand
#     alone, since everything it needs would already be present.
#   * It costs little: the packages and the Docker install it performs are work site.yml
#     would do moments later anyway, so the subsequent full run is correspondingly shorter.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY,
# ANSIBLE_USER, and an inventory written by run_site_idempotency_check's caller.

run_node_baseline_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"
  local inventory="${WORK_DIR}/inventory.yml"

  echo "==> Applying node-baseline.yml to the pristine VM"
  (
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/node-baseline.yml
  ) || { echo "FAIL: node-baseline.yml did not apply cleanly" >&2; return 1; }

  echo "==> Second node-baseline run (must report changed=0)"
  local second
  second="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/node-baseline.yml
  )" || { echo "FAIL: the second node-baseline run failed outright" >&2; return 1; }
  echo "${second}"
  if echo "${second}" | grep -qE 'changed=[1-9]'; then
    echo "FAIL: node-baseline.yml is not idempotent" >&2
    return 1
  fi
  echo "==> PASS: node-baseline.yml is idempotent"

  # The point of the subset is that the hardening and the backup actually work without the
  # service stacks - not merely that the playbook exits 0. Checking effect, not config,
  # is the lesson from #40, where every test stayed green while Prometheus could not reach
  # its target.
  echo "==> Checking the baseline actually took effect"
  local ufw_active sshd_pw docker_ok timer_ok failed=0

  ufw_active="$(ssh "${ssh_opts[@]}" "${remote}" 'sudo ufw status | head -1')"
  sshd_pw="$(ssh "${ssh_opts[@]}" "${remote}" 'sudo sshd -T | grep -i "^passwordauthentication"')"
  docker_ok="$(ssh "${ssh_opts[@]}" "${remote}" 'sudo docker info --format "{{.ServerVersion}}" 2>/dev/null')"
  timer_ok="$(ssh "${ssh_opts[@]}" "${remote}" \
    'systemctl is-enabled linumed-base-backup.timer 2>/dev/null')"

  case "${ufw_active}" in *active*) ;; *) echo "FAIL: ufw is not active (${ufw_active})" >&2; failed=1 ;; esac
  case "${sshd_pw}" in *no) ;; *) echo "FAIL: password auth not disabled (${sshd_pw})" >&2; failed=1 ;; esac
  [ -n "${docker_ok}" ] || { echo "FAIL: docker is not running" >&2; failed=1; }
  [ "${timer_ok}" = "enabled" ] || { echo "FAIL: backup timer is ${timer_ok}, expected enabled" >&2; failed=1; }
  [ "${failed}" -eq 0 ] || return 1

  echo "==> PASS: hardening, Docker and the backup timer are in effect without any service stack"

  # The other half of the claim: none of the service stacks got deployed. If a Compose
  # stack showed up here, the subset would not be a subset.
  local containers
  containers="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sudo docker ps -a --format "{{.Names}}" | wc -l')"
  if [ "${containers}" != "0" ]; then
    echo "FAIL: node-baseline started ${containers} container(s); it should start none" >&2
    ssh "${ssh_opts[@]}" "${remote}" 'sudo docker ps -a --format "{{.Names}}"' >&2 || true
    return 1
  fi
  echo "==> PASS: node-baseline deploys no service stack"
}
