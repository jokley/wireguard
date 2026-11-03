# Entwicklungs-, Test- und Projektkonventionen

Diese Grundlage schafft keine konkreten TEST-Stacks, Pi-Projekte, Testdomains,
Datenbanken, SSH-Keys oder Deployment-Automatisierung.

## Zwei Arbeitsmodelle

### Server-, Web- und Docker-Projekte

```text
feature/dev branch → Code-Server LOCAL/DEV → separater TEST/QA-Docker-Stack
                  → PR / main → kontrolliertes separates PROD-Deployment
```

Code-Server ist der lokale Entwicklungsrechner im Rechenzentrum: Editor, Codex,
Terminal, Git commit/push, Unit Tests, lokale Backend-/Frontend-Prozesse,
Hot Reload und Debugger/Breakpoints. Er kann TEST-Dienste und TEST-Datenbanken
über dev-net erreichen. DEV ist kein zwingender Docker-Stack. Lokale Prozesse
sind keine zusätzlichen öffentlichen Host-Portfreigaben; eine spätere Vorschau
braucht einen separat geprüften Zugriffsweg.

TEST/QA ist die erste vollständige Container-Landschaft für Integration,
Reverse-Proxy-/Auth-Verhalten, Datenbank, Migrationen sowie Browser- und
Workflow-Tests. PROD ist ein eigenständiger Stack und wird nur kontrolliert aus
main ausgerollt. Ein Git-Push verändert niemals automatisch PROD.

Git, Python, Node.js, pnpm, PostgreSQL-Client und Debugger-Unterstützung können
später passend zu Projekten im Code-Image ergänzt werden. Diese Grundlage
installiert keine zusätzlichen Toolchains und behauptet nicht, alle seien
bereits vorhanden. Keine projektbezogenen DB-Credentials in das Image einbauen.

### Pi- und Device-Projekte

```text
Code-Server → SSH über ops-net / WireGuard → DEV-Pi → QA-Pi → PROD-Pi
```

Code-Server ist Editor, Codex-Arbeitsplatz, Terminal und SSH-Ausgangspunkt.
Die Laufzeitumgebungen sind die Geräte selbst; eine lokale Nachbildung im
Code-Server ist nicht gefordert. DEV/QA werden später explizit per SSH gewählt,
PROD separat kontrolliert. Die bestehende Route
`100.64.0.0/24 via 172.30.90.2` bleibt erhalten. Kein konkretes Gerät wird hier
konfiguriert und es werden keine Schlüssel erzeugt.

## Projekte und Environments

| Aspekt | PROD | TEST/QA |
| --- | --- | --- |
| Verzeichnis | `/home/Projects/<project>/prod` | `/home/Projects/<project>/test` |
| Compose-Projekt | `<project>-prod` | `<project>-test` |
| Container | `<project>-prod-<service>` | `<project>-test-<service>` |
| eigenes Netz | `<project>-prod-net` | `<project>-test-net` |
| Domain | `<project>.jokley.at` | `test.<project>.jokley.at` |
| zentrale Netze | optional edge-net, niemals automatisch dev-net | dev-net, optional edge-net |

Kleine private Projekte dürfen nur `prod/` besitzen. DEV bedeutet normalerweise
Git-Branch, Workspace und lokale Prozesse im Code-Server. TEST/PROD benötigen
getrennte Checkouts/Arbeitsverzeichnisse und persistente Daten; kein gemeinsames
beschreibbares Datenverzeichnis. Die Workspace-Strategie wird pro Projekt später
festgelegt; dieser PR ändert keine bestehenden Mounts.

TEST bekommt ein eigenes Test-Netz und verbindet nur benötigte Dienste mit
dev-net; eine Datenbank nicht unnötig mit edge-net verbinden. Ein privates
DB-Netz kann `internal: true` verwenden. PROD erhält sein eigenes Prod-Netz.
Alle Konsumenten von dev-net deklarieren es mit `external: true` und `name: dev-net`.
Kein Projekt übernimmt dessen IPAM oder Ownership von `infra/dev`.

Der zentrale Edge bleibt der einzige öffentliche Reverse Proxy. Künftig z.B.
`incoming.jokley.at` → PROD und `test.incoming.jokley.at` → TEST, beide über den
bestehenden Edge. TEST-Domains standardmäßig hinter Authelia. Kein zweiter
TEST-Edge, keine neuen Nginx-Routen, DNS-Einträge oder Zertifikate in diesem PR.

## Datenbanken: Konvention, keine Implementierung

| Modus | Verwendung |
| --- | --- |
| `none` | Projekt ohne Datenbankabhängigkeit |
| `prod-readonly` | ausdrücklich freigegebener Diagnose-Sonderfall mit eigener Read-only-Rolle |
| `dedicated` | getrennte TEST-DB; bevorzugter TEST-Standard für zustandsbehaftete Anwendungen wie Incoming |
| `snapshot` | kontrolliert befüllte separate TEST-DB aus einem PROD-Backup |

TEST erhält standardmäßig weder PROD-DB-Credentials noch direkten Zugriff auf
PROD-DB-Netze. `prod-readonly` ist keine reguläre TEST-Abhängigkeit. Eine
Ausnahme erfordert explizite Freigabe, begrenzten Netzpfad und minimale Rechte.

```text
PROD-Backup → getrennte TEST-DB → Restore → ggf. Anonymisierung/Pseudonymisierung
            → Migrationen → TEST
```

Backups mit personenbezogenen Daten dürfen nicht unkontrolliert in TEST landen.
Freigabe, Zugriffsschutz und erforderliche Aufbereitung müssen schon vor dem
Restore geklärt sein; Rohdaten bis zur Aufbereitung isolieren. Keine Verbindung
von TEST zu einer produktiven Datenbank als Ersatz für einen Snapshot.

