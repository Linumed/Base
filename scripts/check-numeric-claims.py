#!/usr/bin/env python3
"""A number in prose is correct when someone measures it. Nobody re-measures it (#88).

Five real cases this week: ADR 0008's role-variable count (125, measured wrong and then
aged from 129 to 146 without anyone re-checking), the "30 undocumented variables" figure
from the #71 audit (was 19), the README's requirements table (silently excluded Orthanc
once that role landed), "all six roles" in two places (became seven), and
`node-baseline.yml`'s "three Compose stacks" (became four). For code, this repository
has five gates by now. For a number written in prose, there was none - this is the sixth.

Deliberately NOT "find every number and demand it be current". Two things in the exact
same file, ARCHITECTURE.md/docs/ROADMAP.md, show why that would be wrong:

    "Measured on 2026-08-20: all eleven pinned images ..."   <- a dated measurement record,
                                                                  correct forever as written
    "138 interface role variables"                            <- a present-tense claim,
                                                                  wrong the moment it drifts

A checker that flags the first as stale would be flagging correct text, and a gate that
cries wolf gets ignored (the exact failure mode `scripts/scan-images.py` was built to
avoid - see its own docstring). So this only re-verifies numbers that are deliberately
listed in NUMERIC_CLAIMS below, the same shape as `ansible/internal-variables.txt` and
`security/accepted-image-findings.txt`: a register, not a scan. Adding a new checked claim
is a deliberate edit to this file, not something a regex decides on its own.

What is deliberately NOT in the register, and why, matters as much as what is:

  - "nine variables a plain run aborts without" (ADR 0008) - this is not a syntactic
    count. It means "unconditionally asserted, not just present with a default", and
    telling those apart needs reading every preflight's `when:`, which is exactly the
    judgment call the #73 remeasurement made by hand. A wrong mechanical approximation
    here would be worse than no check at all.
  - "24 pages" (docs/ROADMAP.md) - explicitly dated ("Verified with mkdocs build: 24
    pages, clean"), a record of what was true on 2026-08-14, not a claim about today.
  - Anything in CHANGELOG.md - every entry is a historical record of what was true when
    it shipped, by definition never re-verified.

Usage:
    scripts/check-numeric-claims.py            # check, print findings, exit non-zero
    scripts/check-numeric-claims.py --report   # check and print, always exit 0
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import importlib

_cvd = importlib.import_module("check-variable-docs")


def role_variables_total() -> int:
    return sum(len(names) for names in _cvd.collect_variables().values())


def role_variables_internal() -> int:
    internal, _ = _cvd.read_internal()
    return len(internal)


def role_variables_interface() -> int:
    return role_variables_total() - role_variables_internal()


def container_names() -> int:
    names = set()
    for path in REPO_ROOT.glob("ansible/roles/*/templates/*.j2"):
        for match in re.finditer(r"container_name:\s*(\S+)", path.read_text(encoding="utf-8")):
            value = match.group(1)
            if "{{" not in value:  # a templated name isn't a fixed identifier to count
                names.add(value)
    return len(names)


def alert_rule_names() -> int:
    path = REPO_ROOT / "ansible/roles/monitoring/templates/alert-rules.yml.j2"
    return len(re.findall(r"^\s*- alert:\s", path.read_text(encoding="utf-8"), re.M))


def systemd_units() -> int:
    return len(list(REPO_ROOT.glob("ansible/roles/*/templates/*.service.j2"))) + len(
        list(REPO_ROOT.glob("ansible/roles/*/templates/*.timer.j2"))
    )


def shared_docker_networks() -> int:
    # The two networks this kit creates and shares across roles are named by four
    # variables that must already agree (checked by check-variable-docs.py's
    # COUPLED_LITERALS) - counting *distinct values* rather than variables is what makes
    # this "two networks", not "four variables".
    names = set()
    for role, var in [
        ("caddy", "caddy_external_network_name"),
        ("monitoring", "monitoring_metrics_network_name"),
        ("bridgelink", "bridgelink_exporter_metrics_network"),
    ]:
        value = _cvd.literal_of(role, var)
        if value:
            names.add(value)
    return len(names)


def docker_volume_names() -> int:
    volumes: set[str] = set()
    for path in glob.glob(str(REPO_ROOT / "ansible/roles/*/templates/docker-compose.yml.j2")):
        text = Path(path).read_text(encoding="utf-8")
        match = re.search(r"^volumes:\n((?:\s+\S.*\n|\s*\n)*)", text, re.M)
        if not match:
            continue
        for line in match.group(1).splitlines():
            named = re.match(r"\s{2}([a-z0-9_-]+):", line)
            if named:
                volumes.add(named.group(1))
    return len(volumes)


# Each entry: (file, derivation function, anchor with {n} where the number belongs).
# The anchor is matched against the file's content with runs of whitespace collapsed to
# one space, so a line-wrapped sentence still matches - a bare "{n}" would be too easy to
# match by coincidence, so every anchor carries enough surrounding text to be a real
# claim, not a stray digit.
NUMERIC_CLAIMS: list[tuple[str, "callable[[], int]", str]] = [
    ("ARCHITECTURE.md", role_variables_interface, "{n} interface role variables"),
    ("ARCHITECTURE.md", container_names, "{n} container names"),
    ("ARCHITECTURE.md", alert_rule_names, "{n} alert rule names"),
    ("docs/ROADMAP.md", role_variables_interface, "{n} interface role variables"),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        role_variables_interface,
        "**{n}** interface + 4 internal, six roles",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        role_variables_internal,
        "**120** interface + {n} internal, six roles",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        container_names,
        "Container names (`linumed-base-*`) | **{n}**",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        shared_docker_networks,
        "Shared Docker networks | {n}",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        alert_rule_names,
        "Alert rule names | **{n}**",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        systemd_units,
        "systemd units | {n} (`backup`, `restore-test`",
    ),
    (
        "docs/adr/0008-what-the-v1-0-stability-guarantee-covers.md",
        docker_volume_names,
        "Docker volume names | **{n}**",
    ),
]


def collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--report", action="store_true", help="always exit 0")
    args = parser.parse_args()

    exit_code = 0
    checked = 0
    for rel_path, derive, anchor_template in NUMERIC_CLAIMS:
        path = REPO_ROOT / rel_path
        if not path.exists():
            print(f"  {rel_path} does not exist, but is listed in NUMERIC_CLAIMS")
            exit_code = 1
            continue
        content = collapse(path.read_text(encoding="utf-8"))
        try:
            actual = derive()
        except Exception as exc:  # noqa: BLE001 - report, don't crash a CI job on this
            print(f"  {rel_path}: could not compute the current value ({exc})")
            exit_code = 1
            continue
        expected_text = anchor_template.format(n=actual)
        checked += 1
        if expected_text not in content:
            print(f"  {rel_path}: expected \"{expected_text}\" (measured: {actual}), not found")
            exit_code = 1

    print(f"{checked} numeric claims checked across {len({c[0] for c in NUMERIC_CLAIMS})} files.")
    if exit_code == 0:
        print("Every registered claim matches what the repository currently measures.")
    else:
        print()
        print("A claim here is either out of date, or NUMERIC_CLAIMS needs updating -")
        print("this file is scripts/check-numeric-claims.py, edited deliberately, not")
        print("auto-generated. See its docstring for what does and does not belong here.")

    return 0 if args.report else exit_code


if __name__ == "__main__":
    sys.exit(main())
