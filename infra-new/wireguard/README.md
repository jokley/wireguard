# WireGuard-Stack: vorbereiteter Migrationskandidat

Dieser Stack trennt ausschließlich wg-easy aus dem heutigen Root-Stack heraus.
Er ist eine **noch nicht freigegebene Deployment-Vorlage**: Der produktive
Root-Stack bleibt bis zum geprüften Cutover unverändert aktiv. Insbesondere darf
diese Compose-Datei jetzt nicht gestartet werden, weil UDP-Port `51820` bereits
vom produktiven wg-easy belegt ist und beide Instanzen denselben Zustand nutzen
würden.

## Abbildung des bestehenden wg-easy

Die Vorlage übernimmt bewusst die im Root-Compose sichtbaren Betriebsparameter:

- exakt gepinntes produktives Image
  `ghcr.io/wg-easy/wg-easy@sha256:66352ccb4b5095992550aa567df5118a5152b6ed31be34b0a8e118a3c3a35bf5`
  (verifizierte Container-Image-ID:
  `sha256:417baa6ac0b37f36106f71b864bd950bc872fc5497140f49d1fc29a563623b6d`),
- WireGuard UDP `51820` als einziger veröffentlichter Host-Port,
- Management-Port `51821` nur intern über `expose`,
- `NET_ADMIN` und `SYS_MODULE`,
- `net.ipv4.ip_forward=1` und
  `net.ipv4.conf.all.src_valid_mark=1`,
- bestehende Variablen für Host, Peer-Adressen, DNS und Keepalive sowie
- das bestehende Root-`wgeasy.env` per relativer `env_file`-Referenz.

Die zusätzlichen Host-Ports des alten Monolithen werden nicht übernommen. Sie
gehörten zu Diensten, die dort den Netzwerk-Namespace von wg-easy mitbenutzten,
nicht zum eigenständigen WireGuard-Stack.

Der Digest verhindert, dass ein später verändertes Tag unbemerkt eine andere
wg-easy-Version lädt. Das ist insbesondere für die versionsabhängige Semantik der
WireGuard-Hooks erforderlich.

## Netzarchitektur

Der Container ist an zwei deklarative Bridge-Netze angebunden:

1. Das Compose-projektspezifische `default`-Netz ist für spätere stack-lokale
   Kommunikation vorgesehen.
2. `ops-net` wird von dieser Compose-Datei mit dem festen Namen `ops-net` und dem
   Subnetz `172.30.90.0/24` definiert. wg-easy erhält dort statisch
   `172.30.90.2`.

Geplanter Datenpfad:

```text
code/webssh -> ops-net -> wg-easy (172.30.90.2) -> wg0 -> 100.64.0.x
```

Spätere Teilnehmer müssen die Route `100.64.0.0/24 via 172.30.90.2`
deklarativ erhalten. Weder dieses Repository noch dieser Schritt führt ein
`docker network create/connect` oder `ip route add` zur Laufzeit aus.

## Persistenzstrategie

Der Bind-Mount `${WG_DATA_DIR:-/root/.wg-easy}:/etc/wireguard` zeigt für den
späteren Cutover auf denselben persistenten Bestand wie der Root-Stack. Damit
sollen unverändert weiterverwendet werden:

- private und öffentliche WireGuard-Server-Keys,
- Peer-Keys und Peer-Konfigurationen,
- die von wg-easy verwaltete Server-/Peer-Konfiguration einschließlich der
  vorhandenen Peer-Routen und
- weiterer versionsabhängiger wg-easy-State innerhalb dieses Verzeichnisses.

Es werden jetzt keine Daten gelesen, kopiert, verändert oder neu erzeugt. Vor dem
Cutover sind ein konsistentes Backup, eine Bestandsaufnahme, die Prüfung von
Besitzern/Rechten sowie ein Restore-Test erforderlich. Alt- und Neu-Container
dürfen niemals gleichzeitig schreibend auf dieses Verzeichnis zugreifen.

## Routing und NAT

Die verifizierte produktive wg-easy-Version unterstützt `WG_POST_UP` und
`WG_POST_DOWN`. Bei dieser Version **ersetzen** beide Variablen jedoch die
eingebauten Standard-Hooks vollständig; sie ergänzen sie nicht. Deshalb enthält
die Compose-Datei jeweils die komplette produktive Regelliste und nicht nur die
neue ops-net-Regel.

Vollständig übernommene produktive PostUp-Regeln:

```text
iptables -t nat -A POSTROUTING -s 100.64.0.0/24 -o eth0 -j MASQUERADE;
iptables -A INPUT -p udp -m udp --dport 51820 -j ACCEPT;
iptables -A FORWARD -i wg0 -j ACCEPT;
iptables -A FORWARD -o wg0 -j ACCEPT;
```

PostDown entfernt diese vier Regeln mit denselben Parametern und jeweils `-D`
anstelle von `-A`. Zusätzlich hängt PostUp die erfolgreich getestete
ops-net-Regel an:

```text
iptables -t nat -A POSTROUTING -s 172.30.90.0/24 -o wg0 -j MASQUERADE
```

PostDown entfernt sie exakt spiegelbildlich:

```text
iptables -t nat -D POSTROUTING -s 172.30.90.0/24 -o wg0 -j MASQUERADE;
```

Das Source-NAT ersetzt für Pakete an die Pis die Quelladresse aus
`172.30.90.0/24` durch die Adresse des ausgehenden `wg0`-Interfaces. Antworten
gehen dadurch an wg-easy zurück und werden dort per Conntrack dem ursprünglichen
ops-net-Teilnehmer zugeordnet. Die Pis benötigen deshalb keine eigene Rückroute
zu `172.30.90.0/24`.

Die Regeln werden ausschließlich über die von dieser Version unterstützten
wg-easy-Variablen erzeugt. Die bestehende `wg0.conf` wird **nicht direkt
editiert**, weil wg-easy sie generiert und überschreibt.

## Spätere Testschritte (nicht jetzt ausführen)

1. Gepinnten Repo-Digest nochmals gegen das produktive Image prüfen.
2. `/root/.wg-easy` konsistent sichern und Restore separat verifizieren.
3. Root-Stack in einem geplanten Wartungsfenster stoppen; niemals parallel auf
   denselben State oder Port zugreifen.
4. Compose-Konfiguration validieren und den neuen Stack kontrolliert starten.
5. `wg0` mit `10.64.0.1/24`, vorhandene Peers und UDP `51820` prüfen.
6. Einen isolierten Testteilnehmer deklarativ an `ops-net` anbinden und die Route
   zu `100.64.0.0/24` setzen.
7. SSH-Erreichbarkeit mindestens von `100.64.0.3:22` und `100.64.0.4:22` sowie
   die NAT-Regel und deren Entfernung beim Stop prüfen.
8. Management-Zugriff über das interne Docker-Netz prüfen; Port `51821` bleibt
   am Host unveröffentlicht.

## Rollback

Bei jeder Abweichung wird der neue Container gestoppt, ohne den persistenten
Bestand zu verändern. Nach Prüfung, dass kein neuer Prozess mehr auf
`/root/.wg-easy` oder UDP `51820` zugreift, wird ausschließlich der unveränderte
Root-Stack wieder gestartet. Der Legacy-Stack bleibt bis zum vollständigen,
abgenommenen Cutover die produktive Referenz und wird in diesem Schritt weder
gestoppt noch geändert.
