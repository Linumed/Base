#!/usr/bin/env bash
# Release-time test: runs the README's own "Quick start" section verbatim, block by
# block, against a real Debian 13 netinst install - not a reimplementation of what the
# quick start is supposed to do, but the literal commands it prints.
#
# This closes a gap the README itself used to claim was already closed. It said (until
# issue #106): "a full double-run following this README's own quick start verbatim -
# clone, copy the example inventory, fill in the vault, deploy" - describing
# test/vm-test-netinst.sh. That was never true: vm-test-netinst.sh calls bootstrap.sh
# with --nopasswd (never exercising the plain --ask-become-pass path the quick start
# shows) and hands site.yml a synthetic inventory built by
# test/lib/site-idempotency.sh's write_test_inventory - no git clone, no
# scripts/select-roles.sh, no vault.yml. Found by literally executing the quick start
# rather than reading it (issue #106), which is exactly what this script now does so it
# stays found.
#
# Two real defects this script caught on its first real run, both fixed in issue #106:
#   - `cd ansible` followed by `./scripts/select-roles.sh` can never resolve: scripts/
#     only exists at the repo root, inventory/myhospital/... only exists under ansible/.
#   - `--ask-become-pass` cannot work against the quick start's own bootstrap.sh example
#     (no --nopasswd): useradd never sets a login password, so the account is locked.
#     This script now performs the corrected, documented remedy (passwd on the target)
#     as a literal step, exercising the real become path instead of a synthetic one.
#
# NOT part of regular CI - like vm-test-netinst.sh, a real Debian installer run takes far
# longer than booting a cloud image. Run before releases, and after any change to the
# quick start's wording or the scripts it names.
#
# Required packages, same as test/vm-test.sh and test/vm-test-netinst.sh:
#   libvirt-daemon-system virtinst cloud-image-utils qemu-utils ansible ansible-lint git
set -uo pipefail  # deliberately no -e: every quick-start block is reported PASS/FAIL, not
                  # aborted on the first one that fails - a later block can still be
                  # informative even if an earlier one broke

export LIBVIRT_DEFAULT_URI="qemu:///system"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_REMOTE="${QUICKSTART_TEST_REMOTE:-https://github.com/Linumed/Base.git}"
# See test/vm-test.sh for why /var/tmp, not /tmp, on the maintainer's dev server.
WORK_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/linumed-quickstart.XXXXXX")"
chmod 711 "${WORK_DIR}"
VM_NAME="linumed-quickstart-$$"
SSH_KEY="${WORK_DIR}/id_ed25519"
ROOT_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
RESULTS="${WORK_DIR}/results.txt"
: > "${RESULTS}"

fail_count=0

step() {  # step <name> -- <command...>: PASS/FAIL to RESULTS, always continues
  local name="$1"; shift
  echo "==> ${name}"
  if "$@"; then
    echo "PASS  ${name}" | tee -a "${RESULTS}"
  else
    local rc=$?
    echo "FAIL  ${name} (exit ${rc})" | tee -a "${RESULTS}"
    fail_count=$((fail_count + 1))
  fi
}

# Steps the README documents as an interactive/manual action (editing a file, accepting
# a host-key prompt) that this script has to perform non-interactively. Not a defect -
# recorded so the results are honest about what was actually exercised headlessly.
deviation() {
  echo "DEVIATION  $1" | tee -a "${RESULTS}"
}

cleanup() {
  virsh destroy "${VM_NAME}" >/dev/null 2>&1 || true
  virsh undefine "${VM_NAME}" --nvram >/dev/null 2>&1 || true
  echo
  echo "===================================================================="
  echo "RESULT"
  echo "===================================================================="
  cat "${RESULTS}"
  if [ "${fail_count}" -gt 0 ]; then
    echo
    echo "${fail_count} block(s) of the quick start failed - see output above."
  fi
  echo "Work directory (kept for inspection): ${WORK_DIR}"
}
trap cleanup EXIT

for tool in virt-install virsh cloud-localds qemu-img ansible-playbook ansible-vault git; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "Missing required tool: ${tool}. Install: libvirt-daemon-system virtinst cloud-image-utils qemu-utils ansible git" >&2
    exit 1
  }
done

echo "==> ansible-lint"
(cd "${REPO_ROOT}/ansible" && ansible-lint) || { echo "FAIL  ansible-lint" | tee -a "${RESULTS}"; }

# ---------------------------------------------------------------------------
# Target: a real netinst install, deliberately minimal - same preseed shape as
# test/vm-test-netinst.sh, kept in sync by hand (issue #14's rationale applies here too:
# a cloud image already has python3/sudo/git and would silently mask their absence).
# ---------------------------------------------------------------------------
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso"
echo "==> Downloading Debian 13 netinst ISO"
curl -fsSL -o "${WORK_DIR}/netinst.iso" "${ISO_URL}"
qemu-img create -f qcow2 "${WORK_DIR}/disk.qcow2" 10G >/dev/null
chmod 644 "${WORK_DIR}/disk.qcow2" "${WORK_DIR}/netinst.iso"
ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "linumed-quickstart-test" >/dev/null

