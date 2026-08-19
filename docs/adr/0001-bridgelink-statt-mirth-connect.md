# ADR 0001: BridgeLink statt Mirth Connect als Integrationsengine

**Status:** angenommen · **Datum:** 2026-08-11 · **Betrifft:** `ansible/roles/bridgelink`, Issue #12

## Die Frage, die hier beantwortet wird

Mirth Connect ist der De-facto-Standard für Healthcare-Datenintegration im
DACH-Raum. Wer sich in Kliniken umsieht, findet Mirth oder das kommerzielle
Orchestra — sonst wenig. Linumed Base liefert die Engine trotzdem nicht als
„Mirth Connect" aus, sondern als **BridgeLink**. Das ist erklärungsbedürftig,
und genau darum geht es hier.

## Vorweg: BridgeLink ist kein anderes Produkt

Das wichtigste Missverständnis zuerst. BridgeLink ist **derselbe Codestand unter
anderem Namen**, kein Ersatzprodukt:

- gleiches Kanal-XML-Format, Kanäle sind in beide Richtungen exportierbar
- gleicher Administrator, gleiche JavaScript-Transformer, gleiche Connector-Typen
- die Java-Pakete heißen weiterhin `com.mirth.connect`

Der Serverstart im laufenden Container protokolliert wörtlich:

```
com.mirth.connect.server.Mirth: BridgeLink 26.6.0 (Built on July 17, 2026)
server successfully started.
```

Wer Mirth kann, kann BridgeLink. Der Umstieg auf Orchestra, Apache NiFi oder Camel
wäre ein Produktwechsel — dies hier ist keiner. Die zutreffende Beschreibung lautet:
**NextGen hat die Quelle geschlossen, die Open-Source-Linie läuft unter neuen Namen
weiter, und wir folgen der offenen Linie.**

## Kontext

NextGen Healthcare hat im **März 2025** das Lizenzmodell von Mirth Connect
umgestellt: von einer Doppellizenz (MPL 2.0 + kommerziell) auf **rein kommerziell
und proprietär**. Ab Version 4.6 ist der Quellcode nicht mehr öffentlich. Letzte
MPL-2.0-Version ist **4.5.2**; diese Lizenz kann rückwirkend nicht entzogen werden,
die Version bekommt aber keine Sicherheitsfixes mehr.

Branchenberichten zufolge betrifft das rund 15.000 Organisationen weltweit.
Innerhalb weniger Wochen entstanden zwei Forks des letzten quelloffenen Standes,
beide unter MPL 2.0.

Für Linumed Base kollidiert das mit zwei festgeschriebenen Grundsätzen:

- **FOSS-only im Core** (`CONVENTIONS.md`, `ARCHITECTURE.md`): keine kommerzielle
  Software, keine proprietären Lizenzen.
- **Linumed Base ist der kostenlose Unterbau.** Eine Pflicht zur kommerziellen
  Lizenz für die zentrale Komponente würde den Zweck des Kits aushebeln.

Hinzu kommt: Eine Integrationsengine bewegt echte Patientendaten. Eine eingefrorene
Version ohne Sicherheitsfixes ist dort nicht vertretbar — dasselbe Argument, mit dem
im Monitoring-Stack Promtail (EOL 02.03.2026) durch Grafana Alloy ersetzt wurde.

## Geprüfte Optionen

### A) Mirth Connect 4.6+ mit kommerzieller Lizenz

Verletzt FOSS-only direkt und macht das Kit lizenzpflichtig. Praktisch außerdem:
Für 4.6+ gibt es **kein öffentliches Container-Image** — `nextgenhealthcare/connect`
auf Docker Hub endet bei 4.5.2 (Oktober 2024). Ausgeschlossen.

### B) Mirth Connect 4.5.2 (letzte MPL-Version) einfrieren

Lizenzrechtlich sauber, aber ohne Sicherheitsfixes und ohne Perspektive. Für ein
System, das Gesundheitsdaten verarbeitet, nicht verantwortbar. Ausgeschlossen aus
demselben Grund wie Promtail.

### C) Open Integration Engine (OIE)

Herstellerneutraler Fork, verwaltet von einem Non-Profit-Steering-Committee mit
Maintainern aus mehreren Firmen — **die bessere Governance**, und exakt die
Struktur, die eine Wiederholung des NextGen-Falls verhindern soll. Aktuelle Version
4.6.0 (Java 17, 24 behobene CVEs), MPL 2.0.

