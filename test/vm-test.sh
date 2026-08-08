#!/usr/bin/env bash
# Idempotency test for site.yml against a throwaway Debian 13 VM.
#
# Downloads the official Debian 13 genericcloud qcow2 (cloud.debian.org), boots it via
# libvirt/KVM with a cloud-init seed, runs site.yml twice, and fails unless the second run
# reports changed=0. This is deliberately not Vagrant/VirtualBox: VirtualBox is not packaged
# for Debian 13 and there is no official Debian 13 Vagrant box (Debian bug #1110834).
#
# Required packages (Debian main, not installed automatically by this script):
#   libvirt-daemon-system virtinst cloud-image-utils qemu-utils ansible ansible-lint
set -euo pipefail

# Non-root libvirt clients default to qemu:///session, which has no "default" NAT network
# defined (that lives under qemu:///system, alongside libvirtd's system-wide config). Pin
# the connection explicitly so virsh/virt-install use the system instance this repo assumes.
export LIBVIRT_DEFAULT_URI="qemu:///system"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d /tmp/linumed-os-vmtest.XXXXXX)"
# The libvirt-qemu user (not root/the invoking user) needs to reach the disk images.
chmod 711 "${WORK_DIR}"
VM_NAME="linumed-os-vmtest-$$"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${WORK_DIR}/id_ed25519"

cleanup() {
  virsh destroy "${VM_NAME}" >/dev/null 2>&1 || true
  virsh undefine "${VM_NAME}" --nvram >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for tool in virt-install virsh cloud-localds qemu-img ansible-playbook ansible-lint; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "Missing required tool: ${tool}. Install: libvirt-daemon-system virtinst cloud-image-utils qemu-utils ansible ansible-lint" >&2
    exit 1
  }
done

echo "==> ansible-lint"
(cd "${REPO_ROOT}/ansible" && ansible-lint)

echo "==> Downloading Debian 13 genericcloud image"
curl -fsSL -o "${WORK_DIR}/base.qcow2" "${IMAGE_URL}"
qemu-img create -f qcow2 -F qcow2 -b "${WORK_DIR}/base.qcow2" "${WORK_DIR}/disk.qcow2" 10G
chmod 644 "${WORK_DIR}/base.qcow2" "${WORK_DIR}/disk.qcow2"

ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "linumed-os-vmtest" >/dev/null

cat > "${WORK_DIR}/user-data" <<EOF
#cloud-config
hostname: ${VM_NAME}
users:
  - name: vmtest
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")
EOF
: > "${WORK_DIR}/meta-data"
cloud-localds "${WORK_DIR}/seed.img" "${WORK_DIR}/user-data" "${WORK_DIR}/meta-data"
chmod 644 "${WORK_DIR}/seed.img"

echo "==> Starting VM"
# --boot uefi is required: Debian's genericcloud images are GPT/UEFI-only (no BIOS boot
# partition), so plain SeaBIOS just loops re-drawing the GRUB banner without ever booting.
virt-install \
  --name "${VM_NAME}" \
  --memory 1536 \
  --vcpus 2 \
  --disk "path=${WORK_DIR}/disk.qcow2,format=qcow2" \
  --disk "path=${WORK_DIR}/seed.img,device=cdrom" \
  --os-variant debian12 \
  --network network=default \
  --graphics none \
  --noautoconsole \
  --boot uefi \
  --import

echo "==> Waiting for SSH"
VM_IP=""
for _ in $(seq 1 60); do
  VM_IP="$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 || true)"
  [ -n "${VM_IP}" ] && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 -i "${SSH_KEY}" vmtest@"${VM_IP}" true 2>/dev/null && break
  sleep 5
done
[ -n "${VM_IP}" ] || { echo "VM never came up" >&2; exit 1; }
echo "VM reachable at ${VM_IP}"

# Without this, Ansible can start hardening while cloud-init is still busy on first boot -
# on a 1-vCPU VM that starves systemd's D-Bus socket long enough for a `systemctl reload`
# to time out ("Failed to reload ssh.service: Connection timed out").
echo "==> Waiting for cloud-init to finish"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}" \
  vmtest@"${VM_IP}" 'sudo cloud-init status --wait'

INVENTORY="${WORK_DIR}/inventory.yml"
cat > "${INVENTORY}" <<EOF
all:
  children:
    linumed:
      hosts:
        ${VM_NAME}:
          ansible_host: ${VM_IP}
          ansible_user: vmtest
          ansible_ssh_private_key_file: ${SSH_KEY}
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
EOF

cd "${REPO_ROOT}/ansible"

echo "==> First run"
ansible-playbook -i "${INVENTORY}" playbooks/site.yml

echo "==> Second run (must report changed=0)"
OUTPUT="$(ansible-playbook -i "${INVENTORY}" playbooks/site.yml)"
echo "${OUTPUT}"
if echo "${OUTPUT}" | grep -qE 'changed=[1-9]'; then
  echo "FAIL: second run was not idempotent" >&2
  exit 1
fi

echo "==> PASS: site.yml is idempotent"