cat > "${WORK_DIR}/preseed.cfg" <<EOF
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${VM_NAME}
d-i netcfg/get_domain string local
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i passwd/root-login boolean true
d-i passwd/root-password password ${ROOT_PASSWORD}
d-i passwd/root-password-again password ${ROOT_PASSWORD}
d-i passwd/make-user boolean false
d-i clock-setup/utc boolean true
d-i time/zone string Etc/UTC
d-i clock-setup/ntp boolean true
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
tasksel tasksel/first multiselect
d-i pkgsel/include string openssh-server
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default
d-i preseed/late_command string \
  cp /id_ed25519.pub /target/root/id_ed25519.pub; \
  in-target mkdir -p /root/.ssh; \
  in-target sh -c 'cat /root/id_ed25519.pub > /root/.ssh/authorized_keys'; \
  in-target rm /root/id_ed25519.pub; \
  in-target chmod 700 /root/.ssh; \
  in-target chmod 600 /root/.ssh/authorized_keys
d-i finish-install/reboot_in_progress note
EOF

echo "==> Installing (real installer, takes a while)"
virt-install \
  --name "${VM_NAME}" --memory 2048 --vcpus 2 \
  --disk "path=${WORK_DIR}/disk.qcow2,format=qcow2" \
  --location "${WORK_DIR}/netinst.iso" \
  --initrd-inject "${WORK_DIR}/preseed.cfg" \
  --initrd-inject "${SSH_KEY}.pub" \
  --extra-args "auto=true priority=critical file=/preseed.cfg console=ttyS0,115200n8" \
  --os-variant debian12 --network network=default --graphics none --noautoconsole --wait -1

VM_IP=""
for _ in $(seq 1 90); do
  # tail -n1, not head -n1: the installer and the installed system get separate DHCP
  # leases for the same MAC - see test/vm-test-netinst.sh for the full story (#14/#25).
  VM_IP="$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | tail -n1 || true)"
  [ -n "${VM_IP}" ] && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 -i "${SSH_KEY}" root@"${VM_IP}" true 2>/dev/null && break
  sleep 5
done
[ -n "${VM_IP}" ] || { echo "FAIL  VM never came up after install" | tee -a "${RESULTS}"; exit 1; }
echo "VM reachable at ${VM_IP}"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY} root@${VM_IP}"

step "target is actually minimal (no python3, no sudo)" \
  bash -c "! ${SSH} 'command -v python3 || command -v sudo' >/dev/null 2>&1"

# A person accepts the host-key prompt interactively during their own scp/ssh below and
# it lands in their real known_hosts - ansible-playbook later just works. This script has
# no such file to reuse, so it disables the check for itself only.
export ANSIBLE_HOST_KEY_CHECKING=False

# ---------------------------------------------------------------------------
# The quick start, block by block, in a directory this script owns - not $REPO_ROOT, so
# `git clone` is exercised for real rather than assumed to already have happened.
# ---------------------------------------------------------------------------
CONTROL="${WORK_DIR}/control"
mkdir -p "${CONTROL}"
cd "${CONTROL}"

if git clone --quiet "${GIT_REMOTE}" Base 2>"${WORK_DIR}/clone.err"; then
  echo "PASS  git clone ${GIT_REMOTE}" | tee -a "${RESULTS}"
else
  echo "FAIL  git clone ${GIT_REMOTE} - falling back to the local checkout, see clone.err" | tee -a "${RESULTS}"
  deviation "git clone against the remote failed (network?); used a copy of ${REPO_ROOT} instead"
  cp -r "${REPO_ROOT}" Base
fi
cd Base

step "scp scripts/bootstrap.sh root@<target>:~" \
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}" \
    scripts/bootstrap.sh root@"${VM_IP}":~

# Read locally, not on the target - the public key file only exists on this side.
PUBKEY_CONTENT="$(cat "${SSH_KEY}.pub")"
ANSIBLE_USER="vmtest"
# Deliberately WITHOUT --nopasswd - this is what the quick start's own example shows.
step 'ssh root@<target> ./bootstrap.sh --user <username> --key "..."' \
  bash -c "${SSH} \"chmod +x ~/bootstrap.sh && ~/bootstrap.sh --user ${ANSIBLE_USER} --key '${PUBKEY_CONTENT}'\""

cd ansible
step "cp -r inventory/example inventory/myhospital" \
  cp -r inventory/example inventory/myhospital

sed -i "s/ansible_host: 203.0.113.10/ansible_host: ${VM_IP}/; s/ansible_user: admin/ansible_user: ${ANSIBLE_USER}/" \
  inventory/myhospital/hosts.yml
deviation "hosts.yml filled in with sed - the quick start says 'edit', which has no headless equivalent to test"

# A real operator's own key is normally the default SSH identity (~/.ssh/id_ed25519 or
# similar), or loaded in an agent - OpenSSH finds it with no config on hosts.yml's part,
# which is why the README never mentions ansible_ssh_private_key_file. This script's key
# is a fresh one in a throwaway directory and matches neither, so ansible-playbook cannot
# authenticate without being told explicitly. Adding this is a testing-infrastructure
# necessity, not something the quick start is missing.
cat >> inventory/myhospital/hosts.yml <<EOF
          ansible_ssh_private_key_file: ${SSH_KEY}
