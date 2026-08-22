#!/bin/bash
# Interactive role selection for linumed_base_roles (issue #86), so an operator can pick
# a subset without hand-editing YAML or knowing the dependency rules from memory.
#
# `whiptail` - the same toolkit Debian's own installer uses - not a web UI: this runs on
# the control node before any playbook does, generates plain YAML an operator can read
# before committing to it, and opens nothing on the network. See ADR 0003, which this does
# not conflict with for exactly that reason.
#
# Deliberately does ONE thing: writes `linumed_base_roles`. It does not touch
# `hosts.yml`, `vars.yml`'s other settings, or `vault.yml` - onboarding beyond role
# selection stays the README's job. See issue #87 for why the scope stops here.
#
# `common` and `docker` are not offered as choices - every documented deployment shape in
# this repo (site.yml, node-baseline.yml) includes both, and dropping either is "write a
# playbook of your own" territory per CONVENTIONS.md, not something this tool covers.
#
# `orthanc` is only offered once `monitoring` is selected, and this is checked at
# selection time, not just deployment time: `orthanc_metrics_enabled` defaults to true
# (ansible/roles/orthanc/defaults/main.yml), so orthanc without monitoring fails site.yml's
# own preflight (issue #86 stage 1) the moment it is applied. Graying it out here means an
# operator never reaches that error in the first place.
#
# `bridgelink` is NOT gated the same way, on purpose, not by oversight:
# `bridgelink_exporter_enabled` defaults to FALSE (ansible/roles/bridgelink/defaults/main.yml),
# so bridgelink alone, without monitoring, is a normal and supported combination under
# defaults. Gating it here would be more restrictive than the kit actually is.
#
# These rules are duplicated from ansible/playbooks/site.yml's pre_tasks by necessity, the
# same way the linumed-base-metrics network name is duplicated across three roles' defaults
# (see ADR 0010) - there is no shared source a bash script and Ansible's Jinja can both
# read. If site.yml's dependency preflights change, this file's comments say so and need
# the same edit.
#
# Usage:
#   ./select-roles.sh --file inventory/myhospital/group_vars/linumed/vars.yml
#   ./select-roles.sh --file <path> --non-interactive "caddy monitoring orthanc backup"
#
# --non-interactive takes the space-separated OPTIONAL roles (excluding common/docker,
# which are always included) and skips whiptail entirely - used by the test suite, and
# usable by anyone scripting onboarding without a TTY.
set -euo pipefail

TARGET_FILE=""
NON_INTERACTIVE=""
HAVE_NON_INTERACTIVE=0

usage() {
  cat <<'EOF'
Usage: select-roles.sh --file PATH [--non-interactive "ROLE ROLE ..."]

  --file PATH            group_vars/linumed/vars.yml to write into (or create)
  --non-interactive LIST  space-separated optional roles (caddy monitoring bridgelink
                          orthanc backup) - skips the whiptail dialogs
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) TARGET_FILE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE="$2"; HAVE_NON_INTERACTIVE=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$TARGET_FILE" ]; then
  echo "::error:: --file is required" >&2
  usage >&2
  exit 1
fi

# The known-good optional roles and the one dependency rule, in one place so both the
# interactive and non-interactive paths validate identically.
ALL_OPTIONAL="caddy monitoring bridgelink orthanc backup"

validate_selection() {
  # $1: space-separated optional roles chosen
  local chosen="$1"
  local role
  for role in $chosen; do
    case " $ALL_OPTIONAL " in
      *" $role "*) ;;
      *)
        echo "::error:: '$role' is not one of: $ALL_OPTIONAL" >&2
        return 1
        ;;
    esac
  done
  case " $chosen " in
    *" orthanc "*)
      case " $chosen " in
        *" monitoring "*) ;;
        *)
          echo "::error:: orthanc needs monitoring - orthanc_metrics_enabled defaults to" >&2
          echo "true, and site.yml's own preflight refuses to deploy orthanc without the" >&2
          echo "network monitoring creates. Add monitoring, or deselect orthanc." >&2
          return 1
          ;;
      esac
      ;;
  esac
}

render_roles_yaml() {
  # $1: space-separated optional roles chosen. Always prepends common, docker.
  local chosen="$1"
  echo "linumed_base_roles:"
  echo "  - common"
  echo "  - docker"
  local role
  for role in caddy monitoring bridgelink orthanc backup; do
    case " $chosen " in
      *" $role "*) echo "  - $role" ;;
    esac
  done
}

