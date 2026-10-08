# Eigenständiger Edge-Stack: Migrationskandidat

Dieser Stack bereitet Nginx und Certbot als eigenständigen öffentlichen Edge
vor. Er ist nicht deployt. Der produktive Root-Stack, der laufende Edge, die
bereits vorhandenen Testnetze und `authelia-new` bleiben unangetastet.

## Analysierte Legacy-Architektur

Im Root-Compose läuft Nginx mit `network_mode: "service:wg-easy"`. Dadurch teilt
es Interfaces, veröffentlichte Ports, Routing und `wg0` mit wg-easy und erreicht
direkte Ziele unter `100.64.0.0/24` ohne eigene Route. Der Root-Stack
veröffentlicht 80/TCP, 443/TCP und 8883/TCP über diesen gemeinsamen Namespace;
außerdem werden dort heute weitere, nicht zum neuen Edge gehörende Ports
veröffentlicht.

Legacy-Nginx bindet die Hauptkonfiguration, Includes, Webroot und den
Let's-Encrypt-State ein. Zertifikate werden read-only verwendet. Ein Shell-Loop
lädt Nginx alle sechs Stunden neu. Certbot bindet denselben Zertifikats-State und
ACME-Webroot schreibbar ein und versucht alle zwölf Stunden ein Renewal. Das
separate Legacy-Hilfsskript kann initiale Zertifikate per Webroot ausstellen,
erzeugt dafür temporäre Zertifikate und lädt Nginx neu; dieser invasive Ablauf
wird nicht in den neuen Stack kopiert oder ausgeführt.

Es gibt keinen expliziten Resolver und keine benutzerdefinierten Access-/Error-
Logpfade. Nginx nutzt seine Standardlogs. HTTP wird grundsätzlich auf HTTPS
umgeleitet, außer `/.well-known/acme-challenge/`, das aus dem Certbot-Webroot
bedient wird.

## Verifizierte produktive Images

Die produktive Runtime wurde auf dem ARM64-Zielserver read-only verifiziert.
Für den Infrastruktur-Cutover werden exakt diese Stände verwendet; ein
gleichzeitiges Nginx- oder Certbot-Upgrade ist ausdrücklich ausgeschlossen:

| Komponente | Version | Architektur | Image-ID | RepoDigest |
| --- | --- | --- | --- | --- |
| Nginx | `nginx/1.27.5` | `arm64` | `sha256:1f94323bafb2ac98d25b664b8c48b884a8db9db3d9c98921b3b8ade588b2e676` | `arm64v8/nginx@sha256:b312465509d25554910dfbf88323ede17eeb159fdc1307a05280e282fe4b47d3` |
| Certbot | `certbot 4.0.0` | `arm64` | `sha256:ffa654b4667fd371d3d976938db836df533d4cad08284b66d151c88281ead239` | `certbot/certbot@sha256:0d9c7c8f71a81fcbc1acb96060194ce9e97a528fa907dcc46a72b8b8d523faab` |

Compose verwendet diese unveränderlichen Digests als Defaults. Die lokale
`.env` dokumentiert sie ebenfalls und darf sie bei einem späteren, bewusst
geprüften Upgrade explizit überschreiben. `latest` wird nicht verwendet.

## Domains und Legacy-Upstream-Matrix

Alle aktiven TLS-Server und direkten Pi-Ziele bleiben in der neuen
`nginx.conf` erhalten:

