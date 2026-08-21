#!/usr/bin/env python3
"""Every role variable is either documented or recorded as internal - never neither (#72).

Why this exists: from v1.0 a variable name is a promise (ADR 0008). A variable that is
frozen by that promise while being documented nowhere is the worst of both - an operator
cannot find it, and this project cannot change it. ADR 0010 draws the line between
variables that are part of the interface and variables that are implementation detail, and
this script is what keeps that line from rotting the next time a role is added.

The check is deliberately on the *documentation*, not on the runtime. Ansible does have a
mechanism that would make an internal variable genuinely unsettable - `vars/main.yml`
outranks inventory group_vars - but it enforces by discarding an operator's input in
silence, which is the exact failure mode this repository has paid for three times (#44,
#63, #78). ADR 0010 has the full reasoning. A CI check can be loud; a precedence trick
cannot.

Three things are verified:

  1. Every variable in a role's defaults/main.yml is either findable in that role's
     documentation or listed in INTERNAL_FILE. Neither is a failure; both is a failure too,
     because it means the line was drawn in two places that can disagree.
  2. Every name in INTERNAL_FILE still exists in some defaults/main.yml, and carries a
     reason. A list that keeps names of variables that were renamed away is worse than no
     list.
  3. The literals that must agree across roles actually agree. There are no cross-role
     variable reads in this kit - every coupling is a value duplicated into a second
     variable with a comment saying "must match". A comment is not a gate; this is. That
     includes the Prometheus scrape targets, which name another role's container and the
     port inside it (issue #80), and the pin table in docs/operations/updates.md, which is
     what documents the image variable names at all (issue #81).

Usage:
    scripts/check-variable-docs.py            # check, print findings, exit non-zero
    scripts/check-variable-docs.py --report   # check and print, always exit 0
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ROLE_DEFAULTS = sorted(REPO_ROOT.glob("ansible/roles/*/defaults/main.yml"))
INTERNAL_FILE = REPO_ROOT / "ansible" / "internal-variables.txt"
PIN_TABLE = REPO_ROOT / "docs" / "operations" / "updates.md"
DOC_DIRS = [REPO_ROOT / "docs" / "roles", REPO_ROOT / "docs" / "operations"]

# A variable definition at the start of a line. Names may contain digits - missing that is
# what made the #71 audit undercount by seven (`common_fail2ban_*`).
VAR_DEF = re.compile(r"^([a-z][a-z0-9_]*):", re.M)

# Any name-shaped token in a documentation page, whether inside a table cell, prose, or a
# `{{ ... }}` path. Leading underscore allowed so the "/ `_suffix`" shorthand is captured.
DOC_TOKEN = re.compile(r"[a-z][a-z0-9_]*|_[a-z][a-z0-9_]*")

# Literals that must be equal across roles, with the reason each pair exists. Keys are
# `role:variable`; every group must resolve to one distinct value.
COUPLED_LITERALS = [
    (
        "the shared metrics network - three Compose projects agree on one fixed literal "
        "name (issues #39, #64); a mismatch means Prometheus cannot reach the exporter",
        [
            "monitoring:monitoring_metrics_network_name",
            "bridgelink:bridgelink_exporter_metrics_network",
            "orthanc:orthanc_metrics_network",
        ],
    ),
    (
        "the node_exporter textfile directory - backup drops its .prom file where "
        "monitoring's node_exporter reads, without either role depending on the other",
        [
            "monitoring:monitoring_node_exporter_textfile_dir",
            "backup:backup_textfile_dir",
        ],
    ),
]


# Prometheus scrape targets name another role's container and the port *inside* it. Both
# ends are literals with no shared source, so nothing but equality holds them together -
# and the symptom of a mismatch is a target that reads as down, indistinguishable from a
# service that was never deployed. Issue #80 was exactly that, in the Orthanc job.
SCRAPE_TARGETS = [
    ("monitoring_orthanc_target", "orthanc"),
    ("monitoring_bridgelink_exporter_target", "bridgelink"),
]


def role_name(defaults_path: Path) -> str:
    return defaults_path.parent.parent.name


def collect_variables() -> dict[str, list[str]]:
    """Return {role: [variable, ...]} for every role's defaults/main.yml."""
    found: dict[str, list[str]] = {}
    for path in ROLE_DEFAULTS:
        text = path.read_text(encoding="utf-8")
        found[role_name(path)] = [m.group(1) for m in VAR_DEF.finditer(text)]
    return found


