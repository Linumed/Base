#!/usr/bin/env bash
# Shared by test/vm-test.sh: deploy the previous release onto the pristine VM before
# `main` ever touches it, so the "First run" inside run_site_idempotency_check (which
# happens right after this) is not a fresh install but a real upgrade (issue #89).
#
# Why this needed measuring rather than assuming: before 2026-08-22, "git pull, run
# site.yml again" was a plausible-sounding answer with nobody ever having tried it.
# idempotency across *one* apply and idempotency across a *version boundary* are
# different claims - changed defaults, renamed files, a template that moves a value from
# a variable to a literal can all produce a real, if harmless, `changed` on the first
# post-upgrade run. Measured once by hand (v0.4.0 -> v1.0.0): exactly two changes, both
# `orthanc` - a config file whose content changed because issue #80 made
# `orthanc_http_port`'s container side a literal, and the resulting container restart.
# Nothing else moved, and the second apply was `changed=0`. This check is what keeps that
# claim true going forward instead of re-verifying it by hand before every tag.
#
# Deliberately reuses the VM `vm-test.sh` already provisions rather than starting a
# second one: a full VM lifecycle costs several minutes on this hardware, and the only
# thing an upgrade check actually needs is "something was deployed here before main was".
# Applying the previous tag first and letting the existing idempotency check's own first
# apply *be* the upgrade step costs one extra `site.yml` run, not a second VM.
#
# Not meant to be executed directly. Expects: REPO_ROOT, WORK_DIR, VM_IP, SSH_KEY,
# ANSIBLE_USER, and to run BEFORE write_test_inventory / run_site_idempotency_check.

# The tag to upgrade FROM. Deliberately a fixed literal, not "the latest tag" auto-detected
# - an automatic pick would silently start testing a different upgrade the moment a new
# tag lands, which is exactly the kind of drift this repository does not tolerate
# elsewhere (see ADR 0010 on why coupled literals are compared, not inferred). Bump this
# by hand to the version just released, as part of preparing the NEXT release - if it is
# still v1.0.0 when v1.2.0 is being tagged, this is testing an increasingly irrelevant
# upgrade.
UPGRADE_FROM_TAG="v1.0.0"

run_upgrade_from_previous_tag() {
  local inventory="${WORK_DIR}/inventory.yml"
  local worktree="${WORK_DIR}/upgrade-from-${UPGRADE_FROM_TAG}"

  echo "==> Checking out ${UPGRADE_FROM_TAG} into a worktree"
  (cd "${REPO_ROOT}" && git worktree add --detach "${worktree}" "${UPGRADE_FROM_TAG}")

  # The inventory has to exist before the old tag's site.yml can use it, and it has to
  # carry every secret every role between UPGRADE_FROM_TAG and main might ask for - so
  # this calls the CURRENT write_test_inventory, not a copy frozen at the old tag. That
  # is deliberate: an inventory reflecting what main needs is also a superset of what an
  # older, smaller role set needed, in every case measured so far. If a future role
  # removes a variable the old tag still requires, this comment is where that breaks.
  [ -f "${inventory}" ] || write_test_inventory

  # v1.0.0 still carries the orthanc role, removed on main in #92/ADR 0011 - the shared
  # inventory above no longer sets its secrets, because nothing on main asks for them any
  # more. Supplied here as extra-vars, scoped to only this old-tag deploy, rather than
  # re-adding dead variables to the inventory every other step also uses. Drop this block
  # once UPGRADE_FROM_TAG is bumped past v1.0.0/v1.1.x, whichever release orthanc is gone
  # from on the "from" side too.
  echo "==> Deploying ${UPGRADE_FROM_TAG} (the 'before' side of the upgrade)"
  (
    cd "${worktree}/ansible"
    ansible-playbook -i "${inventory}" playbooks/site.yml \
      -e '{"orthanc_db_password": "throwaway-test-password", "orthanc_users": {"admin": "throwaway-test-password", "metrics": "throwaway-test-metrics-password"}}'
  ) || { echo "FAIL: ${UPGRADE_FROM_TAG} itself failed to deploy - the upgrade check can't start from a broken baseline" >&2; return 1; }

  echo "==> PASS: ${UPGRADE_FROM_TAG} deployed cleanly, ready to be upgraded"

  (cd "${REPO_ROOT}" && git worktree remove --force "${worktree}")
}

# Called after run_site_idempotency_check has applied main and confirmed changed=0 on
# the second run. Reports what changed on the FIRST apply - that number is the actual
# subject of this check, not just "did it succeed". Reads the log
# run_site_idempotency_check writes for exactly this purpose (test/lib/site-idempotency.sh).
report_upgrade_changed_count() {
  local log="${WORK_DIR}/site-first-run.log"
  local changed
  changed="$(grep -oE 'changed=[0-9]+' "${log}" | tail -1 | cut -d= -f2)"
  echo "==> Upgrade from ${UPGRADE_FROM_TAG} to this commit: ${changed} task(s) changed on first apply"
  if [ "${changed}" -gt 20 ]; then
    # No hard failure - a large number is not necessarily wrong, e.g. a release that
    # deliberately renames a lot of files says so under ### Breaking. But a number this
    # far past the one measured example (2) is worth a human looking at the log rather
    # than scrolling past it, so this is loud without being a gate.
    echo "::warning::${changed} changes on upgrade is well above the one measured baseline (2, v0.4.0 -> v1.0.0) - worth checking the log rather than assuming it's fine"
  fi
}
