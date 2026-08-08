# common: ufw-Firewall

## Problem

Ein frisch installiertes Debian hat keine aktive Firewall - jeder Dienst, der später einen
Port öffnet (Docker-Container eingeschlossen, siehe Falle dazu in `CLAUDE.md` bzw.
`~/.claude/CLAUDE.md` der Dev-Maschine), ist damit sofort im gesamten erreichbaren Netz
sichtbar. Diese Rolle setzt `ufw` mit Default-Deny für eingehenden Verkehr auf und öffnet
nur explizit benötigte Ports.

## Variablen

Alle Variablen haben den Präfix `common_ufw_*` und stehen mit sinnvollen Defaults in
`ansible/roles/common/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `common_ufw_enabled` | `true` | Aktiviert ufw am Ende des Rollenlaufs |
| `common_ufw_default_incoming` | `"deny"` | Default-Policy für eingehenden Verkehr |
| `common_ufw_default_outgoing` | `"allow"` | Default-Policy für ausgehenden Verkehr |
| `common_ufw_allow_ssh` | `true` | Öffnet `common_ssh_port`/tcp automatisch. Nur auf `false` setzen, wenn SSH-Zugriff über einen anderen Mechanismus abgesichert ist |
| `common_ufw_extra_rules` | `[]` | Liste weiterer Regeln, z.B. `- {port: 443, proto: tcp, comment: "HTTPS"}` |

## Was wird verändert

- Paket `ufw` wird installiert.
- Default-Policies (`ufw default deny incoming` / `allow outgoing`).
- Erlaubt-Regel für `common_ssh_port`/tcp, danach für jeden Eintrag in
  `common_ufw_extra_rules`.
- `ufw enable` läuft als letzter Schritt - erst wenn die SSH-Regel steht.

## Voraussetzung: Collection

Nutzt `community.general.ufw`, nicht `ansible.builtin`. Vor dem ersten Lauf:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## Verifikation

```bash
sudo ufw status verbose
```

Erwartete Ausgabe (mit Default-Werten): Status `active`, `Default: deny (incoming), allow
(outgoing)`, eine Regel für Port 22/tcp (oder den konfigurierten `common_ssh_port`).

Zusätzlich von einem zweiten Rechner aus prüfen: Verbindung auf einen nicht freigegebenen
Port muss hängen bleiben/timeout, nicht "connection refused" liefern (das wäre ein
geschlossener, aber nicht gefilterter Port - ein Zeichen, dass ufw nicht wie erwartet vor
dem Dienst sitzt).

## Stolperfallen

- **Reihenfolge**: ufw erst aktivieren, nachdem die SSH-Regel gesetzt ist - sonst kappt der
  Default-Deny die laufende Ansible-Verbindung. Die Rolle hält diese Reihenfolge ein
  (`tasks/ufw.yml`), von Hand nachgebaute Playbooks müssen selbst darauf achten.
- **Docker umgeht ufw**: ein Container-Port, der per `ports:` veröffentlicht wird, ist trotz
  aktiver ufw-Regeln im LAN erreichbar (`iptables`-Regeln von Docker liegen vor den
  ufw-Regeln in der Chain). Diese Rolle ändert daran nichts - Container-Ports gehören an
  `127.0.0.1` gebunden, öffentlicher Zugriff läuft über einen Reverse Proxy oder Tailscale.
- **Port-Wechsel bei SSH**: wird `common_ssh_port` geändert, öffnet diese Rolle automatisch
  den neuen Port mit - trotzdem beide Rollen (SSH und ufw) im selben Lauf anwenden, nie den
  Port manuell in `sshd_config` ändern und ufw separat/später laufen lassen.
