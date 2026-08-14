# ARCHITECTURE.md - Linumed OS

## Übersicht

Linumed OS ist kein eigenes Betriebssystem und kein bootfähiges Image.
Es ist ein Infrastructure-as-Code Kit auf Basis von Ansible, das ein
Standard-Debian 13 (Trixie) in eine gehärtete, DSGVO-konforme
Healthcare-Infrastruktur verwandelt.

Zielgruppe sind IT-Abteilungen und Systemadministratoren in Kliniken und
Pflegeeinrichtungen, die Open-Source-Software einsetzen wollen, aber keine
Zeit oder Expertise haben, einen Healthcare-konformen Stack von Grund auf
aufzubauen.

---

## Designprinzipien

**On-Premise by Design**
Linumed OS ist für den Betrieb in der eigenen Infrastruktur der Einrichtung
konzipiert. Es gibt keine Cloud-Abhängigkeit, kein Telemetrie-Callhome,
keine SaaS-Komponente. Alle Daten bleiben im Haus.

**DSGVO als Constraint, nicht als Feature**
Datenschutzanforderungen sind in jede Designentscheidung eingebaut:
Lokale Datenhaltung, verschlüsselte Backups, minimale Logging-Oberfläche,
kein Transfer personenbezogener Daten an Dritte.

**Idempotenz**
Alle Ansible-Playbooks sind idempotent. Ein zweiter Durchlauf produziert
keine Änderungen. Das ist eine harte Anforderung, keine Empfehlung.

**FOSS-only im Core**
Alle Komponenten von Linumed OS sind freie Open-Source-Software.
Linumed Shifts (kommerzielles Produkt) ist nicht Teil dieses Repos und
wird separat lizenziert.

**EU-Infrastruktur**
Keine Abhängigkeiten von US-only-Diensten. Image-Pulls von Docker Hub
sind akzeptiert, aber Images werden auf EU-Infrastruktur betrieben.
Für CI/CD werden EU-nahe Alternativen bevorzugt.

---

## Zielarchitektur (v0.1)

