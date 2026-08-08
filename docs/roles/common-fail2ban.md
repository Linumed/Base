# common: fail2ban

## Problem

Auch mit Key-only-SSH (siehe `common-ssh.md`) sieht ein aus dem Internet erreichbarer
Server dauerhaft automatisierte Login-Versuche in den Logs. Das ist zwar ungefährlich,
solange Passwort-Auth aus ist, erzeugt aber Lograuschen und unnötige CPU-Last durch die
Auth-Versuche selbst. fail2ban sperrt IPs nach wiederholten Fehlversuchen per Firewall-Regel
zeitweise komplett aus.

## Variablen

Alle Variablen haben den Präfix `common_fail2ban_*` und stehen mit sinnvollen Defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `common_fail2ban_enabled` | `true` | Installiert und aktiviert fail2ban. Bei `false` wird der Dienst gestoppt/deaktiviert (falls vorhanden), nicht deinstalliert |
| `common_fail2ban_backend` | `"systemd"` | Liest den Journal-Log direkt, keine Abhängigkeit von `/var/log/auth.log`/rsyslog |
| `common_fail2ban_maxretry` | `5` | Fehlversuche bis zum Ban |
| `common_fail2ban_findtime` | `"10m"` | Zeitfenster, in dem `maxretry` erreicht werden muss |
| `common_fail2ban_bantime` | `"1h"` | Dauer des Bans |
| `common_fail2ban_ignoreip` | `["127.0.0.1/8", "::1"]` | Nie gesperrte Adressen. Eigene Management-IP/Tailscale-Range ergänzen, sonst kann man sich bei zu vielen Fehlversuchen selbst aussperren |

## Was wird verändert

- Paket `fail2ban` wird installiert.
- `/etc/fail2ban/jail.d/10-linumed-sshd.conf` (neu angelegt, Drop-in). `jail.local`/
  `jail.conf` werden **nicht** angefasst - fail2ban dokumentiert `jail.d/` selbst als den
  Ort für lokale Overrides, und `jail.conf` wird bei Paket-Upgrades ohnehin überschrieben.
- Dienst `fail2ban` wird bei Änderung neu gestartet (nicht neu geladen - siehe
  `handlers/main.yml`), aktiviert und gestartet.

## Verifikation

```bash
sudo fail2ban-client status sshd
```

Erwartete Ausgabe enthält u.a. `Currently banned` und `Total banned` (0 direkt nach dem
Rollout ist normal) sowie die aus `common_ssh_port` übernommene Portnummer unter
`Filter`/`Actions`.

```bash
sudo fail2ban-client status
```

zeigt, ob der Jail `sshd` überhaupt aktiv ist.

## Stolperfallen

- **`common_fail2ban_ignoreip` vor dem ersten scharfen Test erweitern**: wer von einer IP
  aus testet, die absichtlich Fehlversuche erzeugt (z.B. ein Passwort-Login-Test gegen
  `common_ssh_password_authentication`), kann sich selbst aussperren. Die eigene
  Tailscale-/Management-Range vorher eintragen.
- **Zusammenspiel mit ufw**: fail2bans Standardaktion (`iptables-multiport`) setzt eigene
  `iptables`-Regeln, unabhängig von den ufw-Regeln aus `common-ufw.md`. Beide koexistieren
  in unterschiedlichen Chains - ein `ufw status` zeigt daher **keine** fail2ban-Bans an,
  dafür ist `fail2ban-client status sshd` nötig.
- **Backend `systemd`**: setzt voraus, dass sshd über den Journal-Log erreichbar ist (Debian
  Default). Wurde `rsyslog` deinstalliert oder journald umkonfiguriert, greift das nicht -
  in dem Fall `common_fail2ban_backend` explizit auf `"auto"` setzen.
