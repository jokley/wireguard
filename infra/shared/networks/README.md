# Produktive Netzwerke

| Netz | Subnetz | Owner | Teilnehmer |
| --- | --- | --- | --- |
| edge-net | 172.30.91.0/24 | Edge | Edge, Authelia, Code-Server, WebSSH, Incoming |
| ops-net | 172.30.90.0/24 | WireGuard | wg-easy, Edge, Code-Server, WebSSH |

wg-easy behält die statische Adresse `172.30.90.2`. Der Edge behält seinen
Alias `edge-nginx` im `edge-net`; Nginx teilt den Namespace von `edge-network`.
Die Konsumenten verwenden die Netze weiterhin als externe Netze. Das lokale
WireGuard-`default`-Bridge-Netz bleibt ebenfalls unverändert.

Route `100.64.0.0/24 via 172.30.90.2`, WireGuard-NAT und sämtliche
Network-/IPAM-/Alias-Einstellungen bleiben unverändert. Dieses Dokument erzeugt
keine Ressourcen und führt keine manuellen Netzwerkverbindungen aus.