```
┌───────────────────────────────────────────────────────────┐
│                  Debian 13 (Bare Metal / VM)               │
│                                                             │
│  ┌──────────┐   ┌───────────────────────────────────────┐ │
│  │  Caddy   │   │              Docker Engine             │ │
│  │ (Proxy,  │   │                                         │ │
│  │  Container)  │  ┌─────────────┐  ┌───────────────────┐│ │
│  │  Port    │──▶│  │ BridgeLink  │  │ Prometheus         ││ │
│  │  80/443  │   │  │ + Postgres  │  │ Grafana (loopback) ││ │
│  └──────────┘   │  │  (loopback) │  │ Loki, Alertmanager ││ │
│                 │  └─────────────┘  │ Alloy, cAdvisor    ││ │
│  ┌──────────┐   │                   └───────────────────┘│ │
│  │  ufw     │   │                                         │ │
│  │ fail2ban │   └───────────────────────────────────────┘ │
│  │  SSH     │                                              │
│  └──────────┘   ┌───────────────────────────────────────┐ │
│                  │  Node Exporter (nativ, Debian-Paket)  │ │
│                  └───────────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  restic (Backup - encrypted, scheduled)               │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

---

## Komponenten

### common (Ansible Role)

Basis-Hardening des Debian-Systems. Wird immer als erstes ausgeführt.

Umfasst:
- SSH-Hardening (PasswordAuthentication off, Port konfigurierbar, AllowUsers)
- ufw Firewall (default deny incoming, nur explizit freigegebene Ports)
- fail2ban (SSH-Brute-Force-Schutz)
- unattended-upgrades (automatische Sicherheitsupdates)
- Zeitzone und NTP-Konfiguration
- Grundlegende Systempakete

### caddy (Ansible Role)

Caddy als Reverse Proxy mit automatischem TLS über ACME (Let's Encrypt oder
eigene CA), betrieben als Docker-Compose-Stack.

Konfiguration via Caddyfile, generiert aus Ansible-Templates.

Designentscheidung - Caddy als Container, nicht nativ auf dem Host:
Ursprünglich war geplant, Caddy nativ zu betreiben, damit TLS-Termination
einen Docker-Neustart übersteht. Geprüft (Stand 2026-08-10): Debian 13
liefert `caddy` in Version 2.6.2 mit 11 offenen Sicherheitsproblemen im
Debian-Security-Tracker, während der Container auf dem aktuellen
Upstream-Stand 2.11.x läuft. Für die am stärksten exponierte Komponente des
gesamten Stacks wäre "nativ" damit nicht sicherer, sondern messbar
unsicherer - der Patch-Kadenz-Vorteil, der nativ sonst rechtfertigen würde,
kehrt sich hier um. Das ursprüngliche Verfügbarkeitsargument trägt zudem
kaum: sind alle Backends selbst Container, liefert ein überlebender Caddy
ohne erreichbare Upstreams nur `502` statt `connection refused` - kein
praktischer Gewinn. Ein echter Notaus (z. B. bei einem Sicherheitsvorfall)
gehört als eigenes, dokumentiertes Verfahren auf Netzwerkebene (`ufw deny`,
Interface down) ins Betriebs-Runbook, nicht als Nebeneffekt der
Proxy-Platzierung.

Docker veröffentlicht Container-Ports an ufw vorbei (siehe Sicherheitskonzept
unten) - bei Caddy ist das für 80/443 gewollt, da der Proxy von außen
erreichbar sein muss. Jeder *weitere* `ports:`-Eintrag in diesem
Compose-Stack muss diese Falle bewusst berücksichtigen.

### bridgelink (Ansible Role)

HL7/FHIR-Integrationsengine, betrieben als Docker Compose Stack.
Eingesetzt wird **BridgeLink**.

Das ist kein Ersatz für Mirth Connect, sondern **dieselbe Codebasis unter
anderem Namen**: gleiches Kanal-XML, gleicher Administrator, gleiche
Transformer und Connectoren, die Java-Pakete heißen weiterhin
`com.mirth.connect`. NextGen Healthcare hat Mirth Connect im März 2025
auf eine rein kommerzielle, proprietäre Lizenz umgestellt (ab 4.6
Quellcode geschlossen); die Open-Source-Linie läuft seither unter neuen
Namen weiter, und Linumed OS folgt der offenen Linie. Mirth Connect
bleibt der De-facto-Standard der Branche — Kanäle sind zwischen allen
Varianten portabel, eine Einrichtung nimmt ihre Integrationsarbeit also
mit, falls sie später wechseln will.

Vollständige Begründung samt geprüfter Alternativen (Open Integration
Engine, lizenziertes Mirth 4.6+, eingefrorenes 4.5.2), eingehandelter
Nachteile und Revisionsauslöser:
[ADR 0001](docs/adr/0001-bridgelink-statt-mirth-connect.md).

Unterstützte Protokolle out-of-the-box: HL7 v2.x, FHIR R4, DICOM, CSV,
XML, Datenbank-Connectoren.

Docker Compose Stack:
- BridgeLink (gehärtetes Image: Debian 13, keine Shell, non-root)
- PostgreSQL (Konfigurations- und Nachrichtendatenbank)

Nur der Admin-/API-Port ist veröffentlicht, ausschließlich auf
`127.0.0.1`. Kanal-Ports (HL7-MLLP o. ä.) veröffentlicht die Rolle
bewusst nicht — das ist eine Entscheidung pro Standort.

### monitoring (Ansible Role)

Observability-Stack. Die meisten Komponenten laufen als Docker-Compose-Stack,
Node Exporter läuft nativ.

Komponenten:
- Prometheus - Metriken-Scraping und -Speicherung (Container)
- Grafana - Dashboards, drei vendorte Standard-Dashboards inklusive (Host-Übersicht,
  Container-Übersicht, Log-Explorer) - bewusst generisch für die Infrastruktur, nicht
  klinisch/patientenbezogen: der Monitoring-Stack sieht Metriken und Logs, keine
  Nachrichteninhalte der Integrationsengine; per Default nur auf `127.0.0.1` gebunden,
  Zugriff via SSH-Tunnel (Container)
- Loki - Log-Aggregation (Container)
- **Grafana Alloy** - Log-Shipping von Host und Containern nach Loki
  (Container). Ersetzt Promtail, das am 02.03.2026 End-of-Life ging und
  keine Sicherheitsfixes mehr erhält - für ein DSGVO-Kit keine Option.
- Alertmanager - Alert-Routing (Container)
- Node Exporter - Host-Metriken (CPU, RAM, Disk, Network). **Natives
  Debian-Paket** statt Container: bekommt Security-Updates automatisch über
  die bestehende unattended-upgrades-Rolle, braucht keine
  `--pid=host`-/rootfs-Mounts, und ufw kann den Port tatsächlich schützen -
  bei einem veröffentlichten Container-Port wäre das wirkungslos (siehe
  Sicherheitskonzept unten).
- cAdvisor - Container-Metriken (Container)

Retention ist nach Datenart getrennt, nicht ein einzelner globaler Wert:
Metriken (`monitoring_metrics_retention_days`, Default 90) und Logs
(`monitoring_logs_retention_days`, Default 30, kürzer) - Logs können
personenbezogene Daten enthalten (IP-Adressen, Benutzernamen), kürzere
Aufbewahrung ist hier Datenminimierung, keine Willkür.

### backup (Ansible Role)

Verschlüsselte Backups mit restic. Unterstützte Backends:
- Lokal (anderes Verzeichnis / externe Platte)
- SFTP (z.B. anderer Server im Netz)
- S3-kompatibel (optional, z.B. Hetzner Object Storage)

Backup-Schedule via systemd Timer (kein Cron). Monitoring-Integration:
restic-Ergebnisse werden als Metrics an Prometheus gepusht.

---

## Netzwerk-Design

**Entschieden, nicht offen:** Kein Verwaltungsdienst von Linumed OS ist von
außen erreichbar. Alle Komponenten binden an `127.0.0.1` oder veröffentlichen
gar keinen Host-Port; der Zugang läuft über einen SSH-Tunnel. Jeder
Compose-Stack hat sein eigenes, isoliertes Docker-Netzwerk.

Ein gemeinsames Netzwerk (`linumed-net`), über das Caddy die eigenen Dienste
routet, war ursprünglich als Zielbild vorgesehen und ist **bewusst verworfen**
worden — zusammen mit der SSO-Anbindung, die darauf aufgebaut hätte.
Begründung, geprüfte Alternativen (Reverse Proxy mit Identity Provider,
Mesh-VPN) und die eingehandelten Nachteile:
[ADR 0003](docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md).

```
Internet
   │
   ├── :80  ──▶ Caddy ──▶ redirect to HTTPS
   └── :443 ──▶ Caddy ──▶ Anwendungen des Betreibers
                          (Linumed OS selbst liegt nicht dahinter)

