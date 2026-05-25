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
┌─────────────────────────────────────────────────────┐
│                  Debian 13 (Bare Metal / VM)         │
│                                                     │
│  ┌──────────┐   ┌─────────────────────────────────┐ │
│  │  Caddy   │   │        Docker Engine             │ │
│  │ (Proxy)  │   │                                  │ │
│  │  Port    │   │  ┌─────────────┐  ┌───────────┐  │ │
│  │  80/443  │──▶│  │    Mirth    │  │ Prometheus │  │ │
│  └──────────┘   │  │  Connect   │  │  Grafana   │  │ │
│                 │  │ Port 8080  │  │    Loki    │  │ │
│  ┌──────────┐   │  └─────────────┘  └───────────┘  │ │
│  │  ufw     │   │                                  │ │
│  │ fail2ban │   │  ┌─────────────────────────────┐  │ │
│  │  SSH     │   │  │      Node Exporter           │  │ │
│  └──────────┘   │  └─────────────────────────────┘  │ │
│                 └─────────────────────────────────┘ │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  restic (Backup - encrypted, scheduled)      │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
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
eigene CA). Läuft direkt auf dem Host, nicht in Docker, um TLS-Termination
vor allen Services zu ermöglichen.

Konfiguration via Caddyfile, generiert aus Ansible-Templates.

Designentscheidung - Caddy auf dem Host, nicht in Docker:
Caddy läuft bewusst nativ auf dem Host und nicht als Container. Begründung:
TLS-Termination erfolgt vor der Docker-Schicht - wenn Docker crasht oder
neu gestartet wird, bleibt der Reverse Proxy erreichbar. Das ist eine
bewusste Sicherheits- und Stabilitätsentscheidung, keine Inkonsistenz.
Diese Entscheidung ist final und wird in zukünftigen Versionen nicht geändert.

### mirth-connect (Ansible Role)

Mirth Connect als HL7/FHIR-Integrationsengine, betrieben als Docker
Compose Stack. Mirth Connect ist der De-facto-Standard für Healthcare-
Datenintegration in DACH-Einrichtungen.

Unterstützte Protokolle out-of-the-box: HL7 v2.x, FHIR R4, DICOM, CSV,
XML, Datenbank-Connectoren.

Docker Compose Stack:
- mirth-connect (NextGen Connect, aktueller Stable-Tag)
- PostgreSQL (Konfigurationsdatenbank für Mirth)

### monitoring (Ansible Role)

Vollständiger Observability-Stack, betrieben als Docker Compose Stack.

Komponenten:
- Prometheus - Metriken-Scraping und -Speicherung
- Grafana - Dashboards (vorbereitete Healthcare-Dashboards inklusive)
- Loki - Log-Aggregation
- Promtail - Log-Shipping von Host und Containern nach Loki
- Node Exporter - Host-Metriken (CPU, RAM, Disk, Network)
- cAdvisor - Container-Metriken

Retention konfigurierbar über Variable `monitoring_retention_days` (Default: 90).

### backup (Ansible Role)

Verschlüsselte Backups mit restic. Unterstützte Backends:
- Lokal (anderes Verzeichnis / externe Platte)
- SFTP (z.B. anderer Server im Netz)
- S3-kompatibel (optional, z.B. Hetzner Object Storage)

Backup-Schedule via systemd Timer (kein Cron). Monitoring-Integration:
restic-Ergebnisse werden als Metrics an Prometheus gepusht.

---

## Netzwerk-Design

Alle Services laufen in einem internen Docker-Netzwerk (`linumed-net`).
Von außen sind nur die Ports 80 und 443 (Caddy) erreichbar sowie der
SSH-Port. Caddy routet anhand von Hostnamen oder Pfaden zu den jeweiligen
Services.

```
Internet
   │
   ├── :80  ──▶ Caddy ──▶ redirect to HTTPS
   └── :443 ──▶ Caddy ──▶ /mirth      ──▶ mirth-connect:8080
                       ──▶ /grafana   ──▶ grafana:3000
                       ──▶ /prometheus──▶ prometheus:9090 (intern only)
```

Prometheus und interne Metrics-Endpoints sind nur über Caddy mit
Authentifizierung erreichbar, nicht direkt.

---

## Storage-Strategie

Alle persistenten Daten liegen in benannten Docker Volumes (named volumes),
keine Bind-Mounts auf Host-Pfade außer explizit dokumentierten Ausnahmen.

| Service | Volume | Inhalt |
|---|---|---|
| mirth-connect | mirth-appdata | Kanal-Konfiguration, Logs |
| postgresql (Mirth) | mirth-postgres-data | Mirth-Konfigurationsdatenbank |
| prometheus | prometheus-data | Metriken (Retention: 90 Tage default) |
| grafana | grafana-data | Dashboards, Nutzereinstellungen |
| loki | loki-data | Log-Daten (Retention: 90 Tage default) |

restic sichert die Volume-Daten via docker-volume-backup oder direktem
Zugriff auf den Volume-Pfad unter /var/lib/docker/volumes/. Backup läuft
täglich via systemd Timer, Ergebnis wird als Metrik an Prometheus gepusht.

Recovery-Tests sind als dokumentierter Prozess vorgeschrieben (DSGVO-Anforderung).
Das Playbook backup-restore-test.yml stellt dafür eine Testumgebung bereit.

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
- Docker-Container ohne Privilegien, kein `--privileged`
- Secrets via Ansible Vault oder externe .env-Datei (nie im Repo)
- Backup-Daten verschlüsselt (restic + Passwort via Vault)
- Automatische Sicherheitsupdates für das Host-System

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

- v0.1: common + caddy + monitoring + mirth-connect + backup
- v0.2: SSO-Integration via Authentik (optionale Role) - Übergangslösung bis
  Linumed Passpin produktionsreif ist; Authentik deckt OIDC, SAML, LDAP-Sync
- v0.3: DICOM-Stack (Orthanc)
- v1.0: Vollständige Dokumentation, CI-getestete Rollen, Zertifizierungsvorbereitung

Langfristig ersetzt Linumed Passpin die Authentik-Role als native Identitäts-
und Secrets-Schicht. Passpin ist ein eigenständiges Linumed-Produkt und wird
nicht in diesem Repository entwickelt.

Anwendungssoftware (KIS, DMS, Dokumentenablage) ist bewusst nicht Teil von
Linumed OS. Die Klinik betreibt ihre eigenen Anwendungen. Linumed OS
liefert den sicheren, DSGVO-konformen Unterbau.

Alle Releases werden als Git Tags gesetzt. Breaking Changes erst ab v1.0.
