# common: unattended-upgrades

## Problem

Sicherheitslücken in Paketen, die nicht zeitnah eingespielt werden, sind auf einem Server
mit medizinischer Integrationssoftware ein direktes Risiko. Ein Mensch, der jede Nacht von
Hand `apt upgrade` fährt, skaliert nicht - diese Rolle automatisiert das Einspielen von
Sicherheitsupdates über den Standard-Mechanismus `unattended-upgrades`.

## Variablen

Alle Variablen haben den Präfix `common_unattended_upgrades_*` und stehen mit sinnvollen
Defaults in `ansible/roles/common/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `common_unattended_upgrades_enabled` | `true` | Installiert und konfiguriert `unattended-upgrades` |
| `common_unattended_upgrades_origins` | `["${distro_id}:${distro_codename}-security"]` | Nur Security-Updates. `-updates` ergänzen für volle unattended Updates - zieht dann auch Nicht-Security-Änderungen automatisch |
| `common_unattended_upgrades_automatic_reboot` | `false` | **Bewusst aus.** Ein unangekündigter Reboot auf einer Maschine mit Mirth/PACS ist riskanter als ein wartendes Kernel-Update |
| `common_unattended_upgrades_automatic_reboot_time` | `"02:00"` | Nur relevant, wenn Reboot oben auf `true` gesetzt wird |
| `common_unattended_upgrades_remove_unused_deps` | `true` | Räumt verwaiste Abhängigkeiten nach Updates auf |
| `common_unattended_upgrades_mail` | `""` (aus) | Leer = kein Mail-Report, da auf einem frischen Host kein MTA vorausgesetzt wird |

## Was wird verändert

- Paket `unattended-upgrades` wird installiert.
- `/etc/apt/apt.conf.d/20auto-upgrades` (neu angelegt): aktiviert die tägliche
  Paketlisten-Aktualisierung und den Unattended-Upgrade-Lauf.
- `/etc/apt/apt.conf.d/51-linumed-unattended-upgrades` (neu angelegt, eigene Datei statt
  Bearbeitung von `50unattended-upgrades`): Origins-Pattern, Reboot-Verhalten,
  Dependency-Cleanup, optionaler Mail-Report.
- Auslösung läuft über den Standard-Timer `apt-daily-upgrade.timer` (systemd), kein
  eigener Cronjob oder Timer wird angelegt.

## Verifikation

```bash
sudo unattended-upgrade --dry-run --debug
```

Zeigt, welche Pakete beim nächsten Lauf aktualisiert würden, ohne etwas zu verändern.

```bash
systemctl status apt-daily-upgrade.timer
sudo apt-config dump | grep -A3 Unattended-Upgrade::Origins-Pattern
```

Erster Befehl: Timer muss `active`/`waiting` sein. Zweiter: zeigt die tatsächlich
gemergten Origins - nicht nur die eigene Drop-in-Datei prüfen, `apt.conf.d` merged alle
Dateien im Verzeichnis.

## Stolperfallen

- **`apt.conf.d`-Dateien werden gemergt, nicht nach erstem Treffer gewählt** - anders als
  bei den `sshd_config.d`-Drop-ins in `common-ssh.md`. Ein zusätzlicher eigener Drop-in mit
  widersprüchlichem Inhalt in `/etc/apt/apt.conf.d/` überschreibt daher stillschweigend
  Werte aus `51-linumed-unattended-upgrades`, je nach alphabetischer Reihenfolge.
- **Automatischer Reboot ist bewusst aus.** Wer ihn aktiviert, sollte
  `common_unattended_upgrades_automatic_reboot_time` auf ein Wartungsfenster legen, in dem
  laufende Integrationen (Mirth-Nachrichtenverarbeitung) keinen Schaden nehmen.
- **`-updates`-Origin zieht mehr als Security-Fixes.** Nur ergänzen, wenn bewusst mehr als
  Sicherheitsupdates automatisiert werden sollen - das erhöht das Risiko einer
  unerwarteten Verhaltensänderung durch ein reguläres Paket-Update.
