#!/usr/bin/env bash
# Shared by test/vm-test.sh and test/vm-test-netinst.sh: given a reachable VM, build an
# inventory and verify site.yml applies cleanly, then reports changed=0 on a second run.
#
# This is the part that's identical between the two test paths - only how the VM gets
# provisioned differs (cloud-init vs. a real netinst/preseed install). Kept in one place
# so the growing per-role test inventory (currently monitoring, bridgelink, backup) only
# has to be maintained once - two copies would drift.
#
# Not meant to be executed directly. Expects these variables to already be set by the
# caller: REPO_ROOT, WORK_DIR, VM_NAME, VM_IP, SSH_KEY, ANSIBLE_USER.

# Optional Docker Hub pull-through cache (issue #43) - half of the full-stack VM runs on
# 2026-08-14 failed pulling images from Docker Hub directly, not on any role. Defaults to
# the libvirt "default" network's own gateway address, which every caller of this script
# already assumes exists (vm-test.sh provisions guests with --network network=default) -
# safe to default even when nothing is listening there: a closed port on that address
# returns an immediate "connection refused" (confirmed: ~10ms), not a hang, and Docker
# falls back to pulling from Docker Hub directly. Override or unset to test without it.
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR-http://192.168.122.1:5000}"

# A green ansible-playbook run only proves the config was applied, not that the result
# does anything - issue #40 found this the hard way: node_exporter was DOWN in Prometheus
# on every fresh install (ufw blocked the scrape) while both vm-test.sh and
# vm-test-netinst.sh stayed green, because neither ever asked Prometheus whether its
# targets were actually reachable. Fetches the raw JSON over SSH and parses it locally on
# the control node - a Python one-liner embedded inside the SSH command string is a
# quoting trap (confirmed while building this check: an f-string with an escaped quote
# inside an already-quoted ssh argument produced "unexpected character after line
# continuation character", not a Python error worth debugging twice).
check_prometheus_targets_healthy() {
  local targets_json
  targets_json="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${SSH_KEY}" "${ANSIBLE_USER}@${VM_IP}" 'curl -s localhost:9090/api/v1/targets')"

  echo "${targets_json}" | python3 -c "
import json, sys

d = json.load(sys.stdin)
targets = d['data']['activeTargets']
down = [t for t in targets if t['health'] != 'up']

if not targets:
    print('FAIL: Prometheus reported zero active targets')
    sys.exit(1)

for t in down:
    job = t['labels'].get('job', '?')
    err = t.get('lastError', '')
    print(f'FAIL: target job={job} health={t[\"health\"]} lastError={err!r}')

if down:
    sys.exit(1)

print(f'PASS: all {len(targets)} Prometheus targets healthy')
"
}

# Split out of run_site_idempotency_check so that a check running *before* it can use the
# same inventory - node-baseline (#70) applies to the pristine VM first, and writing a
# second inventory for it would let the two drift.
write_test_inventory() {
  local inventory="${WORK_DIR}/inventory.yml"
  cat > "${inventory}" <<EOF
all:
  children:
    linumed:
      hosts:
        ${VM_NAME}:
          ansible_host: ${VM_IP}
          ansible_user: ${ANSIBLE_USER}
          ansible_ssh_private_key_file: ${SSH_KEY}
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          # Test-only credentials for a throwaway VM - real deployments set these via
          # Ansible Vault, never in plain text. The monitoring and bridgelink roles have
          # preflight checks that refuse to run without them set at all.
          monitoring_grafana_admin_password: "throwaway-test-password"
          bridgelink_db_password: "throwaway-test-password"
          bridgelink_keystore_storepass: "throwaway-test-storepass"
          bridgelink_keystore_keypass: "throwaway-test-keypass"
          bridgelink_server_id: "$(cat /proc/sys/kernel/random/uuid)"
          # Local-path restic repository inside the VM - no real backend needed to
          # verify the role's own logic (init, backup, forget, check, metrics).
          backup_repository: "/var/backups/restic-test"
          backup_restic_password: "throwaway-test-restic-password"
EOF

  if [ -n "${DOCKER_REGISTRY_MIRROR}" ]; then
    cat >> "${inventory}" <<EOF
          docker_registry_mirrors: ["${DOCKER_REGISTRY_MIRROR}"]
EOF
  fi
}

run_site_idempotency_check() {
  local inventory="${WORK_DIR}/inventory.yml"
  [ -f "${inventory}" ] || write_test_inventory

  (
    cd "${REPO_ROOT}/ansible"

    echo "==> First run"
    ansible-playbook -i "${inventory}" playbooks/site.yml

    echo "==> Second run (must report changed=0)"
    output="$(ansible-playbook -i "${inventory}" playbooks/site.yml)"
    echo "${output}"
    if echo "${output}" | grep -qE 'changed=[1-9]'; then
      echo "FAIL: second run was not idempotent" >&2
      exit 1
    fi
  )

  echo "==> PASS: site.yml is idempotent"

  # 20s, not the bare 15s scrape_interval - the first scrape after a container (re)start
  # is not pinned to that interval's phase, so a check made the instant the second run
  # exits can still catch Prometheus between scrapes.
  echo "==> Waiting for Prometheus's first scrape cycle"
  sleep 20

  echo "==> Checking Prometheus targets are actually healthy, not just configured"
  if ! check_prometheus_targets_healthy; then
    echo "FAIL: at least one Prometheus target is not up - the playbook applied cleanly but the resulting stack does not work (see issue #40)" >&2
    exit 1
  fi
}
