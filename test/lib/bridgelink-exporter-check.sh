#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify the BridgeLink Prometheus exporter (issue #60) works
# when it is actually switched on (issue #62).
#
# Why this is separate from run_site_idempotency_check: that function runs site.yml with
# the role defaults, and the exporter defaults to off. What it proves is that the change
# is a no-op while disabled - the property that matters most, but not the only one. The
# enabled path (deploying secrets/exporter_password as UID 65532, copying the script, the
# second preflight, the extra Compose service, the scrape job) had no coverage at all:
# #60 was verified by hand, container-side, against a throwaway engine. That is not a
# role run.
#
# Why it is not in site-idempotency.sh: that file is shared with vm-test-netinst.sh,
# whose job is proving the bootstrap baseline works on a minimal netinst install. A third
# site.yml pass belongs nowhere near that question, and the netinst run is already the
# slower of the two. This is called only from vm-test.sh, the same arrangement as
# run_docker_reference_smoke_check.
#
# Cost: one more site.yml apply on an already-provisioned VM. Most of it is a no-op
# because only the bridgelink and monitoring roles have anything to change, but it is not
# free - the run was ~9 minutes at runner capacity 1 before this (issue #45). Accepted
# because the alternative is shipping an enable path nothing has ever executed.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY,
# ANSIBLE_USER, VM_NAME, and an inventory already written by run_site_idempotency_check.

# Must satisfy BridgeLink's own password policy, which is enforced server-side and is the
# trap this whole helper nearly walked into: PUT /api/users/{id}/password answers a
# policy violation with HTTP **200** and a body of <string> elements, not with a 4xx. A
# `curl -f` sees success, the password silently stays unset, and the only symptom is the
# exporter failing to authenticate later with a confusing 401. Measured against
# 26.6.0-dhi-slim: uppercase, digit and special character are each required.
BRIDGELINK_TEST_EXPORTER_USER="metrics"
BRIDGELINK_TEST_EXPORTER_PASSWORD='Throwaway-Test-Pw1!'

# Creates the BridgeLink user the exporter authenticates as. The bridgelink role
# deliberately does not do this - BridgeLink's user database belongs to the operator and
# only exists after the first Administrator login (issue #60), which is exactly why the
# exporter is opt-in. A throwaway VM has no operator, so the test plays that part.
_create_bridgelink_exporter_user() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"

  # X-Requested-With is not optional: Mirth rejects every API request without it with
  # HTTP 400 ("All requests must have 'X-Requested-With' header"). It is a CSRF guard and
  # the value is never checked. -k because the engine serves its own generated keystore.
  local api='https://127.0.0.1:8443/api'
  local curl_common="curl -sk -H 'X-Requested-With: vm-test' -u admin:admin"

  echo "==> Creating the BridgeLink user the exporter logs in as"
  ssh "${ssh_opts[@]}" "${remote}" "${curl_common} -H 'Content-Type: application/xml' \
    -X POST --data-binary '<user><username>${BRIDGELINK_TEST_EXPORTER_USER}</username><description>Prometheus exporter (vm-test)</description></user>' \
    ${api}/users" >/dev/null

  # Look the ID up instead of assuming it. On a fresh engine the new user is 2 (admin is
  # 1) and hardcoding that would work today, but the password endpoint is addressed by ID
  # and silently belongs to whoever actually holds it - a wrong guess would reset admin's
  # password rather than fail.
  local user_id
  user_id="$(ssh "${ssh_opts[@]}" "${remote}" "${curl_common} ${api}/users" \
    | tr -d ' \n' \
    | grep -o "<user><id>[0-9]*</id><username>${BRIDGELINK_TEST_EXPORTER_USER}</username>" \
    | grep -o '<id>[0-9]*</id>' | grep -o '[0-9]*' || true)"
  if [ -z "${user_id}" ]; then
    echo "FAIL: BridgeLink user '${BRIDGELINK_TEST_EXPORTER_USER}' was not created" >&2
    return 1
  fi

  local pw_result
  pw_result="$(ssh "${ssh_opts[@]}" "${remote}" "${curl_common} -H 'Content-Type: text/plain' \
    -X PUT --data '${BRIDGELINK_TEST_EXPORTER_PASSWORD}' \
    ${api}/users/${user_id}/password")"

  # Success is an empty body (HTTP 204). Anything with a <string> in it is the policy
  # rejection described above, arriving as a 200.
  if echo "${pw_result}" | grep -q '<string>'; then
    echo "FAIL: BridgeLink rejected the test password:" >&2
    echo "${pw_result}" >&2
    return 1
  fi

  # Prove the credential actually works before handing it to Ansible - otherwise a
  # failure here surfaces much later as an unexplained exporter 401.
  local login_code
  login_code="$(ssh "${ssh_opts[@]}" "${remote}" \
    "curl -sk -o /dev/null -w '%{http_code}' -H 'X-Requested-With: vm-test' \
     -u '${BRIDGELINK_TEST_EXPORTER_USER}:${BRIDGELINK_TEST_EXPORTER_PASSWORD}' \
     ${api}/channels/statuses")"
  if [ "${login_code}" != "200" ]; then
    echo "FAIL: the new BridgeLink user cannot read /api/channels/statuses (HTTP ${login_code})" >&2
    return 1
  fi
  echo "==> PASS: exporter user can authenticate against the BridgeLink API"
}

