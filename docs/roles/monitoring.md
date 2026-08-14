# monitoring: Observability-Stack

## Problem

Ohne Monitoring merkt man einen vollen Datenträger, einen abgestürzten Container oder
einen fehlgeschlagenen Backup-Lauf erst, wenn ein Nutzer sich meldet - oder gar nicht.
Diese Rolle bringt Metriken (Prometheus), Dashboards (Grafana), Logs (Loki) und
Alarmierung (Alertmanager) als Docker-Compose-Stack, plus Host-Metriken über einen
nativen Node-Exporter-Dienst.

## Variablen

Alle Variablen haben den Präfix `monitoring_*` und stehen mit sinnvollen Defaults in
`ansible/roles/monitoring/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `monitoring_deploy_dir` | `/opt/linumed-os/monitoring` | Zielverzeichnis auf dem Host |
| `monitoring_grafana_admin_password` | `""` (Pflicht) | Kein Default - die Rolle bricht per Preflight ab, wenn nicht gesetzt |
| `monitoring_grafana_admin_user` | `"admin"` | Grafana-Admin-Benutzername |
| `monitoring_grafana_port` | `3000` | Nur auf `127.0.0.1` gebunden - Zugriff per SSH-Tunnel |
| `monitoring_prometheus_port` | `9090` | Nur auf `127.0.0.1` gebunden - fürs Debugging/`promtool` |
| `monitoring_metrics_retention_days` | `90` | Prometheus-Retention |
| `monitoring_logs_retention_days` | `30` | Loki-Retention - kürzer als Metriken, siehe DSGVO-Abschnitt unten |
| `monitoring_retention_days` | `~` (leer) | Überschreibt, falls gesetzt, beide Retention-Werte gleichzeitig |
| `monitoring_node_exporter_port` | `9100` | Muss auf allen Interfaces lauschen (siehe Stolperfallen), ufw blockt von außen |
| `monitoring_node_exporter_deny_external` | `true` | Explizite ufw-Deny-Regel für den Node-Exporter-Port |
| `monitoring_alertmanager_smtp_smarthost` | `""` | Leer = keine Zustellung (v0.1-Verhalten). Gesetzt = SMTP-Relay `host:port`, schaltet den Preflight scharf |
| `monitoring_alertmanager_smtp_from` | `""` | Pflicht, sobald der Smarthost gesetzt ist |
| `monitoring_alertmanager_smtp_auth_username` / `_password` | `""` | Optional; wenn Username gesetzt ist, ist das Passwort Pflicht |
| `monitoring_alertmanager_smtp_require_tls` | `true` | STARTTLS - nur ohne Verschlüsselung lassen, wenn der Smarthost lokal/getunnelt ist |
| `monitoring_alertmanager_receivers` | `[]` | Liste von E-Mail-Adressen, die den `default`-Receiver bekommen; Pflicht (mind. ein Eintrag), sobald der Smarthost gesetzt ist |
| `monitoring_alertmanager_group_wait` / `_group_interval` / `_repeat_interval` | `30s` / `5m` / `4h` | Sinnvolle Defaults für einen Klinik-Betriebskontext, überschreibbar |

## Was wird verändert

- `{{ monitoring_deploy_dir }}/` - Prometheus-, Loki-, Alertmanager-, Alloy-Konfiguration,
  Grafana-Provisioning und der Docker-Compose-Stack.
- `/etc/default/prometheus-node-exporter` - Kommandozeilenargumente des nativen Dienstes.
- `/var/lib/prometheus/node-exporter/` - Textfile-Collector-Verzeichnis (für die
  künftige backup-Rolle, #7).
- ufw-Regel: `deny` auf `monitoring_node_exporter_port`/tcp.
- Docker-Container: Prometheus, Grafana, Loki, Grafana Alloy, Alertmanager, cAdvisor.

## Zugriff auf Grafana

Standardmäßig nur über SSH-Tunnel erreichbar, kein Caddy-Routing in v0.1 (siehe
`ARCHITECTURE.md`, Abschnitt „Netzwerk-Design"):

```bash
ssh -L 3000:127.0.0.1:3000 <user>@<host>
# dann im Browser: http://localhost:3000
```

## Verifikation

Nicht nur „Container laufen" - echte Funktion prüfen:

```bash
# Alle Scrape-Targets wirklich UP
curl -s localhost:9090/api/v1/targets | python3 -c \
  "import sys,json;[print(t['labels']['job'],t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"

# Eine Host-Metrik existiert wirklich (nicht nur "Target grün")
curl -s 'localhost:9090/api/v1/query?query=node_load1'

# Prometheus kennt den Alertmanager
curl -s localhost:9090/api/v1/alertmanagers

