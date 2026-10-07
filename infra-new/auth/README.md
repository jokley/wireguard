# Eigenständiger Authelia-Stack: Migrationskandidat

Dieser Stack bereitet Authelia als eigenständigen Auth-Service vor. Er ist noch
nicht deployt. Das produktive Authelia im Root-Compose bleibt bis zum geprüften
Cutover unverändert und ist weiterhin die maßgebliche Instanz.

## Analysierter Legacy-Aufbau

Der Root-Compose verwendet `authelia/authelia:latest`, lädt die nicht
versionierte Datei `authelia.env`, bindet `data/authelia/config` nach `/config`
ein und setzt `network_mode: "service:wg-easy"`. Authelia teilt daher heute den
Netzwerk-Namespace mit wg-easy. Es gibt keinen eigenen Healthcheck und keine
`depends_on`-Beziehung.

Die produktive Konfiguration lauscht intern auf `0.0.0.0:9091/auth`. Sie nutzt:

- einen dateibasierten Authentication-Backend-Pfad
  `/config/users_database.yml`,
- mehrere bestehende Cookie-/Domain-Zuordnungen,
- `deny` als Default-Policy und bestehende `one_factor`-Regeln,
- lokales SQLite unter bisher `/config/db.sqlite3`,
- einen SMTP-Notifier sowie
- eine Reset-Password-Identitätsvalidierung.

Die Konfiguration enthält Einstellungen, deren Werte als Secrets zu behandeln
sind. Diese Werte wurden weder ausgegeben noch in den neuen Tree kopiert. Die
produktive User-Datei und die Legacy-Environment-Datei sind in dieser
Arbeitsumgebung nicht vorhanden; ihre Werte wurden nicht gelesen.

## Produktives Image und Version

Die produktive Runtime wurde auf dem ARM64-Zielserver eindeutig als Authelia
`v4.39.1`, Architektur `arm64`, mit folgender Referenz verifiziert:

```text
authelia/authelia@sha256:e325963609cc928861ffe8130c09111862df88dd8fcafbcd2c47e5ff0a4ae268
```

Die verifizierte Image-ID ist im Migrationsprotokoll als
`sha256:1fa2233464a981db60022ef837a968c4ed1f89fbc0fd5ccec0f6b475bcb2ab45`
festgehalten. Compose und `.env.example` verwenden den RepoDigest statt
`latest`; ein lokaler `AUTHELIA_IMAGE`-Wert kann ihn nur für einen bewusst
geprüften Test überschreiben. Beim Infrastruktur-Cutover findet kein
Authelia-Upgrade statt.

Der produktive v4.39.1-Prozess läuft als UID/GID `0:0`. Für diesen Cutover wird
kein zusätzlicher User- oder Privilege-Drop-Umbau eingeführt. Authelia erhält
trotzdem keine zusätzlichen Linux-Capabilities; ein unprivilegierter Runtime-
User bleibt ein separater Hardening-Schritt nach der funktionalen Migration.

## Zielarchitektur und Port

Authelia hängt ausschließlich am extern bereitgestellten `edge-net`. Der Stack
erzeugt kein Netzwerk, verwendet weder `ops-net` noch Host-Networking und teilt
keinen Namespace mit wg-easy. Port `9091` wird nur intern mit `expose`
dokumentiert; ein Host-Port existiert nicht.

Der zukünftige Edge-Upstream lautet unter Beibehaltung des Pfadpräfixes:

```text
http://authelia:9091/auth
```

Nginx wird in diesem Schritt nicht geändert.

## Config, User-Datei, State und Secrets

### CONFIG

`config/configuration.yml` ist die bereinigte, versionierbare Kopie der
bestehenden fachlichen Konfiguration: Serverpfad, Cookies, Domains, Policies,
Authentication-Backend, SQLite und SMTP-Struktur bleiben erhalten. Die Datei
wird read-only nach `/config/configuration.yml` gemountet. Secret-Felder sowie
der SMTP-Benutzername wurden vollständig entfernt und werden ausschließlich zur
Laufzeit injiziert.

### User-Datei

Das File-Backend erwartet `/users/users_database.yml`. Eine solche Datei kann
Passwort-Hashes, Gruppen und personenbezogene Angaben enthalten. Sie wird daher
nicht in den neuen Git-Tree kopiert. Das dedizierte Verzeichnis
`AUTHELIA_USERS_DATABASE_DIR` wird nach `/users` gemountet. Es ist absichtlich
minimal schreibbar: Der bestehende Reset-Password-Flow kann die User-Datei
aktualisieren und Implementierungen können dafür eine temporäre Datei mit
anschließendem atomarem Rename im selben Verzeichnis benötigen. Ein read-only
Einzeldatei-Mount wäre damit nicht zuverlässig kompatibel. Das Verzeichnis darf
außer der benötigten Runtime-Datei keine weiteren Daten enthalten; Rechte,
Besitzer und Backup sind vor dem Cutover zu prüfen.

### STATE

Die bestehende Architektur verwendet lokales SQLite. Der neue Config-Pfad ist
`/state/db.sqlite3`; `${AUTHELIA_STATE_DIR:-./state}` wird persistent nach
`/state` gemountet und durch `.gitignore` ausgeschlossen. Es wird keine neue
Datenbank erfunden oder initialisiert. Vor dem Cutover sind konsistentes Backup,
Dateirechte, Eigentümer, Migration der vorhandenen SQLite-Datei und Restore-Test
separat zu planen.

### SECRETS

Compose stellt die erforderlichen Werte als read-only Dateien unter
`/run/secrets/` bereit und verweist über die von Authelia unterstützten
`*_FILE`-Variablen darauf. Vorgesehen sind ausschließlich lokale Dateien für:

