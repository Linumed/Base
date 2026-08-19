#!/usr/bin/env python3
"""Prometheus exporter for BridgeLink (Mirth Connect fork) channel statistics.

Why this exists at all: BridgeLink exposes no /metrics endpoint of its own (verified
against 26.6.0-dhi-slim - GET /metrics returns 404), so cAdvisor's container-level
CPU/RAM numbers were the only thing Prometheus ever saw for it. Those cannot show a
stopped channel or a filling queue, which are the failure modes that actually matter for
an integration engine. See issue #60 and docs/roles/bridgelink.md.

Why a script and not an off-the-shelf exporter:

  * prometheus-community/json_exporter was tested first and rejected. BridgeLink's JSON
    is produced by XStream/Jettison from its XML model, so a list with exactly one entry
    serialises as an object and a list with two or more as an array. json_exporter's
    JSONPath then matches nothing at all for a single-channel installation and it reports
    success while emitting zero metrics - a silent hole in monitoring, which is worse than
    no monitoring. Measured on a real instance, all of '{.list.channelStatistics[*]}',
    '{.list.channelStatistics}' and '{..channelStatistics}'. The XML representation has no
    such ambiguity, which is why this script asks for XML.
  * The existing community exporters (vynca/mirth_exporter, teamzerolabs/
    mirth_channel_exporter, feathersct/mirth-prometheus-exporter) target Mirth 3.3-3.7,
    see no maintenance, and publish no pinned container image. vynca's shells out to the
    Mirth CLI, which does not exist in the -dhi-slim image at all.

Deliberately standard library only. That keeps it runnable inside a pinned upstream
python image with the script bind-mounted read-only, so this repo does not have to build,
scan and host a container image of its own for it (CONVENTIONS.md: images are pinned
upstream tags).
"""

from __future__ import annotations

import base64
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Mirth rejects any API request without this header with HTTP 400 - it is a CSRF guard,
# the value is not checked.
_REQUIRED_HEADER = ("X-Requested-With", "bridgelink-exporter")

# Message counters Mirth keeps per channel and per connector.
_STATUSES = ("RECEIVED", "FILTERED", "SENT", "ERROR")

# Channel/connector states Mirth can report. Exported as one gauge per state (the
# standard "state set" pattern) rather than a number, so alert rules can say
# state="STARTED" instead of memorising an integer mapping.
_STATES = ("STARTED", "PAUSED", "STOPPED", "STARTING", "PAUSING", "STOPPING", "UNDEPLOYED")


def _read_secret(env_name: str, file_env_name: str) -> str:
    """Read a value from a *_FILE path if given, else from the variable itself.

    The file form is what the Compose stack uses: the password reaches the container as a
    Docker secret, never as an environment variable, because env vars are readable by
    anyone who can run `docker inspect`.
    """
    path = os.environ.get(file_env_name)
    if path:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    return os.environ.get(env_name, "")


class BridgeLinkClient:
    def __init__(self, base_url: str, user: str, password: str, timeout: float, verify_tls: bool):
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        token = base64.b64encode(f"{user}:{password}".encode()).decode("ascii")
        self._auth = f"Basic {token}"
        if verify_tls:
            self._ctx = ssl.create_default_context()
        else:
            # BridgeLink generates a self-signed keystore on first start and this
            # connection never leaves the Docker network, so verification is off by
            # default. BRIDGELINK_EXPORTER_VERIFY_TLS=true turns it on for installations
            # that put a real certificate in the keystore.
            self._ctx = ssl.create_default_context()
            self._ctx.check_hostname = False
            self._ctx.verify_mode = ssl.CERT_NONE

    def get_xml(self, path: str) -> ET.Element:
        request = urllib.request.Request(f"{self._base_url}{path}")
        request.add_header(*_REQUIRED_HEADER)
        request.add_header("Authorization", self._auth)
        # XML, not JSON, on purpose - see the module docstring for the single-entry
        # serialisation trap in Mirth's JSON output.
        request.add_header("Accept", "application/xml")
        with urllib.request.urlopen(request, timeout=self._timeout, context=self._ctx) as response:
            return ET.fromstring(response.read())


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


class MetricWriter:
    def __init__(self) -> None:
        self._lines: list[str] = []
        self._declared: set[str] = set()

    def add(self, name: str, value, labels: dict[str, str] | None = None,
            help_text: str = "", metric_type: str = "gauge") -> None:
        if name not in self._declared:
            self._lines.append(f"# HELP {name} {help_text}")
            self._lines.append(f"# TYPE {name} {metric_type}")
            self._declared.add(name)
        if labels:
            rendered = ",".join(f'{k}="{_escape(v)}"' for k, v in labels.items())
            self._lines.append(f"{name}{{{rendered}}} {value}")
        else:
            self._lines.append(f"{name} {value}")

    def render(self) -> bytes:
        return ("\n".join(self._lines) + "\n").encode("utf-8")


def _statistics(node: ET.Element, tag: str) -> dict[str, int]:
    """Pull the RECEIVED/FILTERED/SENT/ERROR map out of a dashboardStatus element."""
    counters = {status: 0 for status in _STATUSES}
    container = node.find(tag)
    if container is None:
        return counters
    for entry in container.findall("entry"):
        status = entry.findtext("com.mirth.connect.donkey.model.message.Status")
        count = entry.findtext("long")
        if status in counters and count is not None:
            counters[status] = int(count)
    return counters


