# Code-Server-Stack: vorbereiteter Migrationskandidat

Dieser eigenständige Stack stellt später eine zentrale browserbasierte
Entwicklungs- und Admin-Oberfläche für Projekte unter `/home/Projects` bereit.
Er ist noch nicht deployt und verändert weder den produktiven Root-Stack noch
Docker-Netze, Host-Routen oder Projektdateien.

## Image und Build

Der Stack baut ein minimales abgeleitetes Image aus
`codercom/code-server:4.139.1`, dem laut offiziellem Changelog am 26.09.2026
veröffentlichten stabilen Release. Der feste aktuelle Release-Tag verhindert,
dass ein später verändertes `latest` unkontrolliert neue Software in den Stack
einführt. Das offizielle Image unterstützt sowohl `amd64` als auch `arm64`.

Vor einem produktiven Deployment muss der konkrete, zur Zielarchitektur
gehörende Image-Digest auf dem Zielserver ermittelt werden. Dieser Digest kann
und sollte nach erfolgreichem Test optional zusätzlich im `FROM` gepinnt werden,
damit auch der feste Tag nicht nachträglich auf andere Image-Inhalte zeigen kann.
Auf dem ARM64-Zielserver wurde für Version `4.139.1` folgender Basis-Digest
verifiziert:

```text
codercom/code-server@sha256:0c067c3cf09ed1830ce282387826be8feefef8a5828f462791c2df3f1007ee17
```

Der Dockerfile bleibt vorerst tag-basiert, damit die dokumentierte
Multi-Architektur-Nutzung nicht versehentlich auf ein architekturspezifisches
Manifest eingeschränkt wird.

Der ARM64-Build hat `/usr/sbin/ip`, `/usr/bin/ssh` und den ausführbaren
`/usr/bin/entrypoint.sh` bestätigt. Das kleine `Dockerfile` installiert
`openssh-client` und `iproute2` trotzdem explizit, damit diese Anforderungen
nicht von impliziten Upstream-Paketdetails abhängen. Zusätzlich wird nur `gosu`
als kleiner, zweckgebundener Privilege-Drop-Helfer installiert. Docker- oder
WireGuard-Werkzeuge werden nicht ergänzt.

## Workspace und Sicherheitswirkung

`${WORKSPACE_DIR:-/home/Projects}` wird schreibbar nach `/workspace` gebunden.
Damit kann code-server mehrere Repositories wie `incoming`, den aktuellen
Infra-Checkout und spätere Apps bearbeiten. Dieser Komfort bedeutet zugleich,
dass jeder Prozess oder kompromittierte Benutzer in code-server **alle** dort
gemounteten Projekte verändern kann — einschließlich versionierter
Infra-Konfigurationen.

Secrets dürfen daher nicht automatisch in den Workspace kopiert werden. Nicht
gemountet werden insbesondere `/root`, `/etc`, `/var/run/docker.sock`, anderer
Docker-Socket-Zugriff, WireGuard-State, Let's-Encrypt-State oder private
SSH-Schlüssel. `/var/run/docker.sock` würde code-server praktisch host-root-nahe
Kontrolle ermöglichen und bleibt deshalb ausdrücklich ausgeschlossen. Host- und
Container-Management muss später separat und bewusst entworfen werden.

Falls SSH-Keys benötigt werden, dürfen sie erst in einem späteren Schritt als
separate, explizite und möglichst read-only Bind-Mounts ergänzt werden. Dieses
Skeleton erzeugt oder kopiert keine Keys.

## Netzwerke und HTTP

Der Stack konsumiert ausschließlich zwei bereits vorhandene externe Netze:

- `edge-net` verbindet den internen HTTP-Port `8080` später mit Edge/Nginx.
- `ops-net` verbindet das Terminal mit dem WireGuard-Transit.

Beide Netzwerke sind mit `external: true` deklariert und werden von diesem Stack
nicht erzeugt oder verändert. Es gibt kein `ports`-Mapping; `expose: 8080`
dokumentiert nur den containerinternen HTTP-Endpunkt. Der geplante Zugriffsweg
lautet:

```text
Internet -> Edge/Nginx -> Authelia -> edge-net -> code-server:8080
```

## SSH und deklarative Route zu den Pis

Vor dem Start von code-server führt `route-entrypoint.sh` idempotent aus:

```text
ip -4 route replace 100.64.0.0/24 via 172.30.90.2
```

Danach gibt das Script seine root-Privilegien mit `gosu coder:coder` ab, setzt
`HOME=/home/coder`, `USER=coder` und `LOGNAME=coder` und ersetzt sich per `exec`
durch den originalen Upstream-Entrypoint. Dessen verifiziertes Ende
`exec dumb-init /usr/bin/code-server "$@"` erhält die saubere Signalweitergabe.
Es bleibt keine root-Shell zurück; code-server und sein Terminal sollen als
UID/GID `1000:1000` laufen und ihren Zustand nicht unter `/root` anlegen. Die
Route wird ausschließlich im Netzwerk-Namespace des Containers gesetzt und
verschwindet mit dem Container. Am Host wird keine Route verändert.

Der vollständige Pfad ist:

```text
code-server -> ops-net -> wg-easy 172.30.90.2 -> wg0 -> 100.64.0.x -> Pis
```

wg-easy übernimmt das Source-NAT von `172.30.90.0/24` nach `wg0`, sodass die Pis
keine Rückroute zum Docker-Netz benötigen. Der integrierte Terminalprozess kann
danach mit einem separat bereitgestellten SSH-Key Ziele wie `100.64.0.3` und
`100.64.0.4` erreichen.

