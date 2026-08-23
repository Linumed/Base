#!/bin/bash
# Standalone check for scripts/select-roles.sh (issue #87) - not sourced by vm-test.sh,
# because none of this needs a VM: the script only ever touches the local filesystem.
# Runs in ansible-lint.yml on every push instead, at effectively zero cost, rather than
# waiting for the one VM slot vm-test.yml has.
#
# Exercises only the --non-interactive path, deliberately: whiptail's dialogs cannot be
# driven headlessly in CI, and the dialogs are a thin wrapper around the same
# validate_selection/render_roles_yaml/write_roles_block functions this path also uses -
# so this covers the logic that matters without needing a fake terminal.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/select-roles.sh"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

fail=0

expect_success() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "==> PASS: ${desc}"
  else
    echo "FAIL: expected success - ${desc}" >&2
    fail=1
  fi
}

expect_failure() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: expected failure, got success - ${desc}" >&2
    fail=1
  else
    echo "==> PASS: ${desc}"
  fi
}

# A misspelled role name must be rejected, not silently dropped - the whole reason a
# list was chosen over per-role booleans in #86.
expect_failure "unknown role name is rejected" \
  "${SCRIPT}" --file "${WORK_DIR}/a.yml" --non-interactive "caddyy"

# bridgelink_exporter_enabled defaults to false (ansible/roles/bridgelink/defaults/main.yml),
# so bridgelink alone is a normal, supported combination and must NOT be rejected - if
# this ever starts failing, someone made the tool more restrictive than the kit actually
# is.
expect_success "bridgelink without monitoring is accepted" \
  "${SCRIPT}" --file "${WORK_DIR}/c.yml" --non-interactive "bridgelink backup"

# The actual output, not just the exit code: common and docker are always prepended,
# and only the requested optional roles appear.
"${SCRIPT}" --file "${WORK_DIR}/d.yml" --non-interactive "caddy monitoring backup" >/dev/null
if diff -q <(python3 -c "
import yaml
d = yaml.safe_load(open('${WORK_DIR}/d.yml'))
print(sorted(d['linumed_base_roles']))
") <(echo "['backup', 'caddy', 'common', 'docker', 'monitoring']") >/dev/null; then
  echo "==> PASS: written selection matches exactly what was requested"
else
  echo "FAIL: written role list does not match the requested selection" >&2
  fail=1
fi

# Re-running against the same file with a different selection must replace the block,
# not duplicate it, and must not touch anything outside the markers.
cat > "${WORK_DIR}/e.yml" <<'EOF'
---
backup_repository: "/var/backups/restic"
EOF
"${SCRIPT}" --file "${WORK_DIR}/e.yml" --non-interactive "caddy backup" >/dev/null
"${SCRIPT}" --file "${WORK_DIR}/e.yml" --non-interactive "monitoring" >/dev/null
begin_count=$(grep -c '^# BEGIN linumed_base_roles' "${WORK_DIR}/e.yml")
end_count=$(grep -c '^# END linumed_base_roles' "${WORK_DIR}/e.yml")
if [ "${begin_count}" = "1" ] && [ "${end_count}" = "1" ]; then
  echo "==> PASS: re-running replaces the block instead of duplicating it"
else
  echo "FAIL: expected exactly one BEGIN/END marker pair after two runs, got ${begin_count}/${end_count}" >&2
  fail=1
fi
if grep -q 'backup_repository' "${WORK_DIR}/e.yml"; then
  echo "==> PASS: content outside the markers survives a re-run"
else
  echo "FAIL: backup_repository was lost across a re-run" >&2
  fail=1
fi
if ! grep -q 'caddy' "${WORK_DIR}/e.yml"; then
  echo "==> PASS: the first run's selection (caddy) is gone after the second run"
else
  echo "FAIL: the old selection is still present - the block was appended, not replaced" >&2
  fail=1
fi

# The example inventory itself must be a valid target: this is what an operator's first
# real run of this tool touches, so it is not enough for the script's own tests to pass
# in isolation.
cp "${REPO_ROOT}/ansible/inventory/example/group_vars/linumed/vars.yml" "${WORK_DIR}/example.yml"
expect_success "the shipped example inventory is a valid target" \
  "${SCRIPT}" --file "${WORK_DIR}/example.yml" --non-interactive "caddy monitoring bridgelink backup"
if grep -q 'backup_repository: "/var/backups/restic"' "${WORK_DIR}/example.yml"; then
  echo "==> PASS: the example's own required setting survives a run against it"
else
  echo "FAIL: running against the real example inventory lost backup_repository" >&2
  fail=1
fi

# The result has to be valid YAML that Ansible could actually load, not merely a file
# select-roles.sh is satisfied with.
python3 -c "
import yaml, sys
d = yaml.safe_load(open('${WORK_DIR}/example.yml'))
assert isinstance(d.get('linumed_base_roles'), list), 'linumed_base_roles missing or not a list'
assert set(d['linumed_base_roles']) == {'common', 'docker', 'caddy', 'monitoring', 'bridgelink', 'backup'}
" && echo "==> PASS: the written example inventory parses as valid YAML with the expected roles" || {
  echo "FAIL: the written file is not valid YAML, or the roles are wrong" >&2
  fail=1
}

if [ "${fail}" -eq 0 ]; then
  echo "==> PASS: scripts/select-roles.sh behaves correctly (issue #87)"
fi
exit "${fail}"
