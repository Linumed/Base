#!/usr/bin/env bash
# Shared by test/vm-test.sh: verify the deployed BridgeLink container really has the
# custom-lib volume mounted (issue #98).
#
# Why it needs its own check: the property being protected is that a library copied into
# custom-lib survives a container rebuild. Nothing else in test/ looks at that mount - a
# typo in the Compose template (a wrong destination, a volume declared but not attached)
# would leave every other check green and surface only when an operator's JAR vanished
# after an image update, with no message. That is the failure #98 describes.
#
# What it deliberately does not do: copy a JAR in and load a class from it. The -dhi image
# has no shell, so the only way to write into the volume is a second image (busybox), and
# that would pull an unpinned image into the test - the same reason loki-log-check.sh goes
# through Grafana. The load itself was measured once against the real library, HAPI FHIR
# 7.6.1 (docs/roles/bridgelink.md, "FHIR, precisely"); this check only guards the mount that
# measurement depends on.
#
# Not meant to be executed directly. Expects: VM_IP, SSH_KEY, ANSIBLE_USER, and a stack
# deployed by run_site_idempotency_check.

run_bridgelink_custom_lib_check() {
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")
  local remote="${ANSIBLE_USER}@${VM_IP}"
  local dest="/opt/bridgelink/custom-lib"

  echo "==> Checking that BridgeLink has a volume mounted at ${dest}"
  local mount
  mount="$(ssh "${ssh_opts[@]}" "${remote}" \
    "sudo docker inspect linumed-base-bridgelink --format '{{range .Mounts}}{{.Destination}}={{.Type}}:{{.Name}}{{println}}{{end}}'" \
    | grep -F "${dest}=" || true)"

  # Named volume, project-derived name (ADR 0008 lists volume names as stability surface).
  if [ "${mount}" != "${dest}=volume:bridgelink_bridgelink_custom_lib" ]; then
    echo "FAIL: expected '${dest}=volume:bridgelink_bridgelink_custom_lib', got '${mount:-<no mount>}'" >&2
    exit 1
  fi
  echo "    ${mount}"
}
