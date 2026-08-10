# bridgelink: HL7/FHIR-Integrationsengine

## Problem

Klinische Systeme sprechen HL7 v2, FHIR, DICOM und eine Menge hausgemachter Formate
miteinander. Eine Integrationsengine nimmt Nachrichten entgegen, transformiert sie und
leitet sie weiter — sie ist das Bindeglied zwischen KIS, LIS, PACS und allem anderen.
Diese Rolle stellt **BridgeLink** samt PostgreSQL-Backend als Docker-Compose-Stack bereit.

## Warum BridgeLink und nicht Mirth Connect

Ursprünglich war Mirth Connect geplant. Das geht nicht mehr: NextGen Healthcare hat
Mirth Connect im **März 2025 auf eine rein kommerzielle, proprietäre Lizenz umgestellt**,
ab Version 4.6 ist der Quellcode geschlossen. Das kollidiert mit der FOSS-Vorgabe dieses
Repos. Die letzte MPL-2.0-Version 4.5.2 ist eingefroren und bekommt keine
Sicherheitsfixes mehr — sie einzusetzen wäre derselbe Fehler, für den Promtail aus der
monitoring-Rolle geflogen ist.

BridgeLink ist ein **MPL-2.0-Fork** des letzten quelloffenen Mirth-Standes, gepflegt von
Innovar Healthcare. Die Alternative Open Integration Engine (OIE) hat die bessere
Governance (herstellerneutral, Non-Profit-Steering-Committee), veröffentlicht aber
derzeit kein Container-Image für ihre aktuelle Version — ausführliche Abwägung in
`ansible/roles/bridgelink/README.md`.

## Variablen

Alle Variablen haben den Präfix `bridgelink_*` und stehen in
`ansible/roles/bridgelink/defaults/main.yml`.

| Variable | Default | Bedeutung |
|---|---|---|
| `bridgelink_image` | `innovarhealthcare/bridgelink:26.6.0-dhi-slim` | Gehärtetes Image (Debian 13, keine Shell, non-root UID 65532) |
| `bridgelink_postgres_image` | `postgres:17.10-alpine` | Backend-Datenbank |
| `bridgelink_admin_port` | `8443` | Nur auf `127.0.0.1` gebunden — Zugriff per SSH-Tunnel |
| `bridgelink_db_password` | `""` (Pflicht) | Ohne Wert bricht die Rolle im Preflight ab |
| `bridgelink_keystore_storepass` | `""` (Pflicht) | Keystore-Passwort — **nach dem ersten Start nicht mehr ändern** |
| `bridgelink_keystore_keypass` | `""` (Pflicht) | Schlüssel-Passwort im Keystore — dito |
| `bridgelink_server_id` | `""` (Pflicht) | Einmal per `uuidgen` erzeugen und dauerhaft stabil halten |
| `bridgelink_max_heap_mb` | `512` | JVM-Maximalheap |
| `bridgelink_stop_grace_period` | `35` | Sekunden bis zum harten Kill — bewusst über Dockers 10s-Default |

Die vier Pflichtwerte gehören in **Ansible Vault**, nie im Klartext in ein eingechecktes
Inventory.

## Was wird verändert

- `{{ bridgelink_deploy_dir }}/docker-compose.yml`
- `{{ bridgelink_deploy_dir }}/secrets/` (0700, root) mit `mirth.properties` und
  `db_password` — die Passwortdateien liegen im Klartext, so funktionieren Docker-Secrets
  aus Dateien. `mirth.properties` gehört UID 65532 (0400), sonst kann der gehärtete
  Container sie nicht lesen.
- Container `linumed-os-bridgelink` und `linumed-os-bridgelink-db`, Volumes für Appdata,
  Custom-Extensions und Datenbank.

## Zugriff

```bash
ssh -L 8443:127.0.0.1:8443 <user>@<host>
# dann: https://localhost:8443
```

Das Zertifikat ist selbstsigniert (BridgeLink erzeugt beim ersten Start einen eigenen
Keystore) — die Browser-Warnung ist hier erwartbar, der Kanal läuft ohnehin schon durch
den SSH-Tunnel.

