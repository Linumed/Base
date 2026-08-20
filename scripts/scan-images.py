#!/usr/bin/env python3
"""Scans every pinned container image for known vulnerabilities (issue #67).

Why this exists: `SECURITY.md` lists "pinned container image versions with known
vulnerabilities that have a fixed version available" as in scope for a security report -
and until this script, nothing in the repository ever checked. Measured on 2026-08-20, all
eleven pinned images carried fixable HIGH/CRITICAL findings.

The design problem, and the reason this is not a plain `trivy && exit $?`:

A finding is only actionable here if a newer upstream tag exists that could clear it. Some
images are simply behind - Alertmanager and Grafana both had newer tags on 2026-08-20, and
bumping the pin is real, due maintenance. Others are already on the newest tag and still
carry findings from their upstream base image, which no change in this repository can fix;
`caddy:2.11.4-alpine` was in that state with 19 findings.

A gate that goes red on any finding would therefore be permanently red - and a check that
always says the same thing stops being read. This repository has hit that failure mode
three times already (#40, #48, #63), and it is worth more care than a one-line exit code.

So the verdict is:

  behind + fixable findings  -> failure. The pin is out of date and it matters.
  newest + findings          -> reported, and must be listed in ACCEPTED_FILE with a
                                reason. Unlisted ones fail, so nothing rots silently.
  no findings                -> pass.

Also checks that the hand-maintained references under `docker/` pin the same versions as
the roles - `CONVENTIONS.md` requires it and nothing enforced it before.

Usage:
    scripts/scan-images.py            # scan, print a table, exit non-zero on a verdict
    scripts/scan-images.py --report   # scan and print, always exit 0

Needs `trivy` on PATH, or Docker (the script falls back to running trivy in a container).
In CI the binary is used - the runner deliberately has no broad Docker socket access, see
ADR 0004, and trivy can scan images straight from the registry without a daemon.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ROLE_DEFAULTS = sorted(REPO_ROOT.glob("ansible/roles/*/defaults/main.yml"))
DOCKER_REFS = sorted(REPO_ROOT.glob("docker/*/docker-compose.yml"))
ACCEPTED_FILE = REPO_ROOT / "security" / "accepted-image-findings.txt"

# Pinned to keep results comparable between runs; an unpinned scanner would change its
# verdict without anything in this repository changing.
TRIVY_VERSION = "0.74.0"
TRIVY_IMAGE = f"aquasec/trivy:{TRIVY_VERSION}"
TRIVY_CACHE = "/var/tmp/trivy-cache"

# Images are found by the `*_image:` naming convention in role defaults rather than from a
# separate list, so a new role cannot be forgotten here. Verified 2026-08-20: all eleven
# pinned images follow it, and nothing else in defaults/ looks like an image reference.
IMAGE_VAR = re.compile(r'^([a-z_]+_image): *"([^"]+)"', re.M)
COMPOSE_IMAGE = re.compile(r"^\s*image: *([^\s#]+)", re.M)


def collect_pinned_images() -> dict[str, str]:
    """Return {image_reference: source file} for every image pinned in a role's defaults."""
    images: dict[str, str] = {}
    for path in ROLE_DEFAULTS:
        for match in IMAGE_VAR.finditer(path.read_text(encoding="utf-8")):
            images[match.group(2)] = str(path.relative_to(REPO_ROOT))
    return images


def check_reference_drift(pinned: dict[str, str]) -> list[str]:
    """The docker/ references must pin the same versions the roles do (CONVENTIONS.md).

    ADR 0005 deliberately made those references a testing convenience rather than a
    guaranteed mirror - but the image tag is the one thing it does require to stay in sync,
    and issue #48 is what an unnoticed divergence there costs.
    """
    problems = []
    for path in DOCKER_REFS:
        for match in COMPOSE_IMAGE.finditer(path.read_text(encoding="utf-8")):
            image = match.group(1)
            if image not in pinned:
                problems.append(f"{path.relative_to(REPO_ROOT)} pins {image}, no role does")
    return problems


def split_ref(image: str) -> tuple[str, str]:
    repo, _, tag = image.rpartition(":")
    return repo, tag


def tag_pattern(tag: str) -> re.Pattern[str]:
    """Build a matcher for 'tags shaped like this one'.

    Numeric components become wildcards, everything else stays literal, so
    `2.11.4-alpine` matches `2.12.0-alpine` but not `2.12.0-trixie` or a floating
    `2.12-alpine`. Deliberately conservative: suggesting a tag from a different variant
    would be worse than suggesting none.
    """
    parts = re.split(r"(\d+)", tag)
    return re.compile("^" + "".join(r"\d+" if p.isdigit() else re.escape(p) for p in parts) + "$")


def version_key(tag: str) -> list[int]:
    return [int(n) for n in re.findall(r"\d+", tag)]