| Domain/Pfad | Legacy-Upstream | Neuer Upstream | Authelia | WebSocket | Protokoll |
| --- | --- | --- | --- | --- | --- |
| `me.jokley.at/webssh/` | `localhost:8080` | `webssh:8080` | ja | ja | HTTP |
| `me.jokley.at/` | `localhost:51821` | `wg-easy:51821` | nein | ja | HTTP |
| `me.venti.jokley.at` | `100.64.0.2:80` | unverändert | ja | ja | HTTP |
| `me.disti.jokley.at` | `100.64.0.3:80` | unverändert | ja | ja | HTTP |
| `beck.jokley.at` | `100.64.0.4:80` | unverändert | ja | ja | HTTP |
| `juen.jokley.at` | `100.64.0.5:80` | unverändert | nein | ja | HTTP |
| `zotta.venti.jokley.at` | `100.64.0.6:80` | unverändert | ja | ja | HTTP |
| `franz.venti.jokley.at` | `100.64.0.7:80` | unverändert | ja | ja | HTTP |
| `branner.venti.jokley.at` | `100.64.0.8:80` | unverändert | ja | ja | HTTP |
| `brif.venti.jokley.at` | `100.64.0.9:80` | unverändert | ja | ja | HTTP |
| `mathias.venti.jokley.at` | `100.64.0.10:80` | unverändert | ja | ja | HTTP |
| `walter.venti.jokley.at` | `100.64.0.11:80` | unverändert | ja | ja | HTTP |
| `incoming.jokley.at/` | `incoming-nginx:8080` | unverändert | ja | ja | HTTP |
| `incoming.jokley.at/api/` | `incoming-nginx:8080` | unverändert | ja | nein | HTTP |
| MQTT auf `8883` | `100.64.0.3:1883` | unverändert | nein | n/a | TCP/TLS |

`ski.pointi.jokley.at -> 100.64.0.5:8080` ist im Legacy-File vollständig
auskommentiert und bleibt auch im neuen File inaktiv. Es wird nicht als aktive
Route migriert.

Im Legacy-Nginx existiert kein code-server-Upstream. Deshalb wird ohne bestätigte
Domain, Zertifikat und Auth-Policy kein neuer virtueller Host erfunden. Sobald
diese Angaben feststehen, ist das Ziel über `edge-net` ausdrücklich
`code-server:8080`; WebSocket-/Upgrade-Header müssen erhalten bleiben.

## Authelia-Integration

Die Include-Struktur und Redirect-Logik bleiben erhalten. Nur die
Namespace-gebundenen Upstreams wechseln von `localhost:9091` zu Service-DNS:

| Legacy | Neu |
| --- | --- |
| `/auth/ -> localhost:9091/auth/` | `/auth/ -> authelia:9091/auth/` |
| `/static/ -> localhost:9091/auth/static/` | `/static/ -> authelia:9091/auth/static/` |
| `/authelia-auth -> localhost:9091/auth/api/authz/auth-request` | `/authelia-auth -> authelia:9091/auth/api/authz/auth-request` |

`X-Original-Method`, `X-Original-URL`, `X-Forwarded-For`,
`X-Forwarded-Proto` und `Cookie` werden weiterhin an Authelia übergeben.
Remote-User, Remote-Groups, Remote-Name und Remote-Email werden aus der
Auth-Antwort übernommen; bestehende 401- und Login-Redirect-Handler bleiben
unverändert. Policies werden nicht im Edge verändert.

## Netzwerke und reproduzierbare Pi-Route

Die Netzwerk-Ownership ist eindeutig aufgeteilt:

- Der WireGuard-Stack besitzt und erzeugt `ops-net` mit
  `172.30.90.0/24`. Der Edge-Stack konsumiert dieses Netz weiterhin als externes
  Netz.
- Der Edge-Stack besitzt und erzeugt `edge-net` mit `172.30.91.0/24`
  deklarativ als Bridge-Netz.
- Auth, Code, WebSSH und Incoming besitzen `edge-net` nicht. Sie konsumieren es
  in ihren jeweiligen Stacks als externes Netz.

`ops-net` ist für den Edge zwingend, weil die aktiven HTTP-Upstreams
`100.64.0.2` bis `100.64.0.11`, das wg-easy-UI und MQTT weiterhin erreichbar
sein müssen. Der Dienst `edge-network` bleibt sowohl mit `edge-net` als auch mit
`ops-net` verbunden; sein Alias `edge-nginx` im `edge-net` bleibt bestehen.

