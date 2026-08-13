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

run_site_idempotency_check() {
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
}