# Alle Alert-Regeln geladen und "ok"
curl -s localhost:9090/api/v1/rules

# Grafana gesund
curl -s localhost:3000/api/health
```

Loki und Alertmanager haben **keinen veröffentlichten Port** (siehe Stolperfallen) -
von außerhalb des Compose-Netzes nur über einen temporären Debug-Container im selben
Netzwerk-Namespace erreichbar:

```bash
docker run --rm --network container:linumed-os-loki curlimages/curl:latest -s -G \
  "http://127.0.0.1:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="journal"}' --data-urlencode limit=3
```

## Stolperfallen

- **Node Exporter lauscht bewusst auf allen Interfaces, nicht nur `127.0.0.1`.** Ein
  Container (Prometheus) kann das Host-Loopback nicht erreichen - deshalb lauscht der
  Dienst auf `:9100`, und Prometheus scrapt über `host.docker.internal`
  (`extra_hosts: host-gateway`). Der eigentliche Schutz ist die explizite ufw-Deny-Regel,
  nicht die Bindung - und die funktioniert hier wirklich, anders als bei einem
  veröffentlichten Docker-Container-Port (siehe `docs/roles/common-ufw.md`, "Docker
  umgeht ufw").
- **Loki und Alertmanager haben keinen Host-Port.** Sie sind nur innerhalb des
  Compose-Netzes über Servicenamen erreichbar - das ist Absicht (kleinere Angriffsfläche),
  nicht vergessen. Debuggen geht über den oben gezeigten Netzwerk-Namespace-Trick.
- **`grafana/loki` hat keinen Healthcheck** - das Image enthält keine Shell, kein `wget`,
  nichts außer der loki-Binary selbst. Ein exec-basierter Healthcheck ist damit technisch
  unmöglich; Funktionsprüfung läuft über eine echte Query (siehe Verifikation).
- **Retention allein löscht nichts.** `monitoring_logs_retention_days` setzt bei Loki nur
  `retention_period` - ohne den aktivierten Compactor (`retention_enabled: true`, von
  dieser Rolle mitkonfiguriert) passiert trotzdem nichts, die Platte läuft voll.
- **`monitoring_retention_days` überschreibt beide Werte gleichzeitig**, nicht nur einen -
  wer nur die Metriken-Retention ändern will, setzt `monitoring_metrics_retention_days`
  direkt, nicht die gemeinsame Variable.
- **Alertmanager-Zustellung ist opt-in und alles-oder-nichts** (#22). Ohne gesetztes
  `monitoring_alertmanager_smtp_smarthost` landen Alerts weiterhin nur in Alertmanager und
  sind über dessen API sichtbar, niemand wird benachrichtigt. Wird der Smarthost gesetzt,
  verlangt ein Preflight zusätzlich `monitoring_alertmanager_smtp_from` und mindestens eine
  Adresse in `monitoring_alertmanager_receivers` (und ein Passwort, falls
  `monitoring_alertmanager_smtp_auth_username` gesetzt ist) - eine halb konfigurierte
  Zustellung wird abgelehnt statt Alerts still zu verschlucken. Empfängergruppen,
  Eskalationsstufen und Ruhezeiten pro Standort sind bewusst nicht Teil dieser Rolle: es
  gibt nur einen `default`-Receiver, der an alle konfigurierten Adressen mailt.

## DSGVO: was in Loki landet

Logs sind personenbezogene Daten in einem Sinn, den Metriken nicht sind: Journal- und
Container-Logs können IP-Adressen, Benutzernamen und im Einzelfall auch
Anwendungsdaten enthalten, je nachdem, was die jeweilige Anwendung protokolliert. Deshalb:

- **Retention ist bewusst kürzer** als bei Metriken (`monitoring_logs_retention_days: 30`
  vs. `monitoring_metrics_retention_days: 90`) - Datenminimierung, keine Willkür.
- **Zugriff auf Grafana/Loki ist auf SSH-Tunnel-Nutzer beschränkt** (kein öffentlicher
  Zugriff in v0.1), das schränkt den Kreis der Personen ein, die Logs einsehen können.
- **Was tatsächlich geloggt wird, hängt von den betriebenen Anwendungen ab** - diese Rolle
  sammelt nur, was die Anwendungen selbst ins Journal oder auf `stdout`/`stderr`
  schreiben. Für die Verarbeitungsübersicht eines Kunden gehört dokumentiert, welche
  Anwendungen auf dem Host laufen und was sie loggen - das kann diese Rolle nicht
  pauschal beantworten.
- Alloy braucht für Container-Log-Sammlung Lesezugriff auf den Docker-Socket (read-only) -
  eine bewusste Privilegien-Abwägung, siehe `ansible/roles/monitoring/README.md`.
