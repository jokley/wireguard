# Produktive modulare Infrastruktur

Die Infrastruktur unter `infra/` ist laut aktuellem Betriebsstand produktiv.
Dieser Struktur-/Naming-Cleanup benennt `infra-new/` in `infra/` um und entfernt
`-new` aus den deklarativen Container-Namen. Er führt kein Deployment aus.
Das Repository bleibt `/home/Projects/wireguard`; Root-/Legacy-Compose,
Legacy-Konfigurationen und Backups bleiben erhalten.

## Struktur und Container

```text
infra/
├── edge/       # Edge, TLS, Reverse Proxy und Landingpage
├── auth/       # Authelia
├── wireguard/  # VPN und Pi-Transit
├── code/       # Code-Server
├── webssh/     # Browser-SSH
└── shared/     # gemeinsame Architektur- und Netzwerkdokumentation
```

| Stack | Service | Deklarativer Container-Name |
| --- | --- | --- |
| edge | edge-network | edge-network |
| edge | edge-nginx | edge-nginx |
| edge | certbot | edge-certbot |
| auth | authelia | authelia |
| wireguard | wg-easy | wg-easy |
| code | code-server | code-server |
| webssh | webssh | webssh |

Die laufenden Container werden durch diesen PR nicht umbenannt. Service-Namen,
interne DNS-Namen, Aliases und Compose-Projektverzeichnisse der einzelnen Stacks
bleiben unverändert. Die Namen sind erst bei einem separaten Deployment wirksam;
die erhaltene Legacy-Konfiguration darf nicht parallel mit kollidierenden
Container-Namen oder produktiven Ports gestartet werden.

## Zugriffswege

```text
Internet
 ├─ Edge: 80/tcp, 443/tcp, 8883/tcp
 └─ WireGuard: 51820/udp
```

| Domain | Routing |
| --- | --- |
| me.jokley.at | statische Landingpage |
| code.jokley.at | Authelia → code-server:8080 |
| ssh.jokley.at | Authelia → webssh:8080 |
| wg.jokley.at | Authelia → wg-easy:51821 |
| incoming.jokley.at | bestehender Incoming-Pfad → incoming-nginx:8080 |

Pi-/Home-/MQTT-Routen bleiben unverändert. 51821 bleibt intern; Code-Server,
WebSSH und Authelia erhalten keine öffentlichen Host-Ports. TLS, Zertifikate,
Auth-Policies und sämtliche Nginx-Proxy-Routen werden nicht verändert.

## Netzwerke

| Netzwerk | Ownership und Anbindung |
| --- | --- |
| edge-net, 172.30.91.0/24 | Edge erzeugt das Netz; Auth, Code, WebSSH und Incoming konsumieren es extern. |
| ops-net, 172.30.90.0/24 | WireGuard erzeugt das Netz; Edge, Code und WebSSH konsumieren es extern. wg-easy bleibt 172.30.90.2. |

`edge-network` ist an beide Netze angebunden; Nginx teilt dessen Namespace mit
`network_mode: service:edge-network`. Route und NAT bleiben unverändert:
`100.64.0.0/24 via 172.30.90.2`. Das stack-lokale WireGuard-`default`-Netz bleibt
ebenfalls unverändert. `shared/` erzeugt keine Netzwerke.

## Pfade, Secrets und State

Relative Build-Kontexte und Mount-Pfade behalten innerhalb jedes verschobenen
Stacks ihre Struktur, einschließlich `../../wgeasy.env`. Absolute produktive
Datenpfade werden nicht geändert. Lokale `.env`-Dateien, externe Runtime-Includes,
Zertifikate, Benutzerdateien und persistente Daten bleiben außerhalb von Git.
Bei einer späteren Übernahme der Verzeichnisumbenennung auf dem Zielhost müssen
diese lokalen Dateien und Pfadreferenzen erhalten bleiben; dieser PR verschiebt
oder prüft keinen produktiven Runtime-State.

Die Stack-READMEs enthalten zusätzlich historische Migrations- und Testprotokolle.
Die aktuelle Struktur und Architektur sind in dieser Übersicht dokumentiert.