Ein minimaler `edge-network`-Dienst ist an beide Netze angeschlossen,
veröffentlicht die drei Edge-Ports und setzt in seinem eigenen Namespace
idempotent:

```text
100.64.0.0/24 via 172.30.90.2
```

`edge-nginx` teilt ausschließlich diesen dedizierten Edge-Netzwerk-Namespace,
nicht den von wg-easy. Der Namespace-Halter startet als `root`, setzt einmalig
die Route mit `NET_ADMIN` und wechselt anschließend mit `su-exec` auf den eigens
angelegten Benutzer `edge-network` (UID/GID 10001). `sleep infinity` hält danach
als unprivilegierter PID 1 nur den Namespace am Leben. Nginx erhält selbst keine
Capability.

Compose verwirft zunächst alle Capabilities. `NET_ADMIN` wird nur zum Setzen der
Route benötigt; `SETUID` und `SETGID` ermöglichen ausschließlich den
Privilege-Drop durch `su-exec`. `no-new-privileges:true` bleibt aktiv. Auf dem
ARM64-Zielserver wurden für PID 1 nach dem Wechsel UID/GID 10001,
`CapPrm = 0`, `CapEff = 0` und `NoNewPrivs = 1` bestätigt. Die Route blieb
vorhanden, während ein weiterer Route-Änderungsversuch als unprivilegierter
Benutzer erwartungsgemäß scheiterte. Aus demselben Namespace waren der direkte
Pi-HTTP-/MQTT-Zugriff sowie wg-easy, Authelia und WebSSH erreichbar. Damit bleibt
die Route deklarativ, ohne Hostroute, `docker network connect` oder manuelle
Runtime-Regel. Der Cutover-Test soll diese Ergebnisse als Regressionstest erneut
bestätigen.

## Incoming

`incoming-nginx:8080` bleibt unverändert. Damit Docker-DNS diesen Namen im neuen
Edge auflösen kann, muss der Incoming-Stack später seinen Nginx-Dienst zusätzlich
an das externe `edge-net` anbinden und dort ausdrücklich den Netzwerkalias
`incoming-nginx` erhalten. Ein dokumentarisches Beispiel für die spätere
Änderung im Incoming-Compose ist:

```yaml
services:
  incoming-nginx:
    networks:
      edge-net:
        aliases:
          - incoming-nginx

networks:
  edge-net:
    external: true
    name: edge-net
```

Ein manuelles `docker network connect` ohne diesen Alias genügt nicht. Die
Änderung gehört ins separate Incoming-Repository und wurde hier nicht
vorgenommen.

Der lokale Include mit Incoming-spezifischer sensitiver Konfiguration wird
nicht kopiert. Er wird separat von den versionierten Includes unter
`/etc/nginx/runtime/incoming-secret.conf` read-only eingebunden. Dadurch liegt
der Dateimount nicht mehr innerhalb des bereits read-only gemounteten
Verzeichnisses `/etc/nginx/includes`.

## MQTT TLS

Der bestehende `stream {}`-Block terminiert TLS auf Port `8883` mit dem
Zertifikat für `me.disti.jokley.at` und proxied TCP zu `100.64.0.3:1883`.
Konfiguriert sind TLS 1.2 und ein Proxy-Connect-Timeout von einer Sekunde. Der
zweite Legacy-`listen` mit einem DNS-Namen wird im Container nicht übernommen;
`listen 8883 ssl` deckt den veröffentlichten Containerport ab, ohne zu versuchen,
eine nicht im Container vorhandene öffentliche Adresse zu binden. Backend,
Zertifikatsname und WireGuard-Abhängigkeit bleiben unverändert.

Der vorgesehene Datenpfad ist:

```text
Host EDGE_MQTT_TLS_PORT
  -> Docker-Portfreigabe
  -> edge-network:8883
  -> Nginx TLS
  -> 100.64.0.3:1883 (MQTT ohne TLS)
```

