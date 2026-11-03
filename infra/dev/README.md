# Generische Entwicklungs- und Testplattform

Dieser Stack besitzt ausschließlich `dev-net`. Er enthält keinen Incoming-Teststack,
keine Pi-Konfiguration und keine Deployment-Automatisierung. Es wurde keine Runtime
angelegt oder verändert. Die [zentralen Konventionen](../shared/development.md)
trennen LOCAL/DEV, TEST/QA und PROD sowie Server- und Device-Projekte.

## Subnetz und Voraussetzungen

`172.30.92.0/24` ist der bevorzugte Kandidat. Ein statischer Vergleich mit den
Repo-Netzen `172.30.90.0/24` (ops-net) und `172.30.91.0/24` (edge-net) zeigt
keine Überschneidung. Das ist **keine Freiprüfung des Produktionshosts**:
Docker-IPAM, weitere Docker-Netze, LAN-, VPN- und Hostrouten wurden nicht abgefragt.
Vor einem separaten Deployment muss ein Operator deren Überschneidungsfreiheit
prüfen und `DEV_NET_SUBNET` in einer lokalen, gitignored `.env` explizit setzen.
Die `.env.example` bleibt leer; Compose bricht ohne Auswahl ab. Eine andere
freie private CIDR darf verwendet werden. Keine bestehenden Netze umnummerieren.

Der lokale Compose-Client 2.40.3 akzeptiert `services: {}` mit einer
Netzwerkdefinition bei `config`. Das bestätigt nur das Parsen, nicht Erzeugung,
Ownership oder Erhalt eines ungenutzten Netzes. Die eingesetzte Version auf dem
Produktionshost und ihr Lifecycle wurden nicht verifiziert. Deshalb wird kein
servicefreies Projekt als zuverlässiger Network-Owner vorausgesetzt.

## Ownership und Lifecycle

Das Compose-Projekt `infra-dev` besitzt `dev-net` mit explizitem globalem Namen.
Ein einzelner `network-holder` aus dem kleinen Multi-Arch-Image `alpine:3.22.1`
hält eine aktive Netzwerkanbindung mit `sleep infinity`. Er läuft als
UID/GID 65534, mit `restart: unless-stopped`, read-only Root-Dateisystem,
`cap_drop: ALL` und `no-new-privileges:true`. Keine Ports, Volumes, Secrets,
Docker-Sockets oder zusätzlichen Capabilities. Das feste Image-Tag folgt dem
vorhandenen Alpine-Stand im Repository; es ist nicht per Digest unveränderlich.

Nur dieses Infrastrukturprojekt darf das Netz erzeugen oder entfernen.
Code-Server und zukünftige TEST-Projekte konsumieren es ausschließlich extern:

```yaml
networks:
  dev-net:
    external: true
    name: dev-net
```

Ein `down` eines einzelnen TEST-Projekts entfernt dieses externe Netz nicht.
Ein `down` des Owners ist dagegen eine Infrastruktur-Abbauaktion und nicht Teil
des normalen TEST-Lifecycles; vorhandene fremde Endpunkte können das Entfernen
verhindern. Kein Cleanup darf ein Network-Prune oder Owner-Down implizit ausführen.

Bei einem späteren kontrollierten Deployment muss `infra/dev` vor Code-Server
und TEST-Konsumenten bereitstehen. Keine Cross-Compose-Startabhängigkeit wird
vorgetäuscht. Die Code-Anbindung verwendet `gw_priority: -1` für dev-net;
dafür ist Compose ab 2.33.1 erforderlich. Die bestehende Gateway-Wahl zwischen
edge-net und ops-net wird dadurch nicht neu festgelegt.

## Spätere Abnahme auf dem Zielhost

Vor Aktivierung: Compose-Version, freie CIDR und aufgelöste Compose-Konfiguration
prüfen. Danach in einem eigenen freigegebenen Deployment Ownership, Wiederanlauf
des Holders, DNS/Erreichbarkeit über dev-net, unveränderte Code-Server-Routen und
Isolation gegen ops-net/PROD prüfen. Ein separater TEST-Down muss dev-net erhalten.
Diese Runtime-Prüfungen wurden hier ausdrücklich nicht durchgeführt.
