#!/bin/bash
# Establishes the baseline every Ansible role in this repo assumes: python3, sudo, and a
# sudo-capable user with an SSH key. Debian 13 ships none of these on a minimal/netinst
# install - python3, sudo, and openssh-server are all `Priority: optional` (issue #13).
#
# Deliberately plain bash, no Ansible dependency - Ansible itself needs python3 to run,
# so this has to work before it exists. Deliberately does NOT do anything the `common`
# role is responsible for (hardening, ufw, fail2ban, sshd config) - this script only
# gets you to the point where `site.yml` can start.
#
# Usage:
#   sudo ./bootstrap.sh --user linumed --key "ssh-ed25519 AAAA... you@host"
#   sudo ./bootstrap.sh --user linumed --key-file ~/.ssh/id_ed25519.pub
#   sudo ./bootstrap.sh --user linumed --key-file ~/.ssh/id_ed25519.pub --nopasswd
#
# --nopasswd grants the user passwordless sudo (NOPASSWD in /etc/sudoers.d/). Off by
# default - a hardening-focused kit shouldn't default to that. Without it, Ansible needs
# `--ask-become-pass` (see README.md).
set -euo pipefail

TARGET_USER=""
SSH_KEY=""
SSH_KEY_FILE=""
NOPASSWD=0

usage() {
  cat <<'EOF'
Usage: bootstrap.sh --user NAME (--key "KEY" | --key-file PATH) [--nopasswd]

  --user NAME       Username to create (or reuse, if it already exists)
  --key "KEY"        Public key content, e.g. "ssh-ed25519 AAAA... comment"
  --key-file PATH    Path to a public key file (alternative to --key)
  --nopasswd         Grant passwordless sudo (off by default)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) TARGET_USER="$2"; shift 2 ;;
    --key) SSH_KEY="$2"; shift 2 ;;
    --key-file) SSH_KEY_FILE="$2"; shift 2 ;;
    --nopasswd) NOPASSWD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root (not via sudo - sudo itself may not be installed yet)." >&2
  echo "Log in as root or use 'su -' first." >&2
  exit 1
fi

if [ -z "${TARGET_USER}" ]; then
  echo "Missing --user." >&2
  usage >&2
  exit 1
fi

if [ -n "${SSH_KEY_FILE}" ]; then
  [ -r "${SSH_KEY_FILE}" ] || { echo "Cannot read --key-file '${SSH_KEY_FILE}'." >&2; exit 1; }
  SSH_KEY="$(cat "${SSH_KEY_FILE}")"
fi
if [ -z "${SSH_KEY}" ]; then
  echo "Missing --key or --key-file." >&2
  usage >&2
  exit 1
fi
# Loose sanity check, not full validation - catches "pasted the private key by mistake"
# and empty/garbage input without trying to be a full SSH key parser.
case "${SSH_KEY}" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *) ;;
  *) echo "--key doesn't look like a public key (expected it to start with ssh-ed25519, ssh-rsa, or ecdsa-sha2-...)." >&2; exit 1 ;;
esac

if [ ! -r /etc/os-release ] || ! grep -q '^VERSION_CODENAME=trixie$' /etc/os-release; then
  echo "This script targets Debian 13 (trixie) only, matching the rest of this repo." >&2
  exit 1
fi

echo "==> Installing python3, sudo, openssh-server (skips what's already present)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 sudo openssh-server

echo "==> Ensuring openssh-server is enabled and running"
systemctl enable --now ssh.service >/dev/null

if id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "==> User '${TARGET_USER}' already exists, reusing it"
else
  echo "==> Creating user '${TARGET_USER}'"
  useradd --create-home --shell /bin/bash "${TARGET_USER}"
fi

echo "==> Adding '${TARGET_USER}' to the sudo group"
usermod -aG sudo "${TARGET_USER}"

USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

echo "==> Installing the SSH key into ${AUTH_KEYS}"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${AUTH_KEYS}"
if ! grep -qxF "${SSH_KEY}" "${AUTH_KEYS}"; then
  echo "${SSH_KEY}" >> "${AUTH_KEYS}"
fi
chmod 600 "${AUTH_KEYS}"
chown -R "${TARGET_USER}:${TARGET_USER}" "${SSH_DIR}"

if [ "${NOPASSWD}" -eq 1 ]; then
  echo "==> Granting passwordless sudo to '${TARGET_USER}'"
  echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${TARGET_USER}-bootstrap"
  chmod 440 "/etc/sudoers.d/90-${TARGET_USER}-bootstrap"
  visudo -cf "/etc/sudoers.d/90-${TARGET_USER}-bootstrap" >/dev/null
fi

# Verify the exact contract the common role's SSH preflight checks for
# (ansible/roles/common/tasks/ssh.yml) - UID >= 1000, sudo group membership, a
# populated authorized_keys. Catching a mismatch here beats catching it as an opaque
# Ansible preflight failure later.
echo "==> Verifying the preflight contract the common role expects"
UID_NUM="$(id -u "${TARGET_USER}")"
IN_SUDO_GROUP=0
id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx sudo && IN_SUDO_GROUP=1
KEY_COUNT="$(grep -c . "${AUTH_KEYS}" || true)"

FAIL=0
[ "${UID_NUM}" -ge 1000 ] || { echo "  FAIL: UID ${UID_NUM} is below 1000"; FAIL=1; }
[ "${IN_SUDO_GROUP}" -eq 1 ] || { echo "  FAIL: not a member of the sudo group"; FAIL=1; }
[ "${KEY_COUNT}" -gt 0 ] || { echo "  FAIL: authorized_keys is empty"; FAIL=1; }
if [ "${FAIL}" -eq 1 ]; then
  echo "Bootstrap finished but the preflight contract is not satisfied - see failures above." >&2
  exit 1
fi

echo
echo "==> Done. '${TARGET_USER}' (UID ${UID_NUM}) is sudo-capable with an SSH key installed."
if [ "${NOPASSWD}" -eq 0 ]; then
  echo "    sudo requires a password - pass --ask-become-pass to ansible-playbook, or"
  echo "    re-run this script with --nopasswd for unattended use."
fi