EOF
deviation "ansible_ssh_private_key_file added to hosts.yml - a real operator's default SSH identity or agent covers this with no config; this script's throwaway key needs to be told explicitly"

step "../scripts/select-roles.sh --file ... --non-interactive (caddy + backup, matching the README's own screenshot)" \
  ../scripts/select-roles.sh --file inventory/myhospital/group_vars/linumed/vars.yml \
    --non-interactive "caddy backup"
deviation "select-roles.sh run with --non-interactive - whiptail's dialogs cannot be driven headlessly (same reasoning as test/select-roles-check.sh)"

step "cp vault.yml.example vault.yml" \
  cp inventory/myhospital/group_vars/linumed/vault.yml.example \
     inventory/myhospital/group_vars/linumed/vault.yml

sed -i "s/CHANGEME-generate-your-own/$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)/g; \
        s/CHANGEME-generate-with-uuidgen/$(uuidgen)/g" \
  inventory/myhospital/group_vars/linumed/vault.yml
deviation "CHANGEME placeholders filled in with sed - only backup_restic_password is exercised by caddy+backup, the values themselves are not the point of this test"

VAULT_PW="${WORK_DIR}/vaultpw"
echo "quickstart-test-vault-password" > "${VAULT_PW}"
step "ansible-vault encrypt inventory/myhospital/group_vars/linumed/vault.yml" \
  ansible-vault encrypt --vault-password-file "${VAULT_PW}" \
    inventory/myhospital/group_vars/linumed/vault.yml
deviation "--vault-password-file instead of --ask-vault-pass, here and for the playbook run below - same secret either way, just not typed at a prompt"

# The corrected, documented remedy from issue #106: without --nopasswd, --ask-become-pass
# only works once the target account actually has a login password. Set one for real,
# rather than assuming --ask-become-pass would somehow succeed against a locked account -
# that assumption is exactly what shipped broken in v2.0.0/v2.0.1's README text.
BECOME_PW="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
step "passwd ${ANSIBLE_USER} (the corrected remedy for --ask-become-pass, issue #106)" \
  bash -c "${SSH} \"echo '${ANSIBLE_USER}:${BECOME_PW}' | chpasswd\""

step "ansible-playbook playbooks/site.yml -i inventory/myhospital --ask-vault-pass --ask-become-pass" \
  env ANSIBLE_HOST_KEY_CHECKING=False \
  ansible-playbook playbooks/site.yml -i inventory/myhospital \
    --vault-password-file "${VAULT_PW}" \
    --extra-vars "ansible_become_pass=${BECOME_PW}"
deviation "--vault-password-file + ansible_become_pass instead of the two --ask-*-prompts - exercises the same connect/sudo codepath either way"

SECOND_RUN_LOG="${WORK_DIR}/site-second-run.log"
step "second run is idempotent (changed=0, nothing unreachable or failed)" \
  bash -c "env ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/site.yml -i inventory/myhospital \
    --vault-password-file '${VAULT_PW}' --extra-vars \"ansible_become_pass=${BECOME_PW}\" \
    | tee '${SECOND_RUN_LOG}'; \
    grep -qE 'changed=0' '${SECOND_RUN_LOG}' && ! grep -qE 'unreachable=[1-9]|failed=[1-9]' '${SECOND_RUN_LOG}'"
# changed=0 alone is not enough: a run that fails to even connect also reports changed=0
# in its PLAY RECAP (nothing ran, so nothing changed) and would otherwise pass this check
# while being completely broken - caught on this script's own first real run, where a
# separate SSH auth gap (see the ansible_ssh_private_key_file note above) produced exactly
# that false PASS before this line was added.

# From here on, ${SSH} (root@...) no longer works - the common role's own hardening sets
# PermitRootLogin no by default (ansible/roles/common/templates/sshd_hardening.conf.j2),
# confirmed rather than assumed after this check first failed with exactly that "root:
# Permission denied (publickey)" on this script's own first full run. Checks after this
# point connect as the bootstrapped user instead. docker_users defaults to an empty list
# (ansible/roles/docker/defaults/main.yml) - the quick start never adds vmtest to the
# docker group either, so this needs sudo, piped the password `passwd` set above.
SSH_VMTEST="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY} ${ANSIBLE_USER}@${VM_IP}"
CADDY_CHECK="docker inspect -f '{{.State.Running}}' linumed-base-caddy | grep -qx true && ss -tlnp | grep -q :443"
step "the caddy container is up and listening on 443" \
  bash -c "echo '${BECOME_PW}' | ${SSH_VMTEST} \"sudo -S sh -c '${CADDY_CHECK}'\""
# Not an HTTP status check: this VM has no real domain, so Caddy's automatic TLS has
# nothing to issue a certificate for, and the resulting handshake behaviour is not
# something any existing test in this repo asserts a specific value for either. What is
# verifiable and matches what vm-test.sh already checks elsewhere (container identity,
# not certificate trust) is that the role's own container is running and bound.

exit "${fail_count}"