SSH-Tunnel (nicht öffentlich)
   ├── 127.0.0.1:3000 ──▶ Grafana
   ├── 127.0.0.1:9090 ──▶ Prometheus
   └── 127.0.0.1:8443 ──▶ BridgeLink Admin
```

Caddy ist der Reverse Proxy für die **Anwendungen der Einrichtung**, nicht für
die Verwaltungsoberflächen dieses Kits. Dass Caddy dabei einen Container in
einem anderen Compose-Stack heute noch nicht erreichen kann, ist eine offene
Lücke (Issue #39) und unabhängig von der Zugriffsentscheidung.

Weil alles auf Loopback gebunden bleibt, funktioniert Linumed OS über jedes
Netz, das der Betreiber ohnehin betreibt — Firmen-VPN, Mesh, Sprunghost oder
Klinik-LAN — ohne davon etwas wissen zu müssen. Diese Kombinierbarkeit ist der
Grund für die Entscheidung, nicht ihr Nebeneffekt.

---

## Storage-Strategie

Alle persistenten Daten liegen in benannten Docker Volumes (named volumes),
keine Bind-Mounts auf Host-Pfade außer explizit dokumentierten Ausnahmen.

| Service | Volume | Inhalt |
|---|---|---|
| bridgelink | bridgelink_appdata | Keystore, server.id, Laufzeitdaten |
| postgresql (BridgeLink) | bridgelink_db_data | Kanal-Konfiguration und Nachrichten |
| prometheus | prometheus-data | Metriken (Retention: 90 Tage default) |
| grafana | grafana-data | Dashboards, Nutzereinstellungen |
| loki | loki-data | Log-Daten (Retention: 30 Tage default, kürzer als Metriken - siehe monitoring-Rolle) |

Node Exporter hat kein eigenes Volume - läuft nativ, Host-Metriken werden
nicht persistiert (das übernimmt Prometheus).

restic sichert `/var/lib/docker/volumes/` per direktem Dateizugriff sowie
`/opt/linumed-os/` (Rollen-Konfiguration, Secrets). Backup läuft täglich
via systemd Timer. Das Ergebnis wird nicht an Prometheus gepusht, sondern
als Prometheus-Textfile-Metrik geschrieben (derselbe Mechanismus wie beim
nativen Node Exporter) - Prometheus holt es sich beim regulären Scrape ab,
kein Pushgateway nötig.

Recovery-Tests sind als dokumentierter Prozess vorgeschrieben
(DSGVO-Anforderung) - das manuelle Restore-Verfahren steht in
`docs/roles/backup.md`. Ein automatisiertes Test-Playbook ist für v0.1
nicht gebaut; das bleibt offen für eine spätere Version.

---

## Inventar-Struktur

```
ansible/inventory/
└── example/
    ├── hosts.yml          # Beispiel-Inventory (keine echten Hosts)
    └── group_vars/
        ├── all.yml        # Globale Variablen (Zeitzone, NTP etc.)
        └── linumed.yml    # Linumed-spezifische Defaults