def dockerhub_tags(repo: str, needle: str) -> list[str]:
    if "/" not in repo:
        repo = f"library/{repo}"
    url = (
        f"https://hub.docker.com/v2/repositories/{repo}/tags"
        f"?page_size=100&name={urllib.parse.quote(needle)}&ordering=last_updated"
    )
    with urllib.request.urlopen(url, timeout=30) as response:
        return [t["name"] for t in json.load(response).get("results", [])]


def ghcr_tags(repo: str) -> list[str]:
    """GHCR needs an anonymous pull token before the tag list is readable."""
    path = repo.split("/", 1)[1]
    token_url = f"https://ghcr.io/token?scope=repository:{path}:pull&service=ghcr.io"
    with urllib.request.urlopen(token_url, timeout=30) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(
        f"https://ghcr.io/v2/{path}/tags/list?n=200",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response).get("tags", [])


def newer_tag(image: str) -> tuple[str | None, str | None]:
    """(patch_update, series_update) - newest tag of the same shape in each category.

    The distinction decides whether this can be a gate at all. `caddy:2.11.4-alpine` ->
    `2.11.5-alpine` is an unambiguous security bump and failing the build on it is right.
    `python:3.13-alpine` -> `3.14-alpine` is a language version change wearing the same
    shape, and demanding it would be wrong - the first dry run of this script suggested
    exactly that, which is how the distinction got built.

    "Patch" means every numeric component except the last one is identical. Everything else
    is a series update: reported for a human to decide, never enforced.
    """
    repo, tag = split_ref(image)
    try:
        if repo.startswith("ghcr.io/"):
            tags = ghcr_tags(repo)
        else:
            # Filter server-side on the leading number so the first page is likely to
            # contain the relevant tags - these repositories have thousands.
            lead = re.match(r"v?\d+", tag)
            tags = dockerhub_tags(repo, lead.group(0) if lead else "")
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, OSError) as exc:
        print(f"  ! tag lookup failed for {repo}: {exc}", file=sys.stderr)
        return None, None

    pattern = tag_pattern(tag)
    current = version_key(tag)
    candidates = [t for t in tags if pattern.match(t) and version_key(t) > current]
    if not candidates:
        return None, None

    same_series = [t for t in candidates if version_key(t)[:-1] == current[:-1]]
    other = [t for t in candidates if version_key(t)[:-1] != current[:-1]]
    patch = max(same_series, key=version_key) if same_series else None
    series = max(other, key=version_key) if other else None
    return patch, series


def trivy_findings(image: str) -> tuple[int, set[str]]:
    """Count fixable HIGH/CRITICAL findings and return their CVE ids."""
    args = [
        "image", "--quiet", "--severity", "HIGH,CRITICAL",
        "--ignore-unfixed", "--format", "json", image,
    ]
    if shutil.which("trivy"):
        cmd = ["trivy", *args]
    else:
        cmd = [
            "docker", "run", "--rm",
            "-v", f"{TRIVY_CACHE}:/root/.cache/",
            TRIVY_IMAGE, *args,
        ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 and not result.stdout.strip():
        print(f"  ! scan failed for {image}: {result.stderr.strip()[:200]}", file=sys.stderr)
        return -1, set()
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"  ! unparseable scanner output for {image}", file=sys.stderr)
        return -1, set()
    cves = {
        v["VulnerabilityID"]
        for r in (data.get("Results") or [])
        for v in (r.get("Vulnerabilities") or [])
    }
    return len(cves), cves


STALE_AFTER_DAYS = 90


def load_accepted() -> dict[str, str]:
    """Findings knowingly carried, as `image CVE # reason`.

    Same idea as `.gitleaksignore`: not a way to hide something, a way to record that it was
    looked at, by whom and why. An entry without a reason is not accepted.
    """
    accepted: dict[str, str] = {}
    if not ACCEPTED_FILE.exists():
        return accepted
    for line in ACCEPTED_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        entry, _, reason = line.partition("#")
        fields = entry.split()
        if len(fields) >= 2 and reason.strip():
            accepted[f"{fields[0]} {fields[1]}"] = reason.strip()
    return accepted


def stale_entries(accepted: dict[str, str]) -> list[tuple[str, str]]:
    """Recorded findings whose date has passed STALE_AFTER_DAYS.

    Reported, never fatal: an ageing entry is a prompt to look again, not a build failure.
    Making it fatal would push people to refresh the date, which is the one reaction that
    destroys the file's value.
    """
    cutoff = datetime.date.today() - datetime.timedelta(days=STALE_AFTER_DAYS)
    out = []
    for key, reason in accepted.items():
        found = re.search(r"\((\d{4})-(\d{2})-(\d{2})\)", reason)
        if not found:
            continue
        when = datetime.date(*(int(g) for g in found.groups()))
        if when < cutoff:
            out.append((key, when.isoformat()))
    return sorted(out, key=lambda x: x[1])


