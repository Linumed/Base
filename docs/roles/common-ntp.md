# common: NTP und Zeitzone

## Problem

Uneinheitliche Zeitzonen und driftende Systemuhren machen Log-Korrelation zwischen
mehreren Hosts (z.B. beim Debuggen einer HL7-Nachricht, die über mehrere Systeme läuft)
unnötig mühsam, und manche Protokolle/Zertifikatsprüfungen reagieren empfindlich auf
größere Zeitabweichungen. Diese Rolle setzt Zeitzone und NTP-Synchronisation konsistent.

## Variablen

Alle Variablen stehen mit sinnvollen Defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `common_timezone` | `"Etc/UTC"` | Systemzeitzone. Bewusst UTC statt einer lokalen Zeitzone - eindeutige Log-Timestamps über mehrere Hosts hinweg wiegen schwerer als lokale Wanduhrzeit auf einem Server. Pro Inventory überschreibbar, wenn Personal Logs direkt am Host mit lokaler Zeit lesen muss |
| `common_ntp_enabled` | `true` | Aktiviert die NTP-Konfiguration und `systemd-timesyncd` |
| `common_ntp_servers` | `[]` | Leer = Debians einkompiliertes Default-Pool. Für Umgebungen mit eingeschränktem Internet-Zugang eigenen NTP-Server eintragen |
| `common_ntp_fallback_servers` | `[]` | Fallback-Server, falls die primären nicht erreichbar sind |

## Was wird verändert

- Zeitzone via `community.general.timezone` (setzt `/etc/timezone` und
  `/etc/localtime`-Symlink).
- `/etc/systemd/timesyncd.conf.d/10-linumed.conf` (neu angelegt, Drop-in - die Hauptdatei
  `timesyncd.conf` wird nicht angefasst, aus demselben Grund wie bei den anderen
  Drop-ins in dieser Rolle: übersteht Paket-Upgrades sauber).
- `systemd-timesyncd` wird aktiviert und gestartet. Kein zusätzliches Paket nötig - Debian
  liefert und aktiviert es standardmäßig.

## Verifikation

```bash
timedatectl status
```

Erwartete Ausgabe: `Time zone` entspricht `common_timezone`, `System clock synchronized:
yes`, `NTP service: active`.

```bash
sudo cat /etc/systemd/timesyncd.conf.d/10-linumed.conf
```

Zeigt die tatsächlich aktiven NTP-Server, falls `common_ntp_servers` gesetzt wurde.

## Stolperfallen

- **chrony statt systemd-timesyncd**: falls auf einem Host `chrony` installiert ist (z.B.
  aus einem anderen Setup-Schritt), konkurriert das mit `systemd-timesyncd` um denselben
  NTP-Port. Diese Rolle geht vom Debian-Standard (`systemd-timesyncd`) aus und installiert
  kein `chrony` - bei einem chrony-Host vorher klären, welcher Dienst führend sein soll.
- **UTC-Default und Log-Tools**: wer Logs mit einem Tool liest, das keine Zeitzonen
  umrechnet, sieht UTC-Zeitstempel, nicht die lokale Uhrzeit. Das ist beabsichtigt, aber
  bei der ersten Verwirrung über „falsche" Uhrzeiten in Logs zuerst hier nachsehen, bevor
  eine tatsächliche Zeitabweichung vermutet wird.
