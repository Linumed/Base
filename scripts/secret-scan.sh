#!/usr/bin/env bash
# Secret scan with gitleaks (issue #129).
#
# Usage:
#   scripts/secret-scan.sh            # staged changes only - what a pre-commit hook runs
#   scripts/secret-scan.sh --history  # every commit, what the CI job runs
#
# Why this exists: this repository is public and mirrored. A secret that reaches `main`
# is outside within the mirror's next run, and the only remedy is rotating it - deleting
# it from history does not un-publish it. A scan that runs after the push is a smoke
# alarm, not a lock, so there is a pre-commit hook as well as the CI job.
#
# The hook itself is not versioned (.git/hooks/ never is). It is one line that calls this
# script, see "Secret scan" in CONVENTIONS.md for how to set it up. The logic lives here so
# that it is reviewed like any other code and CI uses the same invocation.
#
# gitleaks is used as a pinned release binary, not as the gitleaks-action: the action needs
# a paid licence for organisation repositories, and the runner has no broad Docker access
# anyway (same reasoning as trivy in .forgejo/workflows/image-scan.yml). The version is
# pinned in the workflow; this script refuses to run against a different one, because a
# scanner that changes its verdict without the repository changing is a verdict nobody
# trusts.
#
# Fails closed: if gitleaks is missing or the wrong version, the commit is refused with
# the install steps. A hook that silently does nothing is worse than no hook.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${REPO_ROOT}/.forgejo/workflows/secret-scan.yml"

want="$(sed -n 's/^ *GITLEAKS_VERSION=\([0-9.]*\).*/\1/p' "${WORKFLOW}" | head -1)"
[ -n "${want}" ] || { echo "secret-scan: no GITLEAKS_VERSION in ${WORKFLOW}" >&2; exit 2; }

gitleaks_bin="$(command -v gitleaks || true)"
[ -n "${gitleaks_bin}" ] || { [ -x "${HOME}/.local/bin/gitleaks" ] && gitleaks_bin="${HOME}/.local/bin/gitleaks"; }
if [ -z "${gitleaks_bin}" ]; then
  cat >&2 <<EOF
secret-scan: gitleaks ${want} not found.
  Download gitleaks_${want}_linux_x64.tar.gz and gitleaks_${want}_checksums.txt from
  https://github.com/gitleaks/gitleaks/releases/tag/v${want}, check the sum with
  'sha256sum -c --ignore-missing', and put the 'gitleaks' binary on PATH
  (for example ~/.local/bin).
EOF
  exit 2
fi

have="$("${gitleaks_bin}" version | head -1)"
if [ "${have}" != "${want}" ]; then
  echo "secret-scan: found gitleaks ${have}, the workflow pins ${want} - install that one." >&2
  exit 2
fi

cd "${REPO_ROOT}"
case "${1:-}" in
  "")
    exec "${gitleaks_bin}" git --pre-commit --staged --redact --no-banner --verbose
    ;;
  --history)
    exec "${gitleaks_bin}" git --redact --no-banner --verbose
    ;;
  *)
    echo "usage: $0 [--history]" >&2
    exit 2
    ;;
esac