Für die Administration gibt es den separaten **Administrator-Launcher** (ebenfalls
MPL-2.0) oder **WebAdmin** als eigenen Container. Das gewählte `-slim`-Image enthält den
alten Swing-Client bewusst nicht mehr.

## Verifikation

Der Container-Status allein sagt hier **nichts** aus (siehe Stolperfallen). Was zählt:

```bash
# Engine antwortet wirklich - liefert die Versionsnummer
curl -sk -H 'X-Requested-With: check' https://127.0.0.1:8443/api/server/version

# Datenbank-Backend gesund
docker inspect linumed-os-bridgelink-db --format '{{ "{{" }}.State.Health.Status{{ "}}" }}'

# Läuft die Engine wirklich gegen PostgreSQL (nicht gegen die eingebaute Derby-DB)?
docker logs linumed-os-bridgelink 2>&1 | grep -i "postgres"
```

Die Rolle führt den ersten Check nach dem Deployment selbst aus und bricht ab, wenn die
Engine nicht innerhalb von fünf Minuten antwortet.

## Stolperfallen

- **„Container läuft" heißt hier nicht „Engine läuft".** Das gehärtete Image kann keinen
  Healthcheck haben (keine Shell, kein `wget`/`curl` im Image — dieselbe Lage wie bei
  Loki). Docker Compose betrachtet einen Container ohne Healthcheck als fertig, sobald er
  läuft — eine Engine, die beim Start abbricht und in einer Restart-Schleife hängt, sieht
  damit wie ein erfolgreiches Deployment aus. Genau das ist beim Bau dieser Rolle
  passiert. Deshalb prüft die Rolle die API, nicht den Container-Status.
- **Keystore-Passwörter nach dem ersten Start nicht ändern.** BridgeLink erzeugt beim
  ersten Start einen Keystore und verschlüsselt ihn mit diesen Passwörtern. Werden sie
  später geändert, ist der bestehende Keystore nicht mehr lesbar.
- **`bridgelink_server_id` stabil halten.** Ändert sich die ID, hält BridgeLink sich für
  einen anderen Server. Deshalb explizit als Variable gesetzt und nicht dem Volume
  überlassen.
- **Kanal-Ports werden von dieser Rolle nicht veröffentlicht.** Ein HL7-MLLP-Listener
  braucht einen von außen erreichbaren Port — das ist eine bewusste Entscheidung pro
  Standort mit echten Sicherheitsfolgen, und ein veröffentlichter Container-Port umgeht
  ufw komplett (siehe `docs/roles/common-ufw.md`). Wer Kanäle nach außen öffnet, muss das
  selbst tun und absichern.
- **Passwörter stehen absichtlich nicht in Umgebungsvariablen.** Env-Variablen sind für
  jeden lesbar, der `docker inspect` ausführen darf, und landen in der Container-Config
  auf der Platte. Deshalb Docker-Secrets aus Dateien.

## DSGVO

Anders als die übrigen Rollen dieses Repos verarbeitet eine Integrationsengine im
Regelbetrieb **echte Patientendaten** — HL7-Nachrichten enthalten Namen, Geburtsdaten,
Diagnosen. Das hat Folgen, die über die Rolle hinausgehen:

- **Message-Storage ist per Kanal einstellbar.** BridgeLink speichert Nachrichten
  standardmäßig zur Fehlersuche. Wie lange und in welchem Umfang, gehört pro Kanal
  bewusst entschieden (Storage-Modus, Pruning) — das ist Datenminimierung und nicht
  Voreinstellungssache. Diese Rolle liefert eine leere Engine, die Kanäle und deren
  Aufbewahrung sind die Integrationsarbeit der Einrichtung.
- **Die Datenbank enthält damit potenziell Patientendaten.** Beim Backup (Rolle `backup`,
  #7) ist das der Unterschied zwischen „Infrastruktur sichern" und „Gesundheitsdaten
  verarbeiten" — Verschlüsselung und Aufbewahrung entsprechend planen.
- **Kein Kanal ist vorkonfiguriert**, es fließen also nach dem Deployment zunächst keine
  Daten. Erst mit dem ersten Kanal beginnt die Verarbeitung.
