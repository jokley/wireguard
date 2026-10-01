# WireGuard-Stack

Geplant ist ein auf **wg-easy** begrenzter Stack. Er soll über `ops-net`
(`172.30.90.0/24`) unter `172.30.90.2` Routing zu den vorhandenen
Raspberry-Pi-Peers anbieten. Nginx, Authelia und WebSSH gehören ausdrücklich
nicht in diesen Stack.

Dieses Verzeichnis ist nur ein Skeleton. Bestehende Keys, Peers, Konfigurationen,
Routen und Firewallregeln werden in diesem Schritt weder kopiert noch verändert.