def doc_pages() -> list[Path]:
    """Every published documentation page.

    "Documented" means the operator-facing reference - `docs/roles/` and
    `docs/operations/` - and deliberately not "the page belonging to this role", nor the
    whole site.

    Not per-role, for two reasons taken from the actual pages: `common` is split across
    five pages (SSH, ufw, fail2ban, unattended-upgrades, NTP), so a one-file-per-role
    mapping is already wrong; and a variable is documented where an operator *sets* it, not
    where it is defined - `monitoring_scrape_orthanc` and the two `monitoring_orthanc_*`
    credentials live in docs/roles/orthanc.md next to the feature that needs them, and the
    image pins live once in docs/operations/updates.md rather than repeated in every role
    table.

    Not the whole site either, which the first version of this check got wrong: ADR 0010
    necessarily names every internal variable in order to explain it, and `docs/changelog.md`
    names whatever changed. Counting those would have made every internal variable look
    documented and defeated the check on its first run. An ADR explains a decision; it is
    not where an operator looks a variable up.
    """
    return sorted(path for directory in DOC_DIRS for path in directory.rglob("*.md"))


def documented_names(pages: list[Path]) -> set[str]:
    """Every variable name a set of documentation pages mentions, shorthand resolved.

    The pages use two space-saving forms that a plain search for the full name misses -
    and missing them is not hypothetical, it is what produced the wrong "30 undocumented
    variables" figure in #71:

        `backup_retention_keep_daily/weekly/monthly`      -> three names
        `monitoring_alertmanager_group_wait` / `_group_interval`  -> two names

    The second form is resolved by trying every prefix of the preceding full name, because
    the shared part is not always all-but-the-last segment. That can in principle invent a
    name that exists but was not really documented; the alternative is the undercount this
    check exists to prevent, and a wrongly-counted-as-documented variable still has to
    survive review of the page it supposedly appears on.
    """
    names: set[str] = set()
    for page in pages:
        text = page.read_text(encoding="utf-8")
        previous_full: str | None = None
        for match in DOC_TOKEN.finditer(text):
            token = match.group(0)
            if token.startswith("_"):
                if previous_full:
                    parts = previous_full.split("_")
                    for cut in range(1, len(parts)):
                        names.add("_".join(parts[:cut]) + token)
                continue
            names.add(token)
            previous_full = token
            # The `a/b/c` form: look at what directly follows and splice the tail onto the
            # name's own prefix.
            tail = text[match.end():]
            while tail.startswith("/"):
                nxt = re.match(r"/([a-z][a-z0-9_]*)", tail)
                if not nxt:
                    break
                parts = previous_full.split("_")
                names.add("_".join(parts[:-1] + [nxt.group(1)]))
                tail = tail[nxt.end():]
    return names