run_bridgelink_exporter_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"
  local inventory="${WORK_DIR}/inventory.yml"

  if ! _create_bridgelink_exporter_user; then
    return 1
  fi

  echo "==> Re-applying site.yml with the exporter enabled"
  (
    cd "${REPO_ROOT}/ansible"
    # Extra-vars rather than editing the inventory: the inventory is what the idempotency
    # check above ran against, and rewriting it here would make a re-read of that earlier
    # PASS misleading about what it covered.
    # JSON extra-vars, not key=value: `-e foo=true` hands Ansible the *string* "true", and
    # a string is not a valid conditional result - the first run of this check failed with
    # "Conditional result (True) was derived from value of type 'str'". JSON keeps the
    # booleans booleans, which is also what a real inventory would supply. (The roles now
    # additionally filter these through | bool, so a string no longer misbehaves - but
    # this side should still hand over the right type rather than lean on that.)
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e '{"bridgelink_exporter_enabled": true, "monitoring_scrape_bridgelink": true}' \
      -e "bridgelink_exporter_user=${BRIDGELINK_TEST_EXPORTER_USER}" \
      -e "bridgelink_exporter_password=${BRIDGELINK_TEST_EXPORTER_PASSWORD}"
  ) || { echo "FAIL: site.yml failed with the exporter enabled" >&2; return 1; }

  # The enabled path has to be idempotent too, and it is a different code path from the
  # one the earlier double-run covered: an extra container, an extra secret, an extra
  # network, a changed Prometheus config. Compose roles are exactly where a spurious
  # "changed" hides (a template that re-renders differently, a handler that always fires).
  echo "==> Re-applying once more with the exporter enabled (must report changed=0)"
  local second
  second="$(
    cd "${REPO_ROOT}/ansible"
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e '{"bridgelink_exporter_enabled": true, "monitoring_scrape_bridgelink": true}' \
      -e "bridgelink_exporter_user=${BRIDGELINK_TEST_EXPORTER_USER}" \
      -e "bridgelink_exporter_password=${BRIDGELINK_TEST_EXPORTER_PASSWORD}"
  )" || { echo "FAIL: the second exporter-enabled run failed outright" >&2; return 1; }
  echo "${second}"
  if echo "${second}" | grep -qE 'changed=[1-9]'; then
    echo "FAIL: the exporter-enabled path is not idempotent" >&2
    return 1
  fi
  echo "==> PASS: the exporter-enabled path is idempotent"

  # The ownership the role has to get right, and the one thing container-side testing for
  # #60 could not check: a file-based Docker secret keeps the host's ownership when
  # Compose mounts it, and the exporter runs unprivileged. Root-owned here means a
  # restart loop (issue #61 is the same failure for mirth.properties).
  echo "==> Checking exporter secret ownership and mode"
  local stat_out
  stat_out="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sudo stat -c "%u:%g %a" /opt/linumed-base/bridgelink/secrets/exporter_password')"
  if [ "${stat_out}" != "65532:65532 400" ]; then
    echo "FAIL: exporter_password is '${stat_out}', expected '65532:65532 400' - the container cannot read it (see issue #61)" >&2
    return 1
  fi
  echo "==> PASS: exporter secret is 65532:65532 400"

  # Polled, not sampled once: the service declares start_period 10s and interval 30s, so
  # a single inspect immediately after the playbook exits legitimately reads "starting"
  # and would fail the test for no reason. 12 x 10s covers two full intervals plus slack
  # on a 1-vCPU guest.
  echo "==> Waiting for the exporter container to report healthy"
  local health=""
  local attempt
  for attempt in $(seq 1 12); do
    health="$(ssh "${ssh_opts[@]}" "${remote}" \
      'sudo docker inspect linumed-base-bridgelink-exporter --format "{{.State.Health.Status}}"' 2>/dev/null || true)"
    [ "${health}" = "healthy" ] && break
    sleep 10
  done
  if [ "${health}" != "healthy" ]; then
    echo "FAIL: exporter container health is '${health}', expected 'healthy'" >&2
    ssh "${ssh_opts[@]}" "${remote}" 'sudo docker logs --tail 30 linumed-base-bridgelink-exporter' >&2 || true
    return 1
  fi
  echo "==> PASS: exporter container is healthy"

  # bridgelink_up distinguishes "the exporter is alive but the engine is not answering"
  # from "the exporter is gone" - a scrape that merely succeeds proves only the latter.
  echo "==> Checking the exporter reports the engine as up"
  local up
  up="$(ssh "${ssh_opts[@]}" "${remote}" \
    'curl -s localhost:9151/metrics | grep "^bridgelink_up " | cut -d" " -f2' || true)"
  if [ "${up}" != "1" ]; then
    echo "FAIL: bridgelink_up is '${up}', expected 1 - the exporter cannot reach the engine" >&2
    return 1
  fi
  echo "==> PASS: bridgelink_up is 1"

  # Same reasoning and the same 20s as in site-idempotency.sh: Prometheus has just been
  # reconfigured, and the first scrape of the new job is not phase-aligned with the
  # scrape interval.
  echo "==> Waiting for Prometheus's first scrape of the new job"
  sleep 20

  # The point of the whole exercise: the existing all-targets-healthy check now has a
  # fourth job to be healthy about. No new assertion needed - issue #40's lesson already
  # lives in check_prometheus_targets_healthy.
  echo "==> Checking Prometheus targets again, now including the bridgelink job"
  local targets_json
  targets_json="$(ssh "${ssh_opts[@]}" "${remote}" 'curl -s localhost:9090/api/v1/targets')"
  if ! echo "${targets_json}" | grep -q '"job":"bridgelink"'; then
    # Dump the evidence rather than just the verdict. A bare "the job is missing" leaves
    # the reader unable to tell the three causes apart - the template rendered without it,
    # it rendered but Prometheus never reloaded, or the job is there and this check is
    # what is broken - and the VM is destroyed on exit, so there is no going back to look.
    echo "FAIL: Prometheus has no bridgelink job - monitoring_scrape_bridgelink did not take effect" >&2
    echo "---- deployed prometheus.yml (tail) ----" >&2
    ssh "${ssh_opts[@]}" "${remote}" \
      'sudo tail -15 /opt/linumed-base/monitoring/prometheus/prometheus.yml' >&2 || true
    echo "---- jobs Prometheus actually has ----" >&2
    echo "${targets_json}" | grep -o '"job":"[^"]*"' | sort -u >&2 || true
    echo "---- config Prometheus actually loaded (scrape job names) ----" >&2
    ssh "${ssh_opts[@]}" "${remote}" \
      'curl -s localhost:9090/api/v1/status/config' | grep -o 'job_name: [a-z]*' | sort -u >&2 || true
    echo "---- reload endpoint response ----" >&2
    ssh "${ssh_opts[@]}" "${remote}" \
      'curl -s -o /dev/null -w "%{http_code}" -X POST localhost:9090/-/reload' >&2 || true
    echo >&2
    return 1
  fi
  if ! check_prometheus_targets_healthy; then
    echo "FAIL: a Prometheus target is down with the exporter enabled (see issue #40)" >&2
    return 1
  fi

  echo "==> PASS: BridgeLink exporter works end to end through Ansible"
}