- Reset-Password/JWT,
- Session,
- Storage-Verschlüsselung und
- SMTP-Authentifizierung.

Die Hostpfade und `AUTHELIA_NOTIFIER_SMTP_USERNAME` werden lokal in `.env`
gesetzt. Weder die Dateien noch ihre Inhalte werden versioniert. Ob die
verifizierte Produktionsversion alle verwendeten `*_FILE`-Variablennamen
unterstützt, wird im isolierten v4.39.1-Test nochmals validiert.

Die Legacy-Namen `JWT_SECRET` und `SESSION_SECRET` werden nicht übernommen. Der
neue Stack verwendet ausschließlich die offiziellen hierarchischen
Authelia-v4.39.1-Variablennamen. Wegen der Priorität Secrets > Environment >
Files sind die vier Secret-Felder aus `configuration.yml` entfernt und werden
weder zusätzlich als normale `AUTHELIA_*`-Werte noch unter Legacy-Namen gesetzt.
Jedes Secret besitzt genau eine FILE-basierte Laufzeitquelle.

## Secret Handling / GitGuardian

- Secrets gehören niemals ins Git.
- Es werden keine realistisch aussehenden Dummy-Secrets verwendet.
- `.env.example` enthält keine Secret-Werte, sondern nur nicht-sensitive Werte
  und lokale Dateipfade.
- FILE-basierte Übergabe wird bevorzugt; README und Compose zeigen keine
  Secret-Inhalte.
- `.env`, lokale Secret-Dateien, User-Datei und State müssen ignored bleiben.
- Lokale Marker wie `SET_ME_LOCALLY` sind bewusst semantisch und keine
  Zugangsdaten.

## Healthcheck und Security

Der zuvor vorbereitete benutzerdefinierte CLI-Healthcheck wurde entfernt, weil
seine exakte Aufrufsyntax für das produktive Image v4.39.1 noch nicht durch einen
Runtime-Test belegt ist. Compose überschreibt damit keine möglicherweise im
gepinnten Image enthaltene Healthcheck-Definition. Beim isolierten Test wird die
Image-Metadatenlage geprüft und anschließend entweder der nachweislich
funktionierende Image-Healthcheck übernommen oder ein getesteter lokaler Check
ohne Internet-Abhängigkeit ergänzt. Bis dahin gilt ein fehlender bestätigter
Healthcheck als Deployment-Blocker.

Der Service besitzt keinen Host-Port, keine zusätzlichen Capabilities, keinen
Docker-Socket und keine Mounts von Host-Systempfaden, WireGuard-Daten,
SSH-Schlüsseln oder Zertifikaten. Die Config ist read-only; ausschließlich das
dedizierte User-Verzeichnis und das SQLite-State-Verzeichnis sind schreibbar.

## Spätere Edge-/Nginx-Integration

Legacy-Nginx nutzt derzeit interne `auth_request`-Locations und proxied
`/auth/`, `/static/` sowie `/auth/api/authz/auth-request` über
`localhost:9091`. Es übergibt unter anderem Host, Client-IP,
`X-Forwarded-For`, `X-Forwarded-Proto`, Prefix, Original-Methode, Original-URL
und Cookie. Die Auth-Antwort liefert User-/Gruppen-/Namens-/E-Mail-Header an die
geschützten Backends; nicht autorisierte Antworten gehen an den vorhandenen
Redirect-Handler.

Beim späteren Edge-Cutover werden ausschließlich die Authelia-Upstreams von
`localhost:9091` auf `authelia:9091` umgestellt. Pfadpräfixe, Auth-Request-
Endpoint, Forwarded-Header, Redirect-Verhalten, Cookie-Domains und Trusted-Proxy-
Annahmen müssen dabei gegen die gepinnte Authelia-Version getestet werden.
Nginx, Domains, Cookies und Policies bleiben in diesem Schritt unverändert.

## Voraussetzungen und spätere Runtime-Tests

1. Den dokumentierten RepoDigest vor dem Test nochmals gegen die lokale
   v4.39.1-Image-ID und Architektur `arm64` prüfen.
2. Unterstützung und Priorität der vier `*_FILE`-Variablen für genau v4.39.1
   bestätigen und nachweisen, dass keine doppelte Secret-Quelle existiert.
3. Image-Healthcheck inspizieren und einen lokalen, tatsächlich erfolgreichen
   Check festlegen.
4. User-Datei und SQLite konsistent sichern; Dateirechte und Restore prüfen.
5. Ausschließlich Testkopien von SQLite, User-Datei und Secret-Dateien verwenden
   und den schreibenden Reset-Password-Flow prüfen.
6. `edge-net` in einem separaten, kontrollierten Schritt bereitstellen.
7. Konfiguration validieren, Healthcheck und internen Listener `9091` prüfen.
8. Login, Gruppen, Policies, Reset-Password-Fluss, Sessions, Cookies und SMTP in
   einer isolierten Umgebung testen.
9. Forward-Auth einschließlich Headern, Redirects und Cookie-Domains mit einem
   Test-Edge prüfen.
10. Sicherstellen, dass kein Host-Port und kein Zugang außerhalb von `edge-net`
   besteht.

## Rollback

Das bestehende Legacy-Authelia bleibt bis zum erfolgreichen, abgenommenen
Cutover unverändert aktiv. Bei einem späteren Test wird ausschließlich der neue
Auth-Stack entfernt; externe Netze, Legacy-State, User-Datei, Nginx und der
produktive Root-Stack bleiben unangetastet. Ein Cutover erfolgt erst nach
geprüftem Restore- und Rückfallverfahren.