Der ARM64-Runtime-Test muss über den Testport `18883` einen vollständigen
TLS-Handshake gegen den generischen Container-Listener bestätigen. Zusätzlich
sind TLS 1.2, das erwartete Zertifikat und die Weiterleitung zum unveränderten
MQTT-Backend zu prüfen. Die hostnamegebundene Legacy-Direktive wird dabei nicht
wieder eingeführt.

## Certbot, TLS-State und ACME

Certbot bleibt ein eigener Service. `${LETSENCRYPT_DIR}` wird für Nginx read-only
und für Certbot read-write nach `/etc/letsencrypt` gemountet.
`${CERTBOT_WEBROOT}` wird entsprechend read-only beziehungsweise read-write nach
`/var/www/certbot` gemountet. Beides ist externer Runtime-State und durch
`.gitignore` ausgeschlossen. Es wurden weder Zertifikate noch private Schlüssel
kopiert.

Der Renewal-Loop entspricht zunächst dem Legacy-Intervall von zwölf Stunden.
Nginx lädt wie bisher alle sechs Stunden neu. Vor dem Test sind Dateirechte,
Renewal-Konfiguration, Zertifikatsnamen und die sichere Reload-Kopplung zu
validieren. In diesem Schritt wird kein Zertifikat ausgestellt oder erneuert.

Der Certbot-Service liegt bewusst im Compose-Profil `certbot`. Ein normaler
paralleler Edge-Test startet daher ausschließlich `edge-network` und
`edge-nginx`; Certbot wird nicht automatisch gestartet und kann kein
produktives `certbot renew` auslösen. Vorhandene produktive Zertifikate dürfen
für Nginx nur über einen bewusst gewählten read-only Runtime-Mount verwendet
werden. Certbot wird erst separat oder beim kontrollierten Cutover aktiviert.

## Testmodus und Cutover-Modus

Dieselbe Compose-/Nginx-Konfiguration wird in beiden Modi verwendet. Nur die
lokale, ignorierte `.env` ändert die veröffentlichten Ports:

| Modus | `EDGE_HTTP_PORT` | `EDGE_HTTPS_PORT` | `EDGE_MQTT_TLS_PORT` |
| --- | ---: | ---: | ---: |
| isolierter Test | `18080` | `18443` | `18883` |
| späterer Cutover | `80` | `443` | `8883` |

`.env.example` lässt die Portwerte absichtlich leer. Die produktiven Ports
dürfen erst nach dem Stop des Legacy-Listeners im kontrollierten Cutover gesetzt
werden. HTTPS-Tests verwenden ausschließlich bewusst bereitgestellte read-only
Testkopien oder einen expliziten externen Runtime-Pfad; TLS-State kommt nie ins
Git.

## Lokales `.env`-Modell

`infra-new/edge/.env` enthält ausschließlich lokale Runtime-Konfiguration:
die verifizierten, nicht sensitiven Image-Digests, Test- oder Cutover-Ports,
Zeitzone, TLS-State,
ACME-Webroot und den Pfad des externen Incoming-Includes. Die Datei wird niemals
versioniert. `.env.example` enthält leere lokale Pfad-/Portfelder sowie nur die
nicht sensitiven Image-Digests und den Zeitzonenwert. Es gibt keine Secretwerte
oder realistisch aussehenden Dummy-Secrets in Git.

Privilegierte Docker-/root-Benutzer können Environmentwerte sehen. Deshalb
enthält `.env` keine Zertifikats-Private-Keys oder Auth-Tokens; sie enthält nur
Pfade zu lokal geschütztem Runtime-State.

## Startreihenfolge und Runtime-Testplan

Die deklarative Startreihenfolge beim Cutover ist:

1. Der WireGuard-Stack startet und erzeugt sein `ops-net`
   (`172.30.90.0/24`).
