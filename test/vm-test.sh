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
# /var/tmp, not /tmp - on this dev server /tmp is a tmpfs (RAM-backed), and a Debian
# genericcloud qcow2 plus the disk this VM grows into during a full-stack deploy is easily
# several GB. A tmpfs work dir competes with the VM's own guest RAM for the same physical
# memory and can fill the host's /tmp entirely (confirmed 2026-08-11: it paused a running
# VM and briefly left the host without a working /tmp). /var/tmp is disk-backed on a
# standard Debian install; if that assumption doesn't hold on some other host, override
# TMPDIR before running this script.
WORK_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/linumed-base-vmtest.XXXXXX")"
# The libvirt-qemu user (not root/the invoking user) needs to reach the disk images.
chmod 711 "${WORK_DIR}"
VM_NAME="linumed-base-vmtest-$$"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${WORK_DIR}/id_ed25519"
ANSIBLE_USER="vmtest"

# shellcheck source=lib/site-idempotency.sh
source "${REPO_ROOT}/test/lib/site-idempotency.sh"
# shellcheck source=lib/docker-reference-smoke.sh
source "${REPO_ROOT}/test/lib/docker-reference-smoke.sh"
# shellcheck source=lib/bridgelink-exporter-check.sh
source "${REPO_ROOT}/test/lib/bridgelink-exporter-check.sh"

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

ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "linumed-base-vmtest" >/dev/null

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
  --memory 6144 \
  --vcpus 3 \
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
  # tail -n1: a stale + fresh DHCP lease for the same MAC can make domifaddr print two
  # ipv4 lines - the installer/boot client and the installed system's dhcp client use
  # different DHCP client-IDs for the same MAC, so dnsmasq hands out two leases and
  # domifaddr lists them oldest-first. head -n1 picked the dead, already-expired one and
  # made every retry probe an address the host had already marked FAILED in ARP - the
  # real, current lease is always the last line (confirmed against actual `ip neigh` /
  # `virsh net-dhcp-leases` output while debugging issue #14/#25).
  VM_IP="$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | tail -n1 || true)"
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

run_site_idempotency_check

# Runs after site.yml, not instead of it: it needs the Docker the docker role installs,
# and it deliberately reuses this already-provisioned throwaway VM rather than exposing a
# Docker socket to the CI job container (issue #46).
run_docker_reference_smoke_check

# Last, and after the idempotency check rather than folded into it: this one deliberately
# changes the deployed state (it switches the exporter on), so anything asserting on a
# default-configuration host has to have run already. Covers the enable path from #60,
# which nothing had ever executed through Ansible (issue #62).
run_bridgelink_exporter_check
