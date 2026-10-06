# WebSSH-Stack

WebSSH wird langfristig als eigenständige Browser-SSH-App betrieben. Der Zugriff
vom Edge erfolgt über `edge-net`; Raspberry-Pi-Ziele werden über den deklarativen
WireGuard-Transit in `ops-net` erreicht.

Dieses Skeleton übernimmt weder das bestehende Image noch Konfiguration, Ports,
Secrets oder persistenten Zustand.
