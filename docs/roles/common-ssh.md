# common: SSH-Härtung

## Problem

Ein frisch installiertes Debian erlaubt standardmäßig Passwort-Login per SSH und (je nach
Installationsweg) teils auch Root-Login. Für einen Server, der aus dem Internet oder auch
nur aus dem Klinik-LAN erreichbar ist, ist das ein Einfallstor für Brute-Force-Angriffe.
Diese Rolle härtet SSH auf einen Key-only-Zugang mit eingeschränktem Root-Login, ohne dass
man jede Zeile von Hand in `/etc/ssh/sshd_config` pflegen muss.

## Variablen

Alle Variablen haben den Präfix `common_ssh_*` und stehen mit sinnvollen Defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `common_ssh_port` | `22` | SSH-Port. Die ufw-Rolle öffnet diesen Port automatisch (siehe `common-ufw.md`) - beim Ändern reicht es, `common_ssh_port` einmal zentral zu setzen |
| `common_ssh_permit_root_login` | `"no"` | Root-Login komplett aus |
| `common_ssh_password_authentication` | `"no"` | Passwort-Login aus, nur noch Key |
| `common_ssh_pubkey_authentication` | `"yes"` | Key-Login an |
| `common_ssh_kbd_interactive_authentication` | `"no"` | Interaktive Auth-Verfahren aus |
| `common_ssh_x11_forwarding` | `"no"` | Kein X11-Forwarding |
| `common_ssh_max_auth_tries` | `3` | Max. Auth-Versuche pro Verbindung |
| `common_ssh_login_grace_time` | `30` | Sekunden bis Verbindungsabbruch ohne erfolgreiche Auth |
| `common_ssh_allow_users` | `[]` | Leer = keine Einschränkung. Nur setzen, wenn sicher ist, dass der eigene Nutzer drinsteht |
| `common_ssh_allow_groups` | `[]` | Wie oben, gruppenbasiert |
| `common_ssh_preflight_enabled` | `true` | Sicherheitscheck vor dem Abschalten von Root-Login (siehe unten). Nur für bewusst root-only-Hosts (z.B. Wegwerf-CI-Images) auf `false` setzen |

## Was wird verändert

- **Datei**: `/etc/ssh/sshd_config.d/10-linumed-hardening.conf` (neu angelegt). Die
  Hauptdatei `/etc/ssh/sshd_config` wird **nicht** angefasst — sie ist auf Debian
  ucf-verwaltet, ein Voll-Template würde bei jedem `openssh-server`-Upgrade gegen ucf
  verlieren.
- **Dienst**: `ssh.service` wird bei Änderung neu geladen (`systemctl reload ssh`), nicht
  neu gestartet — bestehende Verbindungen bleiben offen.
- **Port**: standardmäßig unverändert (22).

## Verifikation

Nach einem Playbook-Lauf selbst nachprüfen, nicht dem Playbook-Output vertrauen:

```bash
sudo /usr/sbin/sshd -T | grep -E '^(permitrootlogin|passwordauthentication|port|maxauthtries)'
```

Erwartete Ausgabe (mit Default-Werten):

```
permitrootlogin no
passwordauthentication no
port 22
maxauthtries 3
```

Zusätzlich: ein Passwort-Login muss fehlschlagen, ein Key-Login muss funktionieren.

## Stolperfallen

- **Reihenfolge der Drop-ins**: sshd nimmt für jede Direktive den *ersten* gefundenen Wert.
  Cloud-Images liefern oft ein `50-cloud-init.conf` mit — unser `10-linumed-hardening.conf`
  gewinnt nur, weil `10` vor `50` kommt. Eigene zusätzliche Drop-ins mit höherer Nummer
  anlegen, niemals mit niedrigerer.
- **Socket-Aktivierung**: falls `ssh.socket` aktiv ist (Debian bietet das optional an, siehe
  `README.Debian` von `openssh-server`), ignoriert `sshd` seine eigene `Port`-Direktive — der
  Port kommt dann aus `ListenStream=` der Socket-Unit. Die Rolle erkennt das und bricht ab,
  statt einen wirkungslosen Port zu setzen.
- **Root-Login-Sperre ohne Rettungsanker**: die Rolle bricht von sich aus ab, wenn kein
  Nicht-Root-Nutzer mit Sudo-Rechten und hinterlegtem SSH-Key existiert — das ist Absicht,
  nicht ein Bug. Vor dem ersten Lauf also erst einen Admin-Nutzer mit Key anlegen (siehe
  geplantes `scripts/bootstrap.sh`).