def read_internal() -> tuple[dict[str, str], list[str]]:
    """Return ({variable: reason}, problems) from INTERNAL_FILE."""
    entries: dict[str, str] = {}
    problems: list[str] = []
    if not INTERNAL_FILE.exists():
        return entries, [f"{INTERNAL_FILE.relative_to(REPO_ROOT)} does not exist"]
    for lineno, raw in enumerate(INTERNAL_FILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name, sep, reason = line.partition("#")
        name = name.strip()
        reason = reason.strip()
        if not sep or not reason:
            problems.append(f"{INTERNAL_FILE.name}:{lineno}: '{name}' has no reason")
        entries[name] = reason
    return entries, problems


def literal_of(role: str, variable: str) -> str | None:
    """The literal value a role's defaults assign to a variable, quotes stripped."""
    path = REPO_ROOT / "ansible" / "roles" / role / "defaults" / "main.yml"
    if not path.exists():
        return None
    match = re.search(rf"^{re.escape(variable)}: *(.+)$", path.read_text(encoding="utf-8"), re.M)
    if not match:
        return None
    return match.group(1).strip().strip('"').strip("'")


def check_coupled_literals() -> list[str]:
    problems = []
    for reason, keys in COUPLED_LITERALS:
        values = {}
        for key in keys:
            role, _, variable = key.partition(":")
            value = literal_of(role, variable)
            if value is None:
                problems.append(f"{key} is referenced as a coupled literal but does not exist")
            else:
                values[key] = value
        if len(set(values.values())) > 1:
            problems.append(
                "these must hold the same value ("
                + reason
                + "):\n"
                + "\n".join(f"    {k} = {v}" for k, v in values.items())
            )
    return problems


# `| role | `variable` | `image:tag` |` rows in the pin table.
PIN_ROW = re.compile(r"^\| *([a-z]+) *\| *`([a-z][a-z0-9_]*_image)` *\| *`([^`]+)` *\|", re.M)
IMAGE_DEF = re.compile(r'^([a-z][a-z0-9_]*_image): *"([^"]+)"', re.M)


def check_pin_table() -> list[str]:
    """The pin table in updates.md must list every pinned image, with the current tag.

    Until 2026-08-21 the table carried a note saying it "will drift" - and it had, in both
    directions: two tags were behind the roles and three images were missing entirely
    (issue #81). An accepted drift was defensible while the table was only a convenience.
    It stopped being defensible when ADR 0010 made this table the documentation that keeps
    those 13 variable names inside the v1.0 promise: a name is documented by a row that
    also claims a version, and a wrong version makes the row untrustworthy as a whole.

    Only the tag is checked, not whether it is the newest one upstream - that is
    scripts/scan-images.py's job and needs a scanner and a network.
    """
    problems = []
    if not PIN_TABLE.exists():
        return [f"{PIN_TABLE.relative_to(REPO_ROOT)} does not exist"]
    listed = {m.group(2): (m.group(1), m.group(3)) for m in PIN_ROW.finditer(PIN_TABLE.read_text(encoding="utf-8"))}
    defined: dict[str, tuple[str, str]] = {}
    for path in ROLE_DEFAULTS:
        for match in IMAGE_DEF.finditer(path.read_text(encoding="utf-8")):
            defined[match.group(1)] = (role_name(path), match.group(2))

    for variable, (role, image) in sorted(defined.items()):
        if variable not in listed:
            problems.append(f"{variable} ({image}) is pinned in the {role} role but missing from the pin table")
            continue
        listed_role, listed_image = listed[variable]
        if listed_image != image:
            problems.append(f"{variable}: the pin table says {listed_image}, the {role} role pins {image}")
        elif listed_role != role:
            problems.append(f"{variable}: the pin table attributes it to {listed_role}, it belongs to {role}")
    for variable in sorted(set(listed) - set(defined)):
        problems.append(f"the pin table lists {variable}, which no role defines")
    return problems


def container_port(role: str, container: str) -> tuple[str | None, str]:
    """The container-side port a role's Compose template publishes for one container.

    Returns (port, explanation-if-none). The container-side port is the last field of a
    `- "127.0.0.1:<host>:<container>"` mapping - the host side may be a variable, the
    container side must not be, which is the whole point of #80.
    """
    path = REPO_ROOT / "ansible" / "roles" / role / "templates" / "docker-compose.yml.j2"
    if not path.exists():
        return None, f"{path.relative_to(REPO_ROOT)} does not exist"
    text = path.read_text(encoding="utf-8")
    blocks = re.split(r"^\s*container_name: *", text, flags=re.M)[1:]
    for block in blocks:
        name = block.splitlines()[0].strip()
        if name != container:
            continue
        mapping = re.search(r'^\s*- *"[^"]*:(\d+)" *$', block, re.M)
        if not mapping:
            return None, f"{role}'s {container} publishes no port with a literal container side"
        return mapping.group(1), ""
    return None, f"{role}'s Compose template defines no container named {container}"


def check_scrape_targets() -> list[str]:
    problems = []
    for variable, role in SCRAPE_TARGETS:
        target = literal_of("monitoring", variable)
        if target is None:
            problems.append(f"{variable} is not defined in the monitoring role")
            continue
        container, _, port = target.rpartition(":")
        actual, why = container_port(role, container)
        if actual is None:
            problems.append(f"{variable} = {target}: {why}")
        elif actual != port:
            problems.append(
                f"{variable} scrapes {container}:{port}, but that container listens on "
                f"{actual} - Prometheus would report a target that is down, not a wrong port"
            )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--report", action="store_true", help="always exit 0")
    args = parser.parse_args()

    variables = collect_variables()
    internal, problems = read_internal()
    all_variables = {v for names in variables.values() for v in names}

    documented = documented_names(doc_pages())
    undocumented: list[tuple[str, str]] = []
    both: list[tuple[str, str]] = []
    for role, names in sorted(variables.items()):
        for name in names:
            is_doc = name in documented
            is_int = name in internal
            if not is_doc and not is_int:
                undocumented.append((role, name))
            elif is_doc and is_int:
                both.append((role, name))

    orphaned = sorted(name for name in internal if name not in all_variables)
    coupling = check_coupled_literals() + check_scrape_targets()
    pins = check_pin_table()

    total = sum(len(v) for v in variables.values())
    print(f"{total} variables across {len(variables)} roles; {len(internal)} recorded internal.")
    print()

    exit_code = 0

    if undocumented:
        print("Neither documented nor recorded as internal - a variable v1.0 would freeze")
        print("while nobody can look it up:")
        for role, name in undocumented:
            print(f"  {role:<12} {name}")
        print(f"\nDocument it in docs/roles/, or add it to {INTERNAL_FILE.relative_to(REPO_ROOT)}")
        print("with the reason it is implementation detail. See ADR 0010.\n")
        exit_code = 1

    if both:
        print("Recorded internal *and* documented - the line is drawn in two places that")
        print("can disagree. Pick one:")
        for role, name in both:
            print(f"  {role:<12} {name}")
        print()
        exit_code = 1

    if orphaned:
        print(f"Listed in {INTERNAL_FILE.name} but no longer defined in any role - the list")
        print("has outlived the variable and needs the same edit the rename did:")
        for name in orphaned:
            print(f"  {name}")
        print()
        exit_code = 1

    for problem in problems:
        print(f"  {problem}")
        exit_code = 1
    if problems:
        print()

    if coupling:
        print("Coupled literals disagree. There are no cross-role variable reads in this")
        print("kit, so these are held together by nothing but the values themselves:")
        for problem in coupling:
            print(f"  {problem}")
        print()
        exit_code = 1

    if pins:
        print("The pin table in docs/operations/updates.md disagrees with the roles. It is")
        print("what documents the image variable names for ADR 0010, so a wrong row is not")
        print("cosmetic - it is the documentation being wrong about what it documents:")
        for problem in pins:
            print(f"  {problem}")
        print()
        exit_code = 1

    if exit_code == 0:
        print("Every variable is either documented or recorded as internal, the internal")
        print("list matches what the roles define, and the coupled literals agree.")

    return 0 if args.report else exit_code


if __name__ == "__main__":
    sys.exit(main())
