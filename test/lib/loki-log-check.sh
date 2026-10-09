#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify that logs actually arrive in Loki - the host journal
# and container output, the two streams the monitoring role's Alloy config ships (#123).
#
# Why it needs its own check: until this existed, nothing in test/ ever queried Loki. A
# green run proved that Alloy and Loki containers start and that Prometheus can scrape
# its targets - not that a single log line gets from the host to the place an operator
# looks for it. The gap had a concrete near miss: Alloy 1.19 overwrote the configured
# `job` label of loki.source.journal with the component id (grafana/alloy#6508, fixed in
# 1.20 by #6982). The Log Explorer dashboard and docs/roles/monitoring.md both query
# {job="journal"}; on 1.19 they would have come back empty while every check stayed green.
#
# Queries through Grafana's datasource proxy rather than Loki directly. Loki publishes no
# port by design (docs/roles/monitoring.md, "Pitfalls"), and the documented way in - a
# throwaway curl container in Loki's network namespace - would pull an unpinned image into
# the test. Going through Grafana also tests the path an operator actually uses: the
# provisioned datasource with its stable uid `loki` (ADR 0008).
#
# Not meant to be executed directly. Expects: VM_IP, SSH_KEY, ANSIBLE_USER, and a stack
# deployed by run_site_idempotency_check.

# Must match monitoring_grafana_admin_password in write_test_inventory
# (test/lib/site-idempotency.sh) - the throwaway VM's only Grafana credential.
LOKI_CHECK_GRAFANA_AUTH="admin:throwaway-test-password"

# Returns 0 if the LogQL selector in $1 matches at least one line from the last hour.
_loki_has_lines() {
  local selector="$1" response
  response="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${SSH_KEY}" "${ANSIBLE_USER}@${VM_IP}" \
    "curl -s -G -u '${LOKI_CHECK_GRAFANA_AUTH}' \
       'http://127.0.0.1:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range' \
       --data-urlencode 'query=${selector}' --data-urlencode 'limit=1'")" || return 1
  # Parsed on the control node, same reason as check_prometheus_targets_healthy: Python
  # inside an already-quoted ssh argument is a quoting trap.
  echo "${response}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
streams = (d.get('data') or {}).get('result') or []
sys.exit(0 if any(s.get('values') for s in streams) else 1)
"
}

run_loki_log_check() {
  echo "==> Checking that logs arrive in Loki (journal and containers)"
  local selector attempt
  # Shipping is asynchronous - Alloy tails, batches and pushes. Up to 2 minutes per stream
  # on this deliberately slow hardware, checked every 10s, rather than one fixed sleep
  # that is either too short or wastes time on every run.
  for selector in '{job="journal"}' '{container=~".+"}'; do
    for attempt in $(seq 1 12); do
      if _loki_has_lines "${selector}"; then
        echo "==> PASS: Loki has lines for ${selector}"
        continue 2
      fi
      sleep 10
    done
    echo "FAIL: no log lines for ${selector} in Loki after 2 minutes - Alloy runs, but the logs do not arrive (#123)" >&2
    return 1
  done
}
