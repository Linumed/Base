#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify the Orthanc role produced a working DICOM archive
# (issue #69), not merely a running container.
#
# The role checks two of these itself and fails the play if they do not hold, so this is
# not duplication for its own sake - it is the outside view. A role can pass its own
# assertions and still leave a host that does not do what the documentation claims, which is
# the shape of #40 and #64.
#
# What is checked here and why each one:
#
#   * runs unprivileged - the entire reason this image was chosen over orthancteam's
#     (ADR 0009). If a future image bump silently reintroduces a root container, the ADR is
#     quietly untrue and nothing else would notice.
#   * PostgreSQL is the index backend - Orthanc starts happily on its built-in SQLite when
#     the plugin fails to load, and everything looks normal until a restore or a second host.
#   * the healthcheck is green - it needs bash, not sh, and the first version of it failed
#     every probe (see the comment in the Compose template).
#   * the DICOM port is NOT on the host - the default this role promises, and the one with
#     real consequences if it silently changes: a published container port bypasses ufw.
#   * metrics answer over the shared network, as Prometheus reaches them - measured from a
#     container, not from the host, because that is the path that actually matters (#64).
#
# Not meant to be executed directly. Expects: VM_IP, SSH_KEY, ANSIBLE_USER.

run_orthanc_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"
  # Must match what write_test_inventory puts in orthanc_users.
  local user="admin"
  local pass="throwaway-test-password"
  local failed=0

  echo "==> Checking the Orthanc container runs unprivileged"
  local uid
  uid="$(ssh "${ssh_opts[@]}" "${remote}" 'sudo docker exec linumed-base-orthanc id -u' 2>/dev/null || true)"
  if [ "${uid}" != "65532" ]; then
    echo "FAIL: Orthanc runs as uid '${uid}', expected 65532 - see ADR 0009" >&2
    failed=1
  fi

  echo "==> Checking Orthanc uses PostgreSQL and not its built-in database"
  local backend
  backend="$(ssh "${ssh_opts[@]}" "${remote}" \
    "curl -s -u ${user}:${pass} http://127.0.0.1:8042/system" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('DatabaseBackendPlugin') or '')" 2>/dev/null || true)"
  case "${backend}" in
    *PostgreSQL*) ;;
    *) echo "FAIL: DatabaseBackendPlugin is '${backend}', expected the PostgreSQL plugin" >&2; failed=1 ;;
  esac

  echo "==> Checking the container healthcheck is green"
  local health
  health="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sudo docker inspect linumed-base-orthanc --format "{{.State.Health.Status}}"' 2>/dev/null || true)"
  if [ "${health}" != "healthy" ]; then
    echo "FAIL: Orthanc health is '${health}', expected 'healthy'" >&2
    ssh "${ssh_opts[@]}" "${remote}" \
      'sudo docker inspect linumed-base-orthanc --format "{{range .State.Health.Log}}{{.ExitCode}} {{.Output}}{{end}}"' >&2 || true
    failed=1
  fi

  # The default this role promises. Checked against the host's listening sockets rather than
  # against the Compose file, because the file is what we wrote and the socket is what an
  # attacker would find.
  echo "==> Checking the DICOM port is not published to the host"
  local dicom_listening
  dicom_listening="$(ssh "${ssh_opts[@]}" "${remote}" \
    'sudo ss -tlnp 2>/dev/null | grep -c ":4242 " || true')"
  if [ "${dicom_listening}" != "0" ]; then
    echo "FAIL: something is listening on 4242 - the DICOM port should not be published by default" >&2
    ssh "${ssh_opts[@]}" "${remote}" 'sudo ss -tlnp | grep ":4242 "' >&2 || true
    failed=1
  fi

  echo "==> Checking the metrics endpoint answers over the shared network"
  local metrics_code
  metrics_code="$(ssh "${ssh_opts[@]}" "${remote}" \
    "sudo docker run --rm --network linumed-base-metrics curlimages/curl:8.11.1 \
     -s -o /dev/null -w '%{http_code}' -u metrics:throwaway-test-metrics-password \
     --max-time 10 http://linumed-base-orthanc:8042/tools/metrics-prometheus" 2>/dev/null || true)"
  if [ "${metrics_code}" != "200" ]; then
    echo "FAIL: metrics over the shared network returned '${metrics_code}', expected 200" >&2
    failed=1
  fi

  [ "${failed}" -eq 0 ] || return 1
  echo "==> PASS: Orthanc is unprivileged, on PostgreSQL, healthy, closed to DICOM and serving metrics"
}