# Replaces the block between the markers if present, appends a new marked block
# otherwise. Never touches anything outside the markers - re-running this script must
# not disturb backup_repository or anything else an operator already set by hand.
write_roles_block() {
  local file="$1"
  local yaml="$2"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ -f "$file" ] && grep -q '^# BEGIN linumed_base_roles' "$file"; then
    awk -v yaml="$yaml" '
      /^# BEGIN linumed_base_roles/ { print; print yaml; skip=1; next }
      /^# END linumed_base_roles/   { skip=0 }
      skip { next }
      { print }
    ' "$file" > "$tmp"
  else
    [ -f "$file" ] && cp "$file" "$tmp"
    {
      echo ""
      echo "# --- Which roles this host runs (issue #86) ---"
      echo "#"
      echo "# Managed by scripts/select-roles.sh (issue #87) - re-run it to change the"
      echo "# selection rather than hand-editing the list below; a hand edit survives the"
      echo "# next run only if it stays between these two markers."
      echo "# BEGIN linumed_base_roles"
      echo "$yaml"
      echo "# END linumed_base_roles"
    } >> "$tmp"
  fi

  mkdir -p "$(dirname "$file")"
  mv "$tmp" "$file"
}

if [ "$HAVE_NON_INTERACTIVE" -eq 1 ]; then
  validate_selection "$NON_INTERACTIVE"
  yaml="$(render_roles_yaml "$NON_INTERACTIVE")"
  write_roles_block "$TARGET_FILE" "$yaml"
  echo "Wrote linumed_base_roles to $TARGET_FILE:"
  echo "$yaml"
  exit 0
fi

command -v whiptail >/dev/null 2>&1 || {
  echo "::error:: whiptail is not installed. On Debian: apt install whiptail" >&2
  exit 1
}

# Step 1: the roles with no selection-time dependency. All pre-checked, matching
# site.yml's default (every role runs unless told otherwise).
STEP1=$(whiptail --title "Linumed Base - role selection" --checklist \
  "common and docker are always included. Choose the rest (space to toggle):" \
  16 70 4 \
  "caddy" "Reverse proxy with automatic TLS" ON \
  "monitoring" "Prometheus, Grafana, Loki, Alertmanager" ON \
  "bridgelink" "HL7/FHIR integration engine" ON \
  "backup" "Encrypted restic backups" ON \
  3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 1; }

STEP1_CLEAN=$(echo "$STEP1" | tr -d '"')

# Step 2: orthanc, offered only if monitoring was selected - the grayed-out behaviour
# the issue asked for, done by not presenting the choice at all rather than presenting
# and then rejecting it.
ORTHANC=""
case " $STEP1_CLEAN " in
  *" monitoring "*)
    if whiptail --title "Linumed Base - role selection" --yesno \
      "Deploy orthanc (DICOM archive)?\n\nOnly offered because monitoring is selected - orthanc's metrics are on by default and need monitoring's network to exist." \
      10 70; then
      ORTHANC="orthanc"
    fi
    ;;
  *)
    whiptail --title "Linumed Base - role selection" --msgbox \
      "orthanc is not offered: it is not selected, and orthanc's metrics default to on, which needs monitoring's network to exist. Select monitoring and run this again to include orthanc." \
      10 70
    ;;
esac

CHOSEN="$STEP1_CLEAN $ORTHANC"
validate_selection "$CHOSEN"
YAML="$(render_roles_yaml "$CHOSEN")"

# The confirmation the issue asked for: readable before it is written, not just before
# it is applied. whiptail --textbox needs a file, not a string.
CONFIRM_FILE="$(mktemp)"
trap 'rm -f "$CONFIRM_FILE"' EXIT
printf 'This will be written to %s:\n\n%s\n' "$TARGET_FILE" "$YAML" > "$CONFIRM_FILE"
whiptail --title "Confirm" --textbox "$CONFIRM_FILE" 20 70

if whiptail --title "Confirm" --yesno "Write this selection now?" 8 50; then
  write_roles_block "$TARGET_FILE" "$YAML"
  echo "Wrote linumed_base_roles to $TARGET_FILE."
else
  echo "Cancelled, nothing written."
  exit 1
fi
