# backup: Verschlüsselte Backups

## Problem

Ein Server ohne Backup ist ein Server, dessen Datenverlust nur eine Frage der Zeit ist -
Festplattenausfall, ein Fehlbedienung, ein fehlgeschlagenes Update. Diese Rolle richtet
verschlüsselte, automatisierte Backups mit [restic](https://restic.net/) ein, geplant über
einen systemd-Timer, mit Ergebnis-Metriken für Prometheus.

## Variablen

Alle Variablen haben den Präfix `backup_*` und stehen in
`ansible/roles/backup/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `backup_repository` | `""` (Pflicht) | restic-Repository-URI, jedes von restic unterstützte Backend |
| `backup_restic_password` | `""` (Pflicht) | Verschlüsselungspasswort - **ohne dieses Passwort sind alle Backups unwiederbringlich verloren** |
| `backup_paths` | `/opt/linumed-os`, `/var/lib/docker/volumes` | Was gesichert wird |
| `backup_retention_keep_daily/weekly/monthly` | `7`/`4`/`6` | Aufbewahrung nach `restic forget` |
| `backup_schedule` | `*-*-* 03:00:00` | systemd-`OnCalendar`-Ausdruck |

Ohne `backup_repository` und `backup_restic_password` bricht die Rolle im Preflight ab.
Beide gehören in Ansible Vault.

## Backend-Beispiele

```yaml
# Lokal / externe Platte
backup_repository: "/mnt/backup-disk/linumed-os"

# SFTP
backup_repository: "sftp:user@backup-host:/srv/restic/linumed-os"

# S3-kompatibel (z. B. Hetzner Object Storage) - Zugangsdaten separat
# als AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY setzen, nicht Teil dieser Rolle
backup_repository: "s3:https://fsn1.your-objectstorage.com/linumed-os-backup"
```

Diese Rolle richtet das Backend selbst nicht ein - SSH-Keys, S3-Buckets oder
IAM-Policies müssen vorher existieren.

## Was gesichert wird

Standardmäßig `/opt/linumed-os` (Konfiguration und Secrets aller Rollen) und
`/var/lib/docker/volumes` (alle benannten Docker-Volumes: Prometheus-, Loki-,
Grafana-Daten, BridgeLinks Appdata und dessen PostgreSQL-Datenbank). Direkter
Dateizugriff, kein `docker-volume-backup`, kein datenbankeigenes Dump-Werkzeug.

## Verifikation

```bash
# Timer aktiv?
systemctl status linumed-os-backup.timer

# Letzter Lauf
systemctl status linumed-os-backup.service
journalctl -u linumed-os-backup.service -n 50

# Metrik wirklich geschrieben?
cat /var/lib/prometheus/node-exporter/backup.prom

# Snapshots wirklich im Repository?
restic snapshots
```

Ein manueller Testlauf: `sudo systemctl start linumed-os-backup.service`.

## Restore-Test (Pflicht, keine Kür)

Ein Backup, das nie zurückgespielt wurde, ist kein verifiziertes Backup - das gilt
generell, nicht nur für dieses Repo. Manuelles Vorgehen, regelmäßig wiederholen:

```bash
export RESTIC_REPOSITORY="<dasselbe Repository wie backup_repository>"
export RESTIC_PASSWORD_FILE=/etc/restic/password

restic snapshots                                    # welche Stände gibt es
restic restore latest --target /tmp/restore-test     # in ein Testverzeichnis zurückspielen
diff -rq /tmp/restore-test/opt/linumed-os /opt/linumed-os   # Stichprobe
rm -rf /tmp/restore-test
```

Diese Rolle automatisiert das nicht (kein `backup-restore-test.yml`) - das ist ein
bewusst offener Punkt für eine spätere Version, nicht ein Versehen.

## Stolperfallen

- **Kein Datenbank-konsistentes Backup.** `/var/lib/docker/volumes` wird als normales
  Dateisystem gesichert, während PostgreSQL (BridgeLink) währenddessen läuft und
  schreibt - das ist nicht dieselbe Garantie wie `pg_dump` oder ein atomarer
  Filesystem-Snapshot. Für v0.1 ein bewusster Trade-off: die Alternative (Datenbank vor
  jedem Backup stoppen) hätte für ein System mit Integrationsengine echte
  Verfügbarkeitskosten. Wer das nicht akzeptieren kann, sollte zusätzlich einen
  regelmäßigen `pg_dump` in `backup_paths` aufnehmen.
- **Ohne das restic-Passwort ist alles verloren.** Es gibt keinen
  Wiederherstellungsmechanismus. Das Passwort gehört zusätzlich zum lokalen Vault an
  einen zweiten, physisch getrennten Ort (siehe `~/.claude/CLAUDE.md` der Dev-Maschine,
  Abschnitt zu Totalverlust am Standort - dieselbe Logik gilt für jede damit gebaute
  Installation).
- **Trap sorgt dafür, dass ein Fehlschlag sichtbar bleibt**, nicht dass er verschwindet.
  Schlägt `restic backup`, `forget` oder `check` fehl, wird trotzdem eine Metrik
  geschrieben (`backup_success 0`) - ein stiller Fehlschlag, der erst auffällt, wenn ein
  Restore gebraucht wird, ist der eigentliche Albtraum bei Backups.
- **`restic forget --prune` löscht alte Snapshots** gemäß der Retention-Policy - das ist
  beabsichtigt, aber wer die Werte in `backup_retention_keep_*` nach unten setzt, verliert
  entsprechend frühere Wiederherstellungspunkte.
