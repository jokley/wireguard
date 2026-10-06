# Geplante Netzwerke

## edge-net

Gemeinsames Netz zwischen dem öffentlichen Edge und internen Webdiensten wie
Auth, code-server, WebSSH und `incoming-nginx`.

## ops-net

Transitnetz für wg-easy und Dienste mit Zugriff auf WireGuard-Peers:

- geplantes Subnetz: `172.30.90.0/24`
- geplante wg-easy-Adresse: `172.30.90.2`
- geplante Teilnehmer: wg-easy, code-server, WebSSH und gegebenenfalls
  vorübergehend der Edge

Die spätere Umsetzung muss Compose-basiert und reproduzierbar erfolgen. Dieses
Dokument erzeugt keine Ressourcen; manuelle Netzwerkverbindungen oder
iptables-Runtime-Regeln sind nicht Teil der Zielarchitektur.
