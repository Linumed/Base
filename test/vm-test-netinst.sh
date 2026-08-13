#!/usr/bin/env bash
# Release-time test: installs Debian 13 from the real netinst ISO with a deliberately
# minimal preseed (no python3, no sudo - see the negative check below for why that's the
# whole point), then runs scripts/bootstrap.sh, then the same idempotency check
# test/vm-test.sh uses. Verifies issue #13 (bootstrap.sh) and closes the gap issue #14
# was filed for: the genericcloud image test/vm-test.sh uses already has python3/sudo/
# requests via cloud-init, which masked their absence on a real minimal install until
# this script existed (see issue #24 for the bug that gap hid).
#
# NOT part of regular CI - a real Debian installer run takes far longer than booting a
# cloud image (expect 10-20+ minutes just for the install). Run before releases.
#
# Required packages, same as test/vm-test.sh:
#   libvirt-daemon-system virtinst cloud-image-utils qemu-utils ansible ansible-lint
set -euo pipefail

export LIBVIRT_DEFAULT_URI="qemu:///system"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# See test/vm-test.sh for why /var/tmp, not /tmp, on this dev server.
WORK_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/linumed-os-netinst.XXXXXX")"
chmod 711 "${WORK_DIR}"
VM_NAME="linumed-os-netinst-$$"
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso"
SSH_KEY="${WORK_DIR}/id_ed25519"
ANSIBLE_USER="root"
# Random, generated per run, never committed - only exists inside this throwaway VM's
# disk image, wiped at cleanup. The trailing `|| true` matters: `head -c 24` closes the
# pipe as soon as it has enough bytes, so `tr` gets SIGPIPE (exit 141) - with `pipefail`
# active that fails the whole pipeline and `set -e` would kill the script before its
# first line of output (issue #25).
ROOT_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"

# shellcheck source=lib/site-idempotency.sh
source "${REPO_ROOT}/test/lib/site-idempotency.sh"

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

echo "==> Downloading Debian 13 netinst ISO"
curl -fsSL -o "${WORK_DIR}/netinst.iso" "${ISO_URL}"
qemu-img create -f qcow2 "${WORK_DIR}/disk.qcow2" 10G >/dev/null
chmod 644 "${WORK_DIR}/disk.qcow2" "${WORK_DIR}/netinst.iso"

ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "linumed-os-netinst" >/dev/null

# Deliberately minimal - this is the whole point of the test. tasksel deselected
# (including "standard system utilities"), pkgsel/include limited to openssh-server
# only (without it, nothing could reach this host at all to run bootstrap.sh). No
# python3, no sudo - if either shows up anyway, the negative check below catches it and
# the run fails loudly rather than silently testing nothing.
#
# passwd/make-user false + a root password: the installer's own "create a normal user"
# step would install sudo as a side effect, defeating the point. late_command drops the
# SSH key into place - root login with a key works out of the box on Debian
# (PermitRootLogin defaults to prohibit-password, which allows key auth).
#
# The key file (--initrd-inject below) lands at the root of the *installer's* live
# environment (/id_ed25519.pub), not inside the target system - late_command has to
# copy it into /target (the new system's root, by d-i convention) before "in-target"
# (which chroots into /target) can use it.
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

echo "==> Starting netinst install (this takes a while - real Debian installer, not a cloud image)"
# --initrd-inject puts the preseed (and our pubkey, for late_command above) straight into
# the installer's initrd - no HTTP server, no extra port, no firewall question.
virt-install \
  --name "${VM_NAME}" \
  --memory 2048 \
  --vcpus 2 \
  --disk "path=${WORK_DIR}/disk.qcow2,format=qcow2" \
  --location "${WORK_DIR}/netinst.iso" \
  --initrd-inject "${WORK_DIR}/preseed.cfg" \
  --initrd-inject "${SSH_KEY}.pub" \
  --extra-args "auto=true priority=critical file=/preseed.cfg console=ttyS0,115200n8" \
  --os-variant debian12 \
  --network network=default \
  --graphics none \
  --noautoconsole \
  --wait -1

echo "==> Install finished, waiting for the post-install reboot and SSH"
VM_IP=""
for _ in $(seq 1 90); do
  # tail -n1: the installer and the installed system use different DHCP client-IDs for
  # the same MAC, so dnsmasq hands out two separate leases and domifaddr lists both,
  # oldest first. Picking the first (head -n1) targets the installer's now-dead lease -
  # the host's own ARP table shows it FAILED - which is why every later probe against it
  # timed out or got "No route to host" even though the guest was reachable the whole
  # time on its real, current (last-listed) lease. See #14/#25.
  VM_IP="$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | tail -n1 || true)"
  [ -n "${VM_IP}" ] && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 -i "${SSH_KEY}" root@"${VM_IP}" true 2>/dev/null && break
  sleep 5
done
[ -n "${VM_IP}" ] || { echo "VM never came up after install" >&2; exit 1; }
echo "VM reachable at ${VM_IP}"

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY} root@${VM_IP}"

# This is the test that matters: if the preseed accidentally pulled in python3/sudo (or
# they're on the ISO by default some other way), the whole point of this script is moot
# and it must fail loudly instead of silently passing.
echo "==> Verifying the install is actually minimal (no python3, no sudo)"
if ${SSH} 'command -v python3 || command -v sudo' >/dev/null 2>&1; then
  echo "FAIL: python3 or sudo is already present - this preseed is not minimal, the test proves nothing" >&2
  exit 1
fi
echo "Confirmed: neither python3 nor sudo is present."

# Re-resolve VM_IP with the same tail -n1 logic as above, in case the lease list grew a
# third entry between the checks - cheap insurance, not a retry loop, since the actual
# root cause (picking the dead installer lease) is fixed above.
VM_IP="$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | tail -n1 || true)"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY} root@${VM_IP}"
echo "==> Uploading and running bootstrap.sh"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}" \
  "${REPO_ROOT}/scripts/bootstrap.sh" root@"${VM_IP}":/root/bootstrap.sh
${SSH} "chmod +x /root/bootstrap.sh && /root/bootstrap.sh --user vmtest --key \"$(cat "${SSH_KEY}.pub")\" --nopasswd"
echo "Bootstrapped at ${VM_IP}"

echo "==> Re-keying as the bootstrapped user"
ANSIBLE_USER="vmtest"

run_site_idempotency_check