WORKFLOW = REPO_ROOT / ".forgejo" / "workflows" / "image-scan.yml"


def check_scanner_pin() -> str | None:
    """The workflow and this script must ask for the same trivy.

    Different scanner versions produce different finding sets - measured while building
    this: 0.58.2 and 0.74.0 disagreed on Prometheus (9 vs 8) and on the total (129 vs 128).
    If the two pins drift, a local run and a CI run disagree about whether the accepted list
    is complete, and the disagreement looks like a real finding. Same idea as the ruff pin
    check in the sibling repository.
    """
    if not WORKFLOW.exists():
        return None
    found = re.search(r"TRIVY_VERSION=([0-9.]+)", WORKFLOW.read_text(encoding="utf-8"))
    if not found:
        return f"no TRIVY_VERSION found in {WORKFLOW.name}"
    if found.group(1) != TRIVY_VERSION:
        return (f"{WORKFLOW.name} pins trivy {found.group(1)}, this script pins "
                f"{TRIVY_VERSION} - they must match")
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", action="store_true",
                        help="print findings but always exit 0")
    args = parser.parse_args()

    pinned = collect_pinned_images()
    if not pinned:
        print("No pinned images found - has the *_image: convention changed?", file=sys.stderr)
        return 2

    drift = check_reference_drift(pinned)
    pin_problem = check_scanner_pin()
    accepted = load_accepted()

    print(f"Scanning {len(pinned)} pinned images with trivy {TRIVY_VERSION}\n")
    print(f"{'image':50} {'fixable':>7}  {'patch':16} {'series':16} verdict")
    print("-" * 116)

    behind, unaccepted, series_notes = [], [], []
    for image in sorted(pinned):
        count, cves = trivy_findings(image)
        patch, series = newer_tag(image)
        if series:
            series_notes.append((image, series))

        if count < 0:
            verdict = "SCAN FAILED"
            unaccepted.append(image)
        elif count == 0:
            verdict = "ok"
        elif patch:
            # Verify the candidate actually helps before demanding it. Measured on
            # 2026-08-20: grafana 13.1.3 -> 13.1.4 cleared 5 of 18 findings, while
            # postgres 17.10 -> 17.11 cleared none at all. "Behind" and "fixes something"
            # are not the same thing, and failing a build over a bump that changes nothing
            # is the noise this script exists to avoid.
            repo, _ = split_ref(image)
            cand_count, _ = trivy_findings(f"{repo}:{patch}")
            if 0 <= cand_count < count:
                verdict = f"BEHIND - bump clears {count - cand_count}"
                behind.append((image, patch, count, cand_count))
            else:
                verdict = "newer patch, clears nothing"
                missing = [c for c in cves if f"{image} {c}" not in accepted]
                if missing:
                    unaccepted.append(image)
        else:
            missing = [c for c in cves if f"{image} {c}" not in accepted]
            if missing:
                verdict = f"{len(missing)} not recorded"
                unaccepted.append(image)
            else:
                verdict = "accepted, on newest"
        print(f"{image:50} {count:>7}  {(patch or '-'):16} {(series or '-'):16} {verdict}")

    print()
    exit_code = 0

    if pin_problem:
        print(f"Scanner pin mismatch: {pin_problem}")
        exit_code = 1

    if drift:
        print("Reference drift (docker/ must pin what the roles pin):")
        for problem in drift:
            print(f"  {problem}")
        exit_code = 1

    if behind:
        print("Pins behind a patch release that demonstrably clears findings:")
        for image, newer, count, after in behind:
            print(f"  {image} -> {newer}  ({count} fixable now, {after} after the bump)")
        exit_code = 1

    if series_notes:
        print("Newer series available - a decision, not a security bump, so never enforced:")
        for image, series in series_notes:
            print(f"  {image} -> {series}")
        print()

    if unaccepted:
        print(f"Images with findings that are not recorded in {ACCEPTED_FILE.relative_to(REPO_ROOT)}:")
        for image in unaccepted:
            print(f"  {image}")
        print("\nThese are on the newest available tag, so the findings come from upstream's")
        print("base image and cannot be fixed here. Record each one with a reason and a date,")
        print("or the list stops meaning anything.")
        exit_code = 1

    stale = stale_entries(accepted)
    if stale:
        print(f"Recorded findings older than {STALE_AFTER_DAYS} days - re-check them rather")
        print("than refreshing the date; a stale entry usually means an upstream stopped")
        print("rebuilding, which is exactly what this is supposed to surface:")
        for key, when in stale[:10]:
            print(f"  {key}  (recorded {when})")
        if len(stale) > 10:
            print(f"  ... and {len(stale) - 10} more")
        print()

    if exit_code == 0:
        print("All pinned images are current, and every remaining finding is recorded.")

    return 0 if args.report else exit_code


if __name__ == "__main__":
    sys.exit(main())