Für `ip route replace` ist `NET_ADMIN` technisch erforderlich. Die Capability
gilt nur im Container-Namespace, erlaubt dort aber weitreichende Änderungen an
Interfaces, Routen und Firewallzustand. Sie vergrößert damit die Auswirkungen
einer Kompromittierung. `privileged: true` wird nicht verwendet; alle anderen
Capabilities werden verworfen und `no-new-privileges` ist aktiviert. Der eigene
Wrapper startet ausschließlich zum Setzen der Route als root und führt danach
den Upstream-Entrypoint über `gosu` als `coder:coder` aus. Der verifizierte
Upstream-Entrypoint führt selbst keinen Benutzerwechsel durch; ohne diesen
expliziten Schritt würde code-server als root weiterlaufen.

**Hardening-Punkt:** Da `NET_ADMIN` in Compose am Service hängt, kann die
Capability derzeit über die gesamte Containerlaufzeit verfügbar bleiben. Ein
Wechsel des Anwendungsprozesses zum Benutzer `coder` ist allein kein belastbarer
Nachweis dafür, dass die Capability im Terminalprozess nicht effektiv nutzbar
ist. Das muss im gebauten Container ausdrücklich geprüft werden. Eine spätere
Iteration soll die Capability nach dem Setzen der Route möglichst entziehen oder
das Routing stärker isolieren; in diesem Schritt wird bewusst keine komplexere
Routingarchitektur eingeführt.

## Authentifizierung

code-server startet mit der unterstützten Authentifizierungsart `password`. Das
Passwort kommt ausschließlich aus `CODE_SERVER_PASSWORD` in einer nicht
versionierten lokalen `.env`; Compose bricht bei einem fehlenden Wert ab. Die
Beispieldatei enthält kein Secret. `auth: none` wird nicht aktiviert.

Später schützt zusätzlich Edge/Nginx mit Authelia den Zugriff. Erst nach einer
bewussten Sicherheitsfreigabe und bestätigter Netzwerkisolation kann entschieden
werden, ob die doppelte Authentifizierung bestehen bleibt oder code-server nur
dem Edge vertraut. Bis dahin bleibt die interne Passwortprüfung aktiv.

## Config, Secrets und State

- **CONFIG:** `docker-compose.yml`, `Dockerfile`, `route-entrypoint.sh`, README
  und `.env.example` werden versioniert.
- **SECRETS:** code-server-Passwort und private SSH-Schlüssel gehören niemals ins
  Git. Es werden standardmäßig keine SSH-Schlüssel gemountet.
- **STATE:** Extensions, Benutzerdaten und Einstellungen liegen unter
  `/home/coder/.local/share/code-server` und werden später aus
  `${CODE_SERVER_STATE_DIR:-./state/code-server}` persistent eingebunden. Das
  Verzeichnis ist durch die übergeordnete `.gitignore` ausgeschlossen. Dieses
  Skeleton erzeugt oder verändert noch keinen Host-State.

## Voraussetzungen für einen ersten Test

1. `edge-net` existiert und ist für den isolierten Test vorbereitet.
2. Das vom WireGuard-Stack erzeugte `ops-net` existiert als `172.30.90.0/24`.
3. wg-easy ist darin unter `172.30.90.2` erreichbar.
4. WireGuard-Routing und die ops-net-MASQUERADE-Regel sind aktiv.
5. Der dokumentierte ARM64-Digest des Tags `4.139.1` ist vor dem Build nochmals
   gegen die Registry geprüft.
6. Der nächste Laufzeittest bestätigt Route, PID/Prozessbaum, UID/GID
   `1000:1000`, `HOME=/home/coder`, dass keine Config unter `/root` entsteht,
   den Listener auf `0.0.0.0:8080` und einen SSH-Client-Aufruf.
7. Im nächsten Testcontainer wird gemessen, ob `NET_ADMIN` im
   code-server-/Terminalprozess noch effektiv verfügbar ist; das Ergebnis fließt
   in das spätere Capability-Hardening ein.
8. Ein starkes lokales `CODE_SERVER_PASSWORD` und ein beschreibbarer State-Pfad
   mit UID/GID `1000` sind vorbereitet.
9. Workspace-Umfang und Schreibberechtigungen sind ausdrücklich freigegeben.

Erst dann folgen in einem separaten Schritt Syntaxprüfung, Image-Build und ein
isolierter Funktionstest für HTTP, Persistenz, Route und SSH. Es findet jetzt
kein Deployment statt.

## Stand der isolierten Build-Verifikation

Der Build auf dem echten ARM64-Zielserver hat Architektur `arm64`, code-server
`4.139.1`, den Benutzer `coder` mit UID/GID `1000:1000`, `ip`, `ssh` sowie den
ausführbaren Upstream-Entrypoint bestätigt. Der Lauf als UID/GID `0:0` und mit
`HOME=/root` hat zugleich den jetzt behobenen Fehler im bisherigen Wrapper
aufgedeckt: Der Upstream-Entrypoint startet code-server für den aufrufenden
Benutzer und führt keinen eigenen Privilege-Drop aus.

Der überarbeitete `gosu`-Pfad ist noch nicht zur Laufzeit verifiziert. Die unter
„Voraussetzungen für einen ersten Test“ genannten Prozess-, HOME-, Config-,
Port-, SSH-, Routen- und Capability-Prüfungen bleiben daher vor jedem Deployment
verbindlich.

## Rollback

Da dieser Schritt keine Runtime-Ressource erzeugt, besteht aktuell kein
Runtime-Rollback. Bei einem späteren Test wird ausschließlich der neue
Code-Stack entfernt; externe Netze, wg-easy, der produktive Root-Stack und die
Projekt-Repositories bleiben unangetastet. Vor einem Rückbau ist neu entstandener
State kontrolliert zu sichern oder bewusst zu verwerfen.
