#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify the Orthanc Prometheus scrape works when it is actually
# switched on, and that the credential preflight from issue #76 refuses a mismatch.
#
# Why this exists at all: `monitoring_scrape_orthanc` defaults to false, so every run before
# this one proved only that the feature is a no-op while switched off. The enable path - the
# scrape job in prometheus.yml, its basic_auth, the three Orthanc alert rules - had no
# coverage whatsoever. That is the rule from issue #62, which this repository wrote down and
# then walked past again one role later: anything behind a default-off flag ships untested
# until a test deliberately turns it on.
#
# What is different from the BridgeLink twin: nothing has to create an account first.
# Orthanc's user store is `orthanc_users`, the role provisions it, and the throwaway
# inventory already contains a `metrics` account. That also makes this the cheaper of the
# two checks despite testing one thing more.
#
# The one thing more is the point of issue #76. Orthanc serves its own metrics endpoint
# rather than getting an exporter (ADR 0009) and that endpoint sits behind Orthanc's REST
# authentication, so the same credential has to exist in two roles: once in `orthanc_users`,
# once in `monitoring_orthanc_user`/`_password`. Until #76 the two were held together by a
# comment in the example vault. A drift produced a 401, which in Prometheus reads as "target
# down" - indistinguishable from an Orthanc that is simply not deployed.
#
# Cost: two site.yml applies on an already-provisioned VM, mostly no-ops, plus one
# deliberately failing single-role run that aborts in its first task. Accepted for the same
# reason as bridgelink-exporter-check.sh - the alternative is shipping an enable path and a
# gate that nothing has ever executed.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY,
# ANSIBLE_USER, and an inventory already written by run_site_idempotency_check.

# Must match the `metrics` account write_test_inventory puts in orthanc_users. Kept as a
# variable rather than inlined precisely because this file's whole subject is two copies of
# one credential drifting apart.
ORTHANC_TEST_METRICS_USER="metrics"
ORTHANC_TEST_METRICS_PASSWORD="throwaway-test-metrics-password"

run_orthanc_scrape_check() {
  local inventory="${WORK_DIR}/inventory.yml"
  local remote="${ANSIBLE_USER}@${VM_IP}"
  local ssh_opts=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  local scrape_on='{"monitoring_scrape_orthanc": true}'

  echo "==> Re-applying site.yml with the Orthanc scrape enabled"
  (
    cd "${REPO_ROOT}/ansible"
    # Extra-vars rather than an inventory edit, and JSON rather than key=value, for the two
    # reasons spelled out in bridgelink-exporter-check.sh: the inventory is what the earlier
    # idempotency PASS covered, and `-e foo=true` would hand Ansible the string "true".
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e "${scrape_on}" \
      -e "monitoring_orthanc_user=${ORTHANC_TEST_METRICS_USER}" \
      -e "monitoring_orthanc_password=${ORTHANC_TEST_METRICS_PASSWORD}"
  ) || { echo "FAIL: site.yml failed with the Orthanc scrape enabled" >&2; return 1; }

  echo "==> Re-applying once more with the scrape enabled (must report changed=0)"
  local second
  second="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e "${scrape_on}" \
      -e "monitoring_orthanc_user=${ORTHANC_TEST_METRICS_USER}" \
      -e "monitoring_orthanc_password=${ORTHANC_TEST_METRICS_PASSWORD}"
  )" || { echo "FAIL: the second scrape-enabled run failed outright" >&2; return 1; }
  echo "${second}"
  if echo "${second}" | grep -qE 'changed=[1-9]'; then
    echo "FAIL: the scrape-enabled path is not idempotent" >&2
    return 1
  fi
  echo "==> PASS: the scrape-enabled path is idempotent"

  # Same 20s and same reasoning as the BridgeLink twin: Prometheus has just been
  # reconfigured and the first scrape of a new job is not phase-aligned with the interval.
  echo "==> Waiting for Prometheus's first scrape of the orthanc job"
  sleep 20

  echo "==> Checking Prometheus has the orthanc job and every target is healthy"
  local targets_json
  targets_json="$(ssh "${ssh_opts[@]}" "${remote}" 'curl -s localhost:9090/api/v1/targets')"
  if ! echo "${targets_json}" | grep -q '"job":"orthanc"'; then
    # Same evidence dump as the BridgeLink check, for the same reason: the VM is destroyed
    # on exit, so "the job is missing" without the surrounding state cannot be told apart
    # from "the template never rendered it" or "Prometheus never reloaded".
    echo "FAIL: Prometheus has no orthanc job - monitoring_scrape_orthanc did not take effect" >&2
    echo "---- deployed prometheus.yml (tail) ----" >&2
    ssh "${ssh_opts[@]}" "${remote}" \
      'sudo tail -20 /opt/linumed-base/monitoring/prometheus/prometheus.yml' >&2 || true
    echo "---- jobs Prometheus actually has ----" >&2
    echo "${targets_json}" | grep -o '"job":"[^"]*"' | sort -u >&2 || true
    return 1
  fi
  if ! check_prometheus_targets_healthy; then
    # A 401 lands here, not in the job-missing branch above - which is exactly why #76
    # matters: the symptom of wrong credentials is a down target, not an auth error.
    echo "FAIL: a Prometheus target is down with the Orthanc scrape enabled" >&2
    echo "---- orthanc target detail ----" >&2
    echo "${targets_json}" | tr ',' '\n' | grep -A3 -B3 orthanc >&2 || true
    return 1
  fi
  echo "==> PASS: Prometheus scrapes Orthanc and all targets are healthy"

  # The gate from issue #76, proven by making it fire. A preflight that has never refused
  # anything is indistinguishable from one that cannot - #62's lesson applied to the check
  # this very file exists to add.
  #
  # A single-role playbook rather than site.yml: the preflight is the monitoring role's
  # first task, so this aborts in seconds instead of walking common/docker/caddy first, and
  # nothing is deployed because the abort happens before any change.
  echo "==> Checking the credential preflight refuses a password that matches no account"
  cat > "${WORK_DIR}/monitoring-only.yml" <<'EOF'
- name: Preflight probe - monitoring role only, expected to abort
  hosts: linumed
  become: true
  roles:
    - monitoring
EOF
  local probe_rc=0
  local probe_out
  probe_out="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" "${WORK_DIR}/monitoring-only.yml" \
      -e "${scrape_on}" \
      -e "monitoring_orthanc_user=${ORTHANC_TEST_METRICS_USER}" \
      -e "monitoring_orthanc_password=deliberately-wrong" 2>&1
  )" || probe_rc=$?
  if [ "${probe_rc}" -eq 0 ]; then
    echo "FAIL: the preflight accepted a password that matches no orthanc_users account (issue #76)" >&2
    return 1
  fi
  if ! echo "${probe_out}" | grep -q "do not match an account in orthanc_users"; then
    echo "FAIL: the run aborted, but not on the credential preflight - so this proves nothing" >&2
    echo "${probe_out}" | tail -20 >&2
    return 1
  fi
  # The failure message names accounts and must never name the secret that was wrong.
  if echo "${probe_out}" | grep -q "deliberately-wrong"; then
    echo "FAIL: the preflight output contains the supplied password - it must name accounts, not secrets" >&2
    return 1
  fi
  echo "==> PASS: the credential preflight refuses a mismatch and leaks no password"

  echo "==> PASS: the Orthanc scrape works end to end and its preflight bites"
}