def _emit_status(writer: MetricWriter, node: ET.Element, labels: dict[str, str], prefix: str) -> None:
    state = (node.findtext("state") or "").upper()
    for candidate in _STATES:
        writer.add(
            f"{prefix}_state",
            1 if candidate == state else 0,
            {**labels, "state": candidate},
            help_text="Current state of the channel/connector (1 for the active state).",
        )

    # lifetimeStatistics, not statistics: the latter is reset by "clear statistics" in the
    # Administrator and by a redeploy, which would make a Prometheus counter go backwards
    # and produce phantom spikes in rate(). Lifetime values only ever increase.
    for status, count in _statistics(node, "lifetimeStatistics").items():
        writer.add(
            f"{prefix}_messages_total",
            count,
            {**labels, "status": status.lower()},
            help_text="Messages by outcome since the channel was created.",
            metric_type="counter",
        )

    queued = node.findtext("queued")
    if queued is not None:
        writer.add(
            f"{prefix}_queued_messages",
            int(queued),
            labels,
            help_text="Messages currently waiting in the queue.",
        )


def collect(client: BridgeLinkClient) -> bytes:
    writer = MetricWriter()
    started = time.monotonic()
    try:
        statuses = client.get_xml("/api/channels/statuses")
        stats = client.get_xml("/api/system/stats")
    except (urllib.error.URLError, ET.ParseError, OSError, ValueError) as exc:
        # up=0 rather than an HTTP error: Prometheus records the failure as data this way,
        # so "BridgeLink unreachable" is alertable instead of just being a scrape error.
        print(f"scrape failed: {exc}", file=sys.stderr, flush=True)
        writer.add("bridgelink_up", 0, help_text="1 if the BridgeLink API answered this scrape.")
        return writer.render()

    writer.add("bridgelink_up", 1, help_text="1 if the BridgeLink API answered this scrape.")

    channel_count = 0
    for channel in statuses.findall("dashboardStatus"):
        channel_count += 1
        labels = {
            "channel": channel.findtext("name") or "",
            "channel_id": channel.findtext("channelId") or "",
        }
        _emit_status(writer, channel, labels, "bridgelink_channel")

        children = channel.find("childStatuses")
        for connector in (children.findall("dashboardStatus") if children is not None else []):
            _emit_status(
                writer,
                connector,
                {
                    **labels,
                    "connector": connector.findtext("name") or "",
                    "connector_type": connector.findtext("statusType") or "",
                },
                "bridgelink_connector",
            )

    writer.add("bridgelink_channels_deployed", channel_count,
               help_text="Number of channels currently deployed.")

    # JVM heap and disk from the engine's own view. cAdvisor sees the container's RSS,
    # which for a JVM says nothing about how close the heap is to its ceiling.
    info = stats.find("*") if stats.tag != "com.mirth.connect.model.SystemStats" else stats
    source = info if info is not None else stats
    for tag, name, help_text in (
        ("cpuUsagePct", "bridgelink_cpu_usage_ratio", "Process CPU usage as reported by the engine (0-1)."),
        ("allocatedMemoryBytes", "bridgelink_jvm_memory_allocated_bytes", "JVM heap currently allocated."),
        ("freeMemoryBytes", "bridgelink_jvm_memory_free_bytes", "Free memory within the allocated JVM heap."),
        ("maxMemoryBytes", "bridgelink_jvm_memory_max_bytes", "JVM heap ceiling (-Xmx)."),
        ("diskFreeBytes", "bridgelink_disk_free_bytes", "Free space on the engine's data filesystem."),
        ("diskTotalBytes", "bridgelink_disk_total_bytes", "Total space on the engine's data filesystem."),
    ):
        value = source.findtext(tag)
        if value is not None:
            writer.add(name, float(value), help_text=help_text)

    writer.add("bridgelink_scrape_duration_seconds", round(time.monotonic() - started, 6),
               help_text="Time the exporter spent querying the BridgeLink API.")
    return writer.render()


class Handler(BaseHTTPRequestHandler):
    client: BridgeLinkClient

    def do_GET(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        if self.path.startswith("/metrics"):
            body = collect(self.client)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path in ("/", "/healthz"):
            # Liveness of the exporter itself, deliberately not of BridgeLink - the
            # container healthcheck uses this and must not restart the exporter just
            # because the engine it watches is down.
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args) -> None:
        pass  # one line per scrape every 15s is noise, not a log


def main() -> int:
    base_url = os.environ.get("BRIDGELINK_URL", "https://bridgelink:8443")
    user = os.environ.get("BRIDGELINK_EXPORTER_USER", "")
    password = _read_secret("BRIDGELINK_EXPORTER_PASSWORD", "BRIDGELINK_EXPORTER_PASSWORD_FILE")
    if not user or not password:
        print("BRIDGELINK_EXPORTER_USER and a password (or _FILE) must be set",
              file=sys.stderr, flush=True)
        return 2

    Handler.client = BridgeLinkClient(
        base_url=base_url,
        user=user,
        password=password,
        timeout=float(os.environ.get("BRIDGELINK_EXPORTER_TIMEOUT", "10")),
        verify_tls=os.environ.get("BRIDGELINK_EXPORTER_VERIFY_TLS", "false").lower() == "true",
    )
    port = int(os.environ.get("BRIDGELINK_EXPORTER_PORT", "9151"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)  # noqa: S104 - published on loopback only
    print(f"bridgelink exporter listening on :{port}, target {base_url}", flush=True)
    threading.current_thread().name = "main"
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
