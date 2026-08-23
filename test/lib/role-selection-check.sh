#!/usr/bin/env bash
# Shared by test/vm-test.sh: prove the two preflights linumed_base_roles depends on
# actually fire (issue #86). A preflight that has never refused anything is
# indistinguishable from one that cannot - the same lesson #62 and #76 already taught
# this repository, applied to the guards this file exists to add.
#
# Split into two functions because they need opposite host states, and getting that
# wrong makes the test prove nothing:
#
#   * The dependency preflight (stage 1) needs a host where caddy/monitoring/bridgelink
#     have NOT run - otherwise the residue preflight (stage 2) fires first on one of
#     those, since it checks every deselected role, not just the one under test. So this
#     runs right after node-baseline, before the full stack exists.
#   * The residue preflight needs the opposite: a role that HAS already run and is then
#     deselected. So this runs after run_site_idempotency_check, against the fully
#     deployed VM.
#
# Both abort in `pre_tasks`, before any role runs, so each costs seconds, not an apply.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY,
# ANSIBLE_USER, and an inventory written by write_test_inventory.

# Call right after run_node_baseline_check, before run_site_idempotency_check. The VM at
# that point has common/docker/backup from node-baseline and nothing else - exactly the
# clean state this probe needs, and reusing it costs nothing extra.
#
# Orthanc used to be the test case here (its metrics-network dependency on monitoring).
# It was removed in #92/ADR 0011 along with the role itself, so this now exercises
# site.yml's own remaining dependency preflight instead: a Compose role selected without
# `docker` (docker is deliberately left out of the selection below, even though
# node-baseline already installed it - the preflight checks linumed_base_roles, not what
# is actually on the host).
run_role_selection_dependency_check() {
  local inventory="${WORK_DIR}/inventory.yml"

  echo "==> Checking the dependency preflight refuses a Compose role without docker"
  local dep_rc=0
  local dep_out
  dep_out="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e '{"linumed_base_roles": ["common", "backup", "caddy"]}' \
      2>&1
  )" || dep_rc=$?
  if [ "${dep_rc}" -eq 0 ]; then
    echo "FAIL: site.yml accepted [common, backup, caddy] - caddy needs docker, which was" >&2
    echo "deliberately left out of the selection" >&2
    return 1
  fi
  if echo "${dep_out}" | grep -q "is not in linumed_base_roles, but"; then
    echo "FAIL: this aborted on the residue preflight, not the dependency one - the host" >&2
    echo "state assumption behind this probe is wrong, it proves nothing" >&2
    echo "${dep_out}" | tail -20 >&2
    return 1
  fi
  if ! echo "${dep_out}" | grep -q "without 'docker'"; then
    echo "FAIL: the run aborted, but not on the docker-dependency preflight - so this proves nothing" >&2
    echo "${dep_out}" | tail -20 >&2
    return 1
  fi
  echo "==> PASS: the dependency preflight refuses a Compose role without docker"
}

# Call after run_site_idempotency_check, against the fully deployed VM - the residue it
# must detect (caddy's deploy directory) is then real, not staged. caddy stands in for
# orthanc, the original test case, removed in #92/ADR 0011.
run_role_selection_residue_check() {
  local inventory="${WORK_DIR}/inventory.yml"

  echo "==> Checking the residue preflight refuses to drop an already-deployed role"
  local residue_rc=0
  local residue_out
  residue_out="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e '{"linumed_base_roles": ["common", "docker", "monitoring", "bridgelink", "backup"]}' \
      2>&1
  )" || residue_rc=$?
  if [ "${residue_rc}" -eq 0 ]; then
    echo "FAIL: site.yml accepted deselecting caddy although it is already deployed on this host" >&2
    return 1
  fi
  if ! echo "${residue_out}" | grep -q "caddy is not in linumed_base_roles"; then
    echo "FAIL: the run aborted, but not on the residue preflight - so this proves nothing" >&2
    echo "${residue_out}" | tail -20 >&2
    return 1
  fi
  if ! echo "${residue_out}" | grep -q "teardown.md"; then
    echo "FAIL: the residue preflight's message does not point at docs/operations/teardown.md" >&2
    return 1
  fi
  echo "==> PASS: the residue preflight refuses and names the teardown page"
}
