#!/usr/bin/env python3
"""Turns a failed CI job into a Forgejo issue, so a red run reaches someone (#117).

Two failures went unnoticed for weeks in September 2026: the weekly image-scan was red
from 2026-09-21 on (#115), and a vm-test run failed on 2026-09-23 (#116). Nothing reported
either one, and by the time someone looked, Forgejo had not archived the vm-test log - the
cause of that failure is unknowable now. An issue fixes both halves: it shows up where
open work is tracked, and it carries the end of the log with it.

One issue per workflow, not per run. If an open issue titled "CI rot: <workflow>" already
exists, the failure is added as a comment - a scan that stays red every Monday should
grow one thread, not a new issue a week. Closing it stays a human decision, with the
reason in the closing comment.

Runs as the last step of every workflow under `if: failure()`. Standard library only:
the step has to work even when the job failed before any of its own installs ran.

Environment: the standard GITHUB_* variables, CI_LOG_FILE (see scripts/ci-log.sh) and
FORGEJO_TOKEN (the job's automatic token, which has write access to its own repository).
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

LOG_TAIL_LINES = 120
# Generous on purpose: trivy reports why a registry fetch failed in one long line, and
# 300 characters cut it off right before the reason (run 348, #115).
LINE_MAX_CHARS = 1000
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\]8;;[^\x1b]*\x1b\\")


def env(name, default=""):
    return os.environ.get(name, default)


def api(method, path, payload=None):
    url = f"{env('GITHUB_SERVER_URL').rstrip('/')}/api/v1{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {env('FORGEJO_TOKEN')}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e:
        # The token never appears here - only the status and Forgejo's own message.
        body = e.read().decode(errors="replace")[:500]
        sys.exit(f"{method} {path} -> HTTP {e.code}: {body}")


def log_tail():
    path = env("CI_LOG_FILE")
    if not path or not os.path.isfile(path):
        return None
    # newline="" keeps a bare \r as it is: progress output ("Reading database ... 5%\r...")
    # redraws one line, and Python's default newline handling would turn every redraw
    # into a line of its own - run 339's issue was mostly apt progress because of that.
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        lines = [line.rstrip("\r").rsplit("\r", 1)[-1] for line in f.read().split("\n")]
    tail = [ANSI.sub("", line)[:LINE_MAX_CHARS] for line in lines[-LOG_TAIL_LINES:]]
    # A ``` inside the log would end the code block early.
    return "\n".join(tail).replace("```", "'''")


def commit_subject():
    try:
        return subprocess.run(["git", "log", "-1", "--format=%s"], capture_output=True,
                              text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def main():
    repo = env("GITHUB_REPOSITORY")
    workflow = env("GITHUB_WORKFLOW")
    run_url = f"{env('GITHUB_SERVER_URL').rstrip('/')}/{repo}/actions/runs/{env('GITHUB_RUN_NUMBER')}"
    sha = env("GITHUB_SHA")[:7]
    subject = commit_subject()
    tail = log_tail()

    report = [
        f"**Lauf:** {run_url}",
        f"**Auslöser:** `{env('GITHUB_EVENT_NAME')}` auf `{sha}`" + (f" ({subject})" if subject else ""),
        f"**Job:** `{env('GITHUB_JOB')}`",
        "",
    ]
    if tail is None:
        report.append("_Kein Log mitgeschnitten - der Job ist vor dem ersten `run:`-Schritt gescheitert._")
    else:
        report += [f"Letzte {LOG_TAIL_LINES} Zeilen des Logs (mitgeschnitten, weil Forgejo "
                   "Task-Logs nicht zuverlässig archiviert):", "", "```", tail, "```"]
    text = "\n".join(report)

    title = f"CI rot: {workflow}"
    open_issues = api("GET", f"/repos/{repo}/issues?state=open&type=issues&limit=50"
                             f"&q={urllib.parse.quote(title)}") or []
    existing = next((i for i in open_issues if i.get("title") == title), None)
    if existing:
        api("POST", f"/repos/{repo}/issues/{existing['number']}/comments",
            {"body": "Erneut rot.\n\n" + text})
        print(f"Commented on existing issue #{existing['number']}: {title}")
    else:
        created = api("POST", f"/repos/{repo}/issues", {"title": title, "body": text})
        print(f"Opened issue #{created['number']}: {title}")


if __name__ == "__main__":
    main()