## Zukünftige SSH-Einbindung

Hostseitige, gitignored Dateien außerhalb des freigegebenen Projekt-Workspaces
halten: etwa `infra/code/runtime/ssh/` für geprüfte Config und Private-Keys,
`infra/code/state/ssh/` für bekannte Hostschlüssel. Das Stack-Gitignore schließt
diese Verzeichnisse aus. Es werden jetzt keine Dateien oder Mounts angelegt.

Später Config und Schlüssel gezielt read-only in ein separates Verzeichnis wie
`/etc/code-ssh/` mounten, nicht pauschal ein schreibbares komplettes `.ssh` mit
Keys. Die Config kann dortige absolute `IdentityFile`-Pfade verwenden und einen
separaten `UserKnownHostsFile` unter `/home/coder/.ssh/known_hosts` festlegen.
Die separate Config später explizit mit `ssh -F /etc/code-ssh/config` auswählen
oder aus einer kontrollierten Benutzer-Config einbinden.
`known_hosts` bekommt separat einen kontrollierten schreibbaren Bind-Mount bzw.
ein eigenes Verzeichnis. Zielhost-Fingerprints vorab über einen vertrauenswürdigen
Kanal prüfen; `StrictHostKeyChecking` nicht global abschalten.

UID/GID 1000, restriktive Host-Dateirechte und für coder lesbare Key-Dateien
prüfen. Eine root-eigene read-only SSH-Config darf nicht für andere beschreibbar
sein. Keine Keys ins Image oder Git, keine automatischen PROD-Zugänge. Ein
read-only Key-Mount verhindert keine Nutzung oder Kopie durch einen kompromittierten
Code-Server; Zugriff auf DEV/QA und später PROD deshalb getrennt begrenzen.

## Deployment-Grenze

Code-Server bleibt ohne `/var/run/docker.sock`, Docker-in-Docker, Host-Docker-
Zugriff, privilegierten Containerzugriff oder Deployment-Rechte. Er darf Code
ändern, Codex verwenden, lokal testen, Git commit/push und TEST-Dienste erreichen.
Builds, Starts, Restarts und Deployments laufen später über einen separaten,
authentifizierten Prozess mit Projekt-/Environment-Allowlist und Auditierung.
Kein beliebiger Docker-/Shell-Durchgriff oder Secrets-Zugriff aus Code-Server.

Langfristige Schnittstelle, hier nicht implementiert:

```text
projectctl deploy <project> test
projectctl logs <project> test
projectctl status <project> test
```

PROD bekommt eine separate, restriktivere Freigabe und ausschließlich main als
Deployment-Quelle. Git-Push und Runtime-Aktivierung bleiben getrennte Schritte.

## Netzgrenzen und zukünftige Firewallregeln

`dev-net` ist ein gemeinsames Entwicklungsnetz, keine Sicherheitsgrenze zwischen
gegenseitig nicht vertrauenswürdigen TEST-Projekten. Bei Bedarf später je Projekt
stärker segmentieren. TEST hängt typischerweise an dev-net, eigenem test-net und
optional edge-net; niemals automatisch an ops-net oder einem Prod-DB-Netz.
Code-Server hängt zusätzlich an ops-net und edge-net, weil dies seine bestehende
Admin-Funktion benötigt. Diese Mehrfachanbindung macht ihn nicht automatisch zum
Router. Keine zusätzlichen Forwarding-/NAT-Regeln oder Proxy-/Tunnel-Dienste
für TEST in Code-Server einrichten. Ein kompromittierter Code-Server kann dennoch
seine eigenen Admin-Verbindungen benutzen; die Netze allein verhindern das nicht.

Zukünftig sind hostseitige Regeln sinnvoll, die vor Docker-Freigaben greifen:
beim iptables-Backend typischerweise in `DOCKER-USER`, beim nativen nftables-
Backend über dessen passende Forward-Hooks/Prioritäten (keine DOCKER-USER-Kette
voraussetzen). Backend und Docker-Version vor Umsetzung feststellen.

Regelmodell: zustandsbezogene Antwortpakete zulassen; neue Verbindungen aus
dev-net zu ops-net, `100.64.0.0/24`, Admin-/Prod-DB-Netzen und Host-Management
standardmäßig sperren; notwendige TEST-/Edge-Verbindungen gezielt freigeben.
IPv4 und ggf. IPv6, Inter-Bridge-Verkehr, Rückwege sowie Zugriffe über publizierte
Hostports gesondert berücksichtigen. Gleiches Bridge-Netz und L7-Proxys können
andere Kontrollpunkte brauchen. Keine pauschale Freigabe über Code-Server.
Die erreichbaren Code-Server-Ports und Hostdienste ebenfalls prüfen.

Diese Regeln sind eine Empfehlung, keine bereits nachgewiesene Isolation.
Keine produktiven Firewall-/Routing-Einstellungen werden hier verändert.
Vor späterem Deployment negative Verbindungstests gegen Pi-/Admin-/PROD-Ziele
und positive Tests der erlaubten DEV-Pfade durchführen.

## Secrets

Echte `.env`-Dateien bleiben gitignored; `.env.example` enthält nur leere
Secret-Platzhalter bzw. nicht-sensitive Einstellungen. TEST und PROD verwenden
getrennte Secrets. Keine Secrets in Images, SSH-Private-Keys im Repo oder
DB-Credentials im Code-Image. Logs und Deployment-Ausgaben müssen Secrets
redigieren. Der bestehende Code-Server-Passwortmechanismus bleibt unverändert.
