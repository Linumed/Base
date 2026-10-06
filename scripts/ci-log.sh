# Sourced, not executed: every workflow sets BASH_ENV to this file, so each `run:` step -
# a non-interactive bash - loads it before its own commands. It copies the step's output
# into $CI_LOG_FILE while leaving the normal job log untouched (tee writes to both), so
# scripts/ci-failure-issue.py can quote the end of it when the job fails.
#
# Why a copy at all (issue #117): Forgejo does not reliably archive task logs. Run 319 of
# vm-test failed on 2026-09-23, and when someone looked two weeks later its log was gone
# (#116) - the cause can no longer be determined. The issue the failure step opens keeps
# the last lines where they cannot expire.
#
# Why BASH_ENV rather than a `| tee` on every step: it covers steps added later without
# anyone remembering to add it. CI_LOG_TEE guards against nesting - `bash test/vm-test.sh`
# starts a second bash that would load this file again and write every line twice.
if [ -n "${CI_LOG_FILE:-}" ] && [ -z "${CI_LOG_TEE:-}" ]; then
  export CI_LOG_TEE=1
  exec > >(tee -a "${CI_LOG_FILE}") 2>&1
fi