2. `edge-network` wird aus dem Edge-Stack gestartet. Compose erzeugt dabei das
   dem Edge-Stack gehörende `edge-net` (`172.30.91.0/24`).
3. Auth, WebSSH, Code und Incoming können anschließend das vorhandene
   `edge-net` extern konsumieren.
4. `edge-nginx` startet erst danach, sodass seine Service-DNS-Upstreams im
   `edge-net` auflösbar sind.

Ein späterer isolierter Test umfasst danach folgende Schritte:

1. Die dokumentierten produktiven Nginx-/Certbot-Digests auf dem Zielhost
   nochmals gegen die lokal verfügbaren Images prüfen.
2. Testkopien beziehungsweise bewusst isolierte Runtime-Pfade für TLS-State,
   ACME-Webroot und Incoming-Include vorbereiten.
3. Das vom WireGuard-Stack erzeugte `ops-net`, wg-easy `172.30.90.2` und seine
   NAT-Regel prüfen, ohne den aktuellen Testzustand zu verändern.
4. `edge-network` starten und damit `edge-net` deklarativ erzeugen.
5. Authelia, WebSSH und — sobald konfiguriert — code-server im `edge-net`
   bereitstellen. Incoming muss vor dem Nginx-Konfigurationstest ebenfalls am
   `edge-net` hängen, da Nginx Upstreamnamen beim Start auflöst.
6. Ausschließlich `edge-nginx` zusätzlich starten und über die drei bereits von
   `edge-network` veröffentlichten Testports prüfen; das Profil `certbot` bleibt
   deaktiviert.
7. Für PID 1 von `edge-network` UID/GID ungleich 0, `CapPrm = 0`, `CapEff = 0`
   und `NoNewPrivs = 1` messen; zugleich muss `ip route` weiterhin
   `100.64.0.0/24 via 172.30.90.2` enthalten.
8. Nginx mit read-only Test- beziehungsweise bewusst bereitgestelltem TLS-State
   starten und `nginx -t` ausführen.
9. HTTP-Redirect, ACME-Webroot, TLS, alle virtuellen Hosts, Authelia-Verhalten,
   WebSockets, direkte Pi-Upstreams, Incoming und MQTT Ende-zu-Ende testen.
10. Certbot-Konfiguration zunächst nur read-only inspizieren; Renewal erst in
   einem ausdrücklich freigegebenen separaten Test prüfen.
11. Sicherstellen, dass keine produktiven Ports, Zertifikate oder Backends
   verändert wurden und alle Testcontainer/-ports rückstandsfrei entfernen.

## Security und GitGuardian

- Kein Docker-Socket, Host-Networking oder `privileged: true`.
- Nginx-Konfiguration und TLS-State sind für Nginx read-only.
- Nur Certbot erhält Schreibzugriff auf seinen expliziten Runtime-State.
- Keine unnötig persistenten Logs; Nginx verwendet Container-Standardlogs.
- Keine Secrets, Zertifikatsdateien, privaten Schlüssel oder realistisch
  aussehenden Dummywerte im Git.
- Sensitive Incoming-Konfiguration bleibt eine externe, ignorierte Runtime-Datei.
- Die verifizierten Image-Digests sind nicht sensitiv und dürfen in
  `.env.example` und Compose stehen; lokale Port- und Pfadwerte bleiben in der
  ignorierten `.env`.

## Rollback

Der Legacy-Edge bleibt bis zum vollständigen, abgenommenen Cutover produktiv.
Bei jedem Fehler werden ausschließlich die neuen Testcontainer und Testports
entfernt. Die externen Netze, wg-easy, Authelia, Incoming, Zertifikate und der
Root-Stack bleiben unangetastet. Erst nach einem erfolgreichen End-to-End-Test,
gesichertem TLS-State und dokumentiertem Rückfallverfahren dürfen 80/443/8883 an
den neuen Edge übergeben werden.