```

Für echte Deployments legt der Administrator ein eigenes Inventory
außerhalb des Repos an und referenziert die Roles.

---

## Sicherheitskonzept

- Alle Verbindungen TLS-verschlüsselt (Caddy + ACME)
- SSH-Key-only, kein Passwort-Login
- Firewall default-deny, minimale Öffnung
- **Docker umgeht ufw**: ein per `ports:` veröffentlichter Container-Port ist
  trotz aktiver ufw-Regeln erreichbar (Dockers eigene iptables/nftables-Regeln
  liegen vor den ufw-Regeln in der Chain). Deshalb der Default in diesem Kit:
  nichts veröffentlichen, was nicht öffentlich erreichbar sein muss (Ausnahme
  Caddy auf 80/443, das ist gewollt) - alles andere entweder gar keinen
  Host-Port oder explizit auf `127.0.0.1` gebunden.
- Docker-Container ohne Privilegien, kein `--privileged`
- Secrets via Ansible Vault oder externe .env-Datei (nie im Repo). Passwörter,
  die ein Container zur Laufzeit braucht, gehen als Docker-Secret aus einer
  Datei hinein, nicht als Umgebungsvariable - Env-Variablen sind für jeden
  lesbar, der `docker inspect` ausführen darf, und landen in der
  Container-Config auf der Platte.
- **Ab der bridgelink-Rolle verarbeitet der Stack echte Patientendaten.**
  Bis dahin enthält er nur Betriebsdaten (Metriken, Logs); eine
  Integrationsengine bewegt dagegen HL7-Nachrichten mit Namen, Geburtsdaten
  und Diagnosen, und ihre Datenbank speichert sie je nach Kanal-Einstellung.
  Das verschiebt die Anforderungen an Backup (Rolle `backup`), Aufbewahrung
  und Zugriffskontrolle von "Infrastruktur sichern" zu "Gesundheitsdaten
  verarbeiten" - siehe `docs/roles/bridgelink.md`, Abschnitt DSGVO.
- Backup-Daten verschlüsselt (restic + Passwort via Vault)
- Automatische Sicherheitsupdates für das Host-System (unattended-upgrades
  deckt auch nativ installierte Pakete wie Node Exporter ab, nicht nur
  Container-Images)

---

## Abgrenzung: Linumed OS vs. Linumed Shifts

| | Linumed OS | Linumed Shifts |
|---|---|---|
| Typ | Open Source IaC-Kit | Kommerzielle SaaS-Anwendung |
| Lizenz | MIT | Proprietär |
| Inhalt | Infra-Stack, Integrationsengine, Monitoring | Dienstplanung für Pflegestationen |
| Repo | linumed/linumed-os | linumed/shifts (privat) |
| Zielgruppe | IT-Admins, Systemintegratoren | PDL, Stationsleitung, Pflegekräfte |
| Abhängigkeit | unabhängig | kann auf Linumed OS betrieben werden |

Linumed Shifts ist nicht in diesem Repository und wird nicht hier
dokumentiert.

---

## Versionsstrategie

- v0.1: common + docker + caddy + monitoring + bridgelink + backup
- v0.2: Betriebsreife — funktionierender Einstieg, Betriebshandbuch,
  Zugriffshärtung (Tunnel-Nutzer ohne Shell, echte Grafana-Benutzer),
  automatisierter Restore-Test. Siehe `docs/ROADMAP.md`.
- v0.3: DICOM-Stack (Orthanc)
- v1.0: Vollständige Dokumentation, CI-getestete Rollen, Zertifizierungsvorbereitung

**Kein mitgelieferter Identity Provider.** Die ursprünglich für v0.2 geplante
Authentik-Rolle ist verworfen ([ADR 0003](docs/adr/0003-loopback-only-access-no-bundled-identity-provider.md)):
Sie hätte eine Öffnung nach außen vorausgesetzt, die dieses Kit bewusst
vermeidet. Statt einen Identity Provider mitzuliefern, wird Grafana optional an
einen **vorhandenen** angeschlossen (OIDC). Linumed Passpin bleibt davon
unberührt — es ist ein eigenständiges Produkt und wird nicht in diesem
Repository entwickelt.

Anwendungssoftware (KIS, DMS, Dokumentenablage) ist bewusst nicht Teil von
Linumed OS. Die Klinik betreibt ihre eigenen Anwendungen. Linumed OS
liefert den sicheren, DSGVO-konformen Unterbau.

Alle Releases werden als Git Tags gesetzt. Breaking Changes erst ab v1.0.
