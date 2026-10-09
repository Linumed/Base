#!/usr/bin/env bash
# Shared by test/vm-test-netinst.sh and test/vm-test-quickstart.sh: fetch the current Debian
# 13 netinst ISO and verify it, or stop the test.
#
# Why the file name is looked up rather than written down (issue #127): both scripts used to
# pin `.../debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso`. `current/` only
# ever holds the newest point release, so that URL was bound to 404 with the next one - and
# did, on 2026-10-09 with Debian 13.7.0, right before a release. The point release is not
# what these tests are about (they test a minimal netinst install, issue #14), so the name
# comes from Debian's own SHA512SUMS next to it.
#
# Why the checksum is checked: it was never verified before. A truncated or swapped image
# would have failed somewhere inside the installer, far from its cause.
#
# Why it exits instead of returning: vm-test-quickstart.sh runs without `set -e` on purpose
# (each quick-start block reports PASS/FAIL on its own), and after the 404 it went on to
# start an installer with no ISO and hung. Without install media there is nothing to report.
#
# Not meant to be executed directly. Usage: fetch_netinst_iso <destination file>

NETINST_ISO_DIR="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"

fetch_netinst_iso() {
  local dest="$1" sums name expected actual
  sums="$(curl -fsSL "${NETINST_ISO_DIR}/SHA512SUMS")" || {
    echo "FAIL: could not fetch ${NETINST_ISO_DIR}/SHA512SUMS" >&2; exit 1; }
  # Exactly the plain amd64 netinst image - not debian-edu-* or debian-mac-*, which sit in
  # the same list.
  name="$(awk '$2 ~ /^debian-13\.[0-9]+\.[0-9]+-amd64-netinst\.iso$/ {print $2}' <<<"${sums}")"
  if [ "$(grep -c . <<<"${name}")" != "1" ]; then
    echo "FAIL: expected exactly one debian-13.*-amd64-netinst.iso in SHA512SUMS, found: ${name:-none}" >&2
    exit 1
  fi
  expected="$(awk -v n="${name}" '$2 == n {print $1}' <<<"${sums}")"
  echo "==> Downloading ${name}"
  curl -fsSL -o "${dest}" "${NETINST_ISO_DIR}/${name}" || {
    echo "FAIL: download of ${name} failed" >&2; exit 1; }
  actual="$(sha512sum "${dest}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "FAIL: ${name} does not match its SHA512SUMS entry" >&2
    exit 1
  fi
  echo "==> ${name} verified against SHA512SUMS"
}