Gescheitert an einem praktischen Punkt: **kein Container-Image für die aktuelle
Version.** Auf Docker Hub liegt nur 4.5.2 vom August 2025, also genau die
CVE-Belastung aus Option B. Ein Image selbst zu bauen ist technisch machbar (das
offizielle Dockerfile ist sauber parametrisiert, Tarball und SHA256 sind
veröffentlicht), verlagert aber Build und Pflege auf jeden Betreiber — für
IT-Dienstleister ohne eigene Registry unpraktisch.

### D) BridgeLink — gewählt

MPL-2.0-Fork von Innovar Healthcare. Aktuelle Version 26.6.0, Container-Images
werden zu jedem Release veröffentlicht und sind tagesaktuell. Gewählt wird die
Variante `26.6.0-dhi-slim`: Docker Hardened Image auf **Debian 13** (dieselbe Basis,
die dieses Repo ohnehin voraussetzt), ohne Shell und Paketmanager, non-root
UID 65532, mit Trivy-Gate auf behebbare HIGH/CRITICAL-Findings in der CI.

## Entscheidung

**BridgeLink 26.6.0 (`-dhi-slim`) mit PostgreSQL als Backend.**

Ausschlaggebend war nicht, dass BridgeLink das bessere Projekt wäre — bei der
Governance liegt OIE vorn. Ausschlaggebend war, dass BridgeLink als einzige Option
gleichzeitig quelloffen, aktuell gepatcht **und** ohne Eigenbau deploybar ist.

## Konsequenzen

### Was wir uns einhandeln

- **Beschaffungs- und Wahrnehmungsreibung.** „Mirth Connect" steht in Lastenheften,
  Ausschreibungen, Wartungsverträgen und Lebensläufen; „BridgeLink" nicht. Wer
  Linumed Base anbietet, muss die Frage „warum nicht Mirth?" beantworten können —
  dieses Dokument ist die Antwort und darf zitiert werden.
- **Ökosystem.** Kommerzielle Mirth-Erweiterungen und NextGen-Supportverträge zielen
  auf NextGens Produkt, nicht auf Forks.
- **Einzelner Hersteller.** BridgeLink wird von einer Firma geführt. MPL 2.0 kann
  rückwirkend nicht entzogen werden, künftige Versionen theoretisch schon — dann
  gäbe es erneut einen Fork. Das ist genau das Risiko, das OIEs Governance
  adressiert, und der Hauptgrund, diese Entscheidung offen zu halten.
- **Zwei konkurrierende Forks** könnten die Community fragmentieren. Historisch
  konsolidieren sich solche Spaltungen meist auf einen Gewinner (OpenTofu,
  OpenSearch, Valkey), garantiert ist das nicht.

### Was uns nicht bindet

**Kanal-Portabilität ist der belastbare Ausweg**, nicht die Image-Variable. Kanäle,
Code-Templates und Transformer lassen sich zwischen allen drei Varianten
exportieren und importieren, weil alle denselben Codestand teilen. Eine Einrichtung,
die später auf lizenziertes Mirth Connect oder auf OIE wechseln will, nimmt ihre
Integrationsarbeit mit — das ist der eigentliche Wert, und er bleibt erhalten.

`bridgelink_image` ist ebenfalls eine Variable, aber ein Wechsel des Images ist
**nicht getestet und nicht garantiert**: Die Container-Konventionen (`MP_*`-Variablen,
`mirth_properties`-Secret) stammen zwar alle aus NextGens ursprünglichem
`connect-docker`, die Installationspfade unterscheiden sich aber
(`/opt/bridgelink` vs. `/opt/connect`), und für lizenzierte 4.6+-Images ist uns die
Distributionsform nicht bekannt. Wer diesen Weg gehen will, muss ihn gegen seine
eigene Lizenz-Distribution verifizieren.

### Wann diese Entscheidung neu zu prüfen ist

- **OIE veröffentlicht Container-Images für aktuelle Versionen.** Dann entfällt der
  einzige Grund, der gegen OIE sprach, und die bessere Governance gibt den Ausschlag.
  Upstream verfolgt unter `OpenIntegrationEngine/engine#40`.
- **BridgeLink ändert Lizenz oder Pflegezustand.**
- **Die Forks konsolidieren sich** auf einen gemeinsamen Nachfolger.

## Quellen

- [NextGen: A New Era for Mirth Connect](https://www.nextgen.com/blog/industry-news/a-new-era-for-mirth-connect-by-nextgen-healthcare)
- [Open Integration Engine](https://openintegrationengine.org/) · [engine#40 „Create OIE Docker Image"](https://github.com/OpenIntegrationEngine/engine/issues/40)
- [BridgeLink Container-Repo](https://github.com/Innovar-Healthcare/bridgelink-container) (MPL-2.0)
- [OIE vs BridgeLink vs Mirth Connect — Vergleich](https://saga-it.com/blog/oie-vs-bridgelink-vs-mirth-connect)
