# Eigenständiger WebSSH-Stack: Migrationskandidat

Dieser Stack bereitet die Ausgliederung des bestehenden Browser-SSH-Dienstes
vor. Er ist noch nicht deployt; der produktive Root-Stack bleibt bis zum
erfolgreichen Cutover vollständig unverändert aktiv.

## Analysierter Legacy-Aufbau

Der produktive Root-Compose baut `webssh/dockerfile`, verwendet
`restart: unless-stopped` und setzt `network_mode: "service:wg-easy"`. WebSSH
teilt dadurch heute Interfaces, Routing, Ports, `wg0` und den gesamten
Netzwerk-Namespace mit wg-easy. Deshalb kann es Raspberry-Peers unter
`100.64.0.x` ohne eigene Route erreichen. Der vom gemeinsamen Namespace auf dem
Host veröffentlichte Port `8080` wird vom Legacy-Nginx über
`http://localhost:8080/` angesprochen.

Das Legacy-Dockerfile basiert auf dem ungepinnten `arm64v8/alpine`, installiert
Python 3, pip und virtualenv, erzeugt `/opt/venv`, installiert das PyPI-Paket
`webssh` **ohne Versionspin** und startet:

```text
wssh --address=0.0.0.0 --port=8080
```

Es enthält weder `USER` noch eigenen Entrypoint; der Prozess läuft daher nach
Repositorystand als root. Die konkret produktiv installierte WebSSH-Version ist
weder im Repository festgeschrieben noch in dieser Arbeitsumgebung per Runtime-
Inspect bestimmbar. Sie darf vor dem Cutover nicht geraten werden: Auf dem
ARM64-Zielserver sind `wssh --version` beziehungsweise Paketmetadaten und der
Image-Digest zu erfassen. Erst danach soll `webssh` auf genau diese getestete
Version gepinnt werden.

## Neues Image und unprivilegierter Benutzer

Der neue Dockerfile behält den bewährten Alpine-/Python-/venv-Aufbau bei und
verwendet den festen ARM64-Basistag `arm64v8/alpine:3.22.1`. Zusätzlich werden
nur `iproute2` für die Route und Alpines kleiner Privilege-Drop-Helfer `su-exec`
installiert. Das Image legt den dedizierten Benutzer und die Gruppe `webssh` mit
UID/GID `10001:10001` und Home `/home/webssh` an.

Der Container startet ausschließlich für die Routenoperation als root.
`route-entrypoint.sh` prüft UID 0 und setzt idempotent:

```text
ip -4 route replace 100.64.0.0/24 via 172.30.90.2
```

Danach startet `exec su-exec webssh:webssh ... wssh "$@"` die Anwendung direkt
als unprivilegierten Benutzer. `HOME`, `USER` und `LOGNAME` werden konsistent
gesetzt, keine root-Shell bleibt bestehen und Signale erreichen `wssh` direkt.

Für die Route ist initial `NET_ADMIN` erforderlich. `SETUID` und `SETGID`
ermöglichen `su-exec` den Wechsel zu `webssh:webssh`. Compose verwirft vorher
alle Capabilities, aktiviert nur diese drei und setzt
`no-new-privileges:true`; `privileged: true` und Host-Networking werden nicht
verwendet. Im ARM64-Runtime-Test muss noch bestätigt werden, dass der laufende
WebSSH-Prozess UID/GID `10001:10001` sowie `CapPrm=0` und `CapEff=0` besitzt und
selbst keine Route mehr verändern kann.

## Netzwerke, Port und Routing

Der Stack konsumiert ausschließlich bestehende externe Netze:

- `edge-net` für HTTP vom späteren Edge-Nginx,
- `ops-net` (`172.30.90.0/24`) für den Transit zu WireGuard.

Er erzeugt oder verändert keines der Netze. Port `8080` wird nur mit `expose`
für andere Container dokumentiert und nicht auf dem Host veröffentlicht. Beim
späteren Edge-Cutover wird der bisherige Nginx-Upstream `localhost:8080` durch
`webssh:8080` ersetzt; in diesem Schritt bleibt Nginx unverändert.

Der Zielpfad lautet:

```text
Internet -> Edge/Nginx -> Authelia -> edge-net -> webssh:8080
WebSSH -> ops-net -> wg-easy 172.30.90.2 -> wg0 -> 100.64.0.x -> Pis
```

wg-easy übernimmt Source-NAT von `172.30.90.0/24` nach `wg0`. Die Raspberry-Peers
benötigen deshalb keine Rückroute zum Docker-Netz.

## Security, Config, Secrets und State

- **CONFIG:** `Dockerfile`, `docker-compose.yml`, `route-entrypoint.sh` und dieses
  README werden versioniert.
- **SECRETS:** Es gibt keine produktiven Secrets im Git. WebSSH benötigt für
  diesen Betriebsmodus keinen automatisch bereitgestellten privaten SSH-Key;
  Benutzer geben Zielsystem-Zugangsdaten interaktiv ein.
- **STATE:** WebSSH wird stateless betrieben. Es werden keine Volumes und kein
  persistenter State angelegt.

Es gibt keinen Host-Port und keine Mounts. Insbesondere werden weder
`/var/run/docker.sock`, `/root`, Host-Systemverzeichnisse, WireGuard-State,
Let's-Encrypt-Daten noch private SSH-Schlüssel eingebunden. Der Zugriff soll
später ausschließlich über Edge und Authelia erfolgen.

## Voraussetzungen und spätere Tests

Vor einem isolierten ARM64-Test müssen `edge-net` und das vom WireGuard-Stack
erzeugte `ops-net` existieren, wg-easy unter `172.30.90.2` erreichbar sowie
WireGuard-Routing und ops-net-MASQUERADE aktiv sein. Der Test muss mindestens
bestätigen:

1. Basisimage und Build funktionieren auf ARM64; Image-Digests werden erfasst.
2. Die produktive Legacy-WebSSH-Version wird ermittelt und eine feste Version
   für das neue Image ausgewählt.
3. `ip`, `su-exec` und `wssh` sind vorhanden; WebSSH lauscht auf
   `0.0.0.0:8080`, ohne dass ein Host-Port veröffentlicht ist.
4. Die Route `100.64.0.0/24 via 172.30.90.2` ist vorhanden und SSH-Verbindungen
   zu den bekannten Peer-Zielen erreichen mindestens den SSH-Handshake.
5. Prozessbaum, UID/GID, HOME, `NoNewPrivs`, `CapPrm` und `CapEff` entsprechen
   dem Privilege-Drop-Konzept; `webssh` kann keine Route nachträglich verändern.
6. HTTP/WebSocket-Funktion sowie der spätere Upstreamname `webssh:8080` werden
   in einem isolierten Testnetz geprüft.

## Rollback

Der alte WebSSH-Service bleibt bis zum erfolgreichen, abgenommenen Cutover im
Legacy-Root-Stack erhalten. Bei einem späteren Test wird ausschließlich der neue
WebSSH-Container entfernt; externe Netze, wg-easy, Nginx, Authelia und der
produktive Root-Stack bleiben unverändert.
