# Modulare Infrastruktur (paralleles Grundgerüst)

Dieses Verzeichnis beschreibt die geplante Zielarchitektur. Es ist derzeit **nur
ein Skeleton**: Der produktive Legacy-Stack im Repository-Root bleibt bis zum
vollständigen Cutover unverändert und allein maßgeblich. Keine der Compose-Dateien
in diesem Verzeichnis definiert oder startet aktuell produktive Services.

## Zielarchitektur

```text
infra-new/
├── edge/       # öffentlicher Entry Point, TLS und Reverse Proxy
├── auth/       # eigenständige Authentifizierung
├── wireguard/  # VPN und Routing zu Raspberry-Pi-Peers
├── code/       # zentrale Entwicklungs- und Admin-Oberfläche
├── webssh/     # Browser-SSH
└── shared/     # gemeinsam deklarierte Infrastruktur, insbesondere Netze
```

Anwendungen wie `incoming`, `app2` und `app3` bleiben eigenständige Repositories
neben dem späteren Infrastruktur-Repository unter `/home/Projects`.

## Verantwortlichkeiten der Stacks

| Stack | Verantwortung | Geplante Anbindungen |
| --- | --- | --- |
| `edge` | Nginx, Certbot, öffentlicher Entry Point, TLS und Reverse Proxy | `edge-net`; vorübergehend eventuell `ops-net` für direkte `100.64.0.x`-Ziele |
| `auth` | Authelia als eigenständiger, später austauschbarer Auth-Service | `edge-net` |
| `wireguard` | Ausschließlich wg-easy sowie VPN/Routing zu Raspberry Pis | `ops-net` mit geplanter IP `172.30.90.2` |
| `code` | code-server mit Zugriff auf `/home/Projects` und über WireGuard auf Raspberry Pis | `edge-net`, `ops-net` |
| `webssh` | Eigenständiges Browser-SSH mit Zugriff auf Raspberry Pis | `edge-net`, `ops-net` |
| `shared` | Spätere deklarative Definition gemeinsam genutzter Netze | `edge-net`, `ops-net` |

## Geplante Netzwerke

- **`edge-net`** verbindet den Edge mit internen Webdiensten, beispielsweise
  Auth, code-server, WebSSH und `incoming-nginx`.
- **`ops-net`** ist das Transitnetz für Dienste, die WireGuard-Peers erreichen
  müssen. Vorgesehen sind das Subnetz `172.30.90.0/24` und für wg-easy die IP
  `172.30.90.2`. Diese Werte wurden bereits temporär erprobt, werden hier aber
  weder angelegt noch aktiviert.

In diesem Schritt existieren die Netze ausschließlich als Dokumentation. Im
finalen System sind keine manuellen `docker network connect`-Befehle oder
temporären iptables-Runtime-Regeln zulässig: Netzwerke, Routing und notwendige
NAT-Regeln müssen später vollständig deklarativ, versioniert und reproduzierbar
umgesetzt werden.

## Abhängigkeiten

1. `shared` stellt künftig die externen gemeinsamen Netze bereit.
2. `wireguard` stellt den Transit zu den VPN-Peers für Teilnehmer von `ops-net`
   bereit.
3. `code` und `webssh` benötigen den WireGuard-Transit für Raspberry-Pi-Zugriff
   und `edge-net` für den Zugriff über den Reverse Proxy.
4. `auth` ist über `edge-net` vom Edge erreichbar.
5. `edge` terminiert TLS, bindet Auth ein und veröffentlicht interne Webdienste.

Diese Abhängigkeiten sind Planungsstand und noch nicht in laufende Ressourcen
übersetzt.

## Config, Secrets und State

### CONFIG — gehört grundsätzlich ins Git

Reproduzierbare, überprüfbare Konfiguration wird versioniert, zum Beispiel:

- Compose-Dateien,
- `nginx.conf` und weitere Reverse-Proxy-Konfiguration,
- Authelia `configuration.yml` ohne geheime Werte.

### SECRETS — gehören nicht ins Git

Passwörter, Tokens, JWT-/Session-/Encryption-Secrets, Proxy-Secrets und private
SSH-Schlüssel werden niemals eingecheckt. `.env.example` enthält ausschließlich
harmlose Platzhalter; reale Werte gehören später in einen geeigneten
Secret-Mechanismus.

### STATE — persistent und nicht neu generieren

Bestehende WireGuard-Schlüssel und Peer-Konfigurationen, Let's-Encrypt-Zertifikate
und gegebenenfalls Authelia-Daten sind produktiver Zustand. Sie dürfen weder neu
generiert noch unkontrolliert kopiert oder überschrieben werden. Ihr späterer
Umzug braucht einen eigenen, geprüften Migrations- und Rollback-Schritt.

## Migrationsreihenfolge

1. Shared Networks deklarieren und kontrolliert bereitstellen
2. WireGuard ausgliedern
3. code-server bereitstellen
4. WebSSH ausgliedern
5. Auth ausgliedern
6. Edge ausgliedern
7. Legacy-Stack erst nach vollständiger Verifikation entfernen
8. Repository abschließend von `wireguard` in `infra` umbenennen

Jeder Schritt benötigt vor Aktivierung eine eigene Prüfung, Sicherung und einen
Rollback-Plan.

## Rollback-Grundsatz

Der Legacy-Stack im Repository-Root einschließlich Compose-Datei,
Konfigurationen, persistenten Daten, Secrets und Peer-Zugängen bleibt bis zum
vollständigen Cutover unangetastet. Ein neuer Stack ersetzt den bisherigen erst,
wenn Funktion und Rückweg nachweislich geprüft sind.

## Aktueller Sicherheitsstatus

Dieses Grundgerüst enthält keine übernommenen Secrets, Keys, Zertifikate oder
produktiven Daten. Es erzeugt keine Docker-Netze, verändert keine Ports und führt
keine Container-, WireGuard-, Firewall- oder Deployment-Aktion aus.
