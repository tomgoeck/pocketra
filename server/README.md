# Mehrspieler-Vermittler

Der Vermittler (`mp_server.py`) verteilt im Mehrspieler die Befehlspakete zwischen den Clients.
Er rechnet **keine** Simulation, hat **keine** Spieluhr und schreibt **nichts** auf Platte: er
verwaltet Räume, sammelt je Netzrahmen die Pakete aller menschlichen Plätze und schickt sie
gebündelt zurück, sobald alle da sind. Entwurf und Protokoll: `docs/MULTIPLAYER.md` §3, §4 und §9.

| Datei | Zweck |
|---|---|
| `mp_server.py` | der Vermittler, eine Datei, Python 3 + `websockets` |
| `mp_smoke.py` | Prüfclients ohne Godot (Lobby, Rahmen, Desync, Abbruch, Rate-Limit, Raumliste, Teams/Startpunkte, Hintergrund, Sprechfunk) |
| `pocketra-mp.service` | systemd-Unit (`/etc/systemd/system/pocketra-mp.service`) |
| `nginx-mp.conf` | der `location /mp`-Block für die nginx-Site |
| `../tools/mp_deploy.sh` | rollt alles auf `pocketra.net` aus |

## Kurz

```
Client  ──wss://pocketra.net/mp──►  nginx (443)  ──►  127.0.0.1:8787  mp_server.py
```

* Spielcode: 6 Zeichen aus `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (ohne I, O, 0, 1).
* Höchstens 50 Räume, je Raum bis 8 Plätze (Fassung 1 der App nutzt 6).
* Ein Raum ohne Verbindung **und** ohne reservierten Platz verschwindet sofort; eine Lobby ohne
  Start nach 30 min, eine Partie ohne Verkehr nach 5 min.
* **Reservierter Platz** (2026-09-09): bricht in der Lobby eine Verbindung ab, bleibt der Platz
  `--resume-s` lang (Vorgabe 180 s) stehen und der Raum lebt weiter — Android friert die App im
  Hintergrund ein, das darf keinen Raum kosten. Mit `resume{code, token}` sitzt derselbe Spieler
  wieder darauf, samt Gastgeberrolle. `leave` gibt den Platz dagegen sofort frei.
  Einzelheiten: `docs/MULTIPLAYER.md` §10.
* Ohne Paket eines Platzes: nach 500 ms `waiting`, nach 20 s `peer_left`.
* Vorsprung höchstens 40 Rahmen (`MAX_LEAD`), Nachrichten höchstens 16 KB.

## Am Mac laufen lassen

```bash
python3 -m venv build/.venv_mp && build/.venv_mp/bin/pip install websockets
build/.venv_mp/bin/python server/mp_server.py --host 127.0.0.1 --port 8787
```

Prüfclients (startet ohne `--url` selbst einen Vermittler mit kurzen Fristen):

```bash
build/.venv_mp/bin/python server/mp_smoke.py                       # lokal, ~49 s, 132 Prüfungen
build/.venv_mp/bin/python server/mp_smoke.py --url ws://127.0.0.1:8787/mp
build/.venv_mp/bin/python server/mp_smoke.py --url wss://pocketra.net/mp
```

Der Rauchtest legt neun Räume an. Dem selbst gestarteten Vermittler gibt er dafür
`--create-per-min 30` mit; **gegen einen fremden Vermittler** (`--url`) gilt dessen Schranke „5
`create` je Minute und IP", dort melden zwei Läufe kurz hintereinander `ratelimit` — eine Minute
warten oder `--schnell` nehmen (lässt den Abbruchtest und damit einen Raum weg).

Schalter des Vermittlers:

| Schalter | Vorgabe | Bedeutung |
|---|---|---|
| `--host` | `127.0.0.1` | Adresse (hinter nginx bleibt es lokal) |
| `--port` | `8787` | Port |
| `--max-rooms` | `50` | gleichzeitige Räume |
| `--waiting-ms` | `500` | ohne Paket: ab wann `waiting` gemeldet wird |
| `--drop-s` | `20` | ohne Paket: ab wann `peer_left` kommt |
| `--resume-s` | `180` | Lobby: so lange bleibt ein Platz nach einem Abbruch reserviert |
| `--create-per-min` | `5` | Räume je Minute und IP (nur für `mp_smoke.py` heruntersetzen/anheben) |

## Ausrollen

```bash
tools/mp_deploy.sh                 # rsync, venv, systemd, nginx, Neustart, Probe
tools/mp_deploy.sh --check         # nur Zustand und Handschlag prüfen
tools/mp_deploy.sh --skip-nginx    # nginx nicht anfassen
```

Der erste Lauf legt den Systembenutzer `pocketra-mp` an, baut `/opt/pocketra-mp/venv` mit
`websockets`, installiert und aktiviert die Unit und trägt den `location /mp`-Block in
`/etc/nginx/sites-available/pocketra.net` ein — **nur** wenn `location /mp` dort noch
fehlt, danach `nginx -t` und `systemctl reload nginx`. Vor dem Eingriff legt er
`…pocketra.net.bak-mp` an und stellt die Datei zurück, falls `nginx -t` meckert.

Zum Schluss prüft das Skript den Handschlag von außen:

```bash
curl -i -N --max-time 10 --http1.1 \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://pocketra.net/mp
```

Erwartet wird `HTTP/1.1 101 Switching Protocols` mit `Sec-WebSocket-Accept`. Ohne die beiden
`Sec-WebSocket-*`-Kopfzeilen antwortet die Bibliothek mit `426` — das ist kein Fehler des Dienstes.
`--http1.1` ist Pflicht: über HTTP/2 lässt curl `Connection: Upgrade` weg und bekommt ebenfalls `426`.

## Betrieb

```bash
ssh pocketra-upload systemctl status pocketra-mp
ssh pocketra-upload journalctl -u pocketra-mp -f          # laufend mitlesen
ssh pocketra-upload journalctl -u pocketra-mp -n 200 --no-pager
ssh pocketra-upload systemctl restart pocketra-mp         # trennt laufende Partien
ssh pocketra-upload systemctl stop pocketra-mp
```

Ein Neustart ist harmlos: es liegt kein Zustand auf Platte. Laufende Partien brechen ab, die
Clients melden „Verbindung verloren" und gehen ins Menü.

### Was im Protokoll steht

Eine Zeile je Ereignis nach stdout, also nach journald. `connect`, `hello`, `create`, `join`,
`join_full`, `join_nocode`, `join_mismatch`, `map` (Kartenwechsel des Gastgebers),
`visibility` (öffentlich/privat), `slot` (Fraktion, Team, Startpunkt eines Platzes),
`start_team_fix` (der Gastgeber schickte ein veraltetes Team — der Vermittler hat es ersetzt),
`start_spawn_diff` (Startpunkt in der Aufstellung weicht vom Lobby-Wunsch ab),
`seat_absent` (Verbindung weg, Platz reserviert), `resume` (Platz zurückgeholt),
`resume_expired` (Frist abgelaufen), `watch`/`unwatch` (Beobachter des
Android-Vordergrunddienstes), `bot_add`, `bot_remove`, `kick`, `start`, `chat`
(nur Platz, Umfang und Länge — **nie** der Text), `voice` (eine Zeile je **Redezug**, also nach
2 s Stille — Platz, Kanal, Zahl der Empfänger, **nie** die Nutzdaten), `voice_oversize`,
`desync` (mit Rahmen und Hashes), `peer_left`,
`stale_frame`, `dup_frame`, `lead_kick`, `ratelimit_*`, `ban`, `oversize`, `room_closed`,
`disconnect`. Der Fehlersuche hilft:

```bash
ssh pocketra-upload "journalctl -u pocketra-mp --since '1 hour ago' -o cat | grep -E 'desync|peer_left|ratelimit'"
```

### Grenzen und Sperren

| Grenze | Wert |
|---|---|
| Nachricht | 16 KB (größere werden verworfen, `error{code:"badstate"}`) |
| Chat | 200 Zeichen, 5 Nachrichten / 5 s je Verbindung → `ratelimit` (Verbindung bleibt) |
| Andere Nachrichten | 60 / 5 s je Verbindung → `ratelimit` und Trennung |
| `order` | 600 / 5 s je Verbindung (der Gleichschritt braucht ~13/s) |
| `voice` (Sprechfunk) | 4096 Zeichen Base64 je Paket, 150 Pakete / 5 s je Verbindung (60-ms-Pakete geben ~17/s) → Paket verworfen, höchstens eine `ratelimit`-Meldung je Sekunde, Verbindung bleibt |
| `create` | 5 / min und IP (Prüfschalter `--create-per-min`) |
| `list` (Raumliste) | 1 Anfrage / 2 s je Verbindung → `ratelimit` (Verbindung bleibt) |
| `join` | 20 / min und IP |
| falsche Codes | 3 → 60 s Sperre für die IP |
| Name | 24 Zeichen |

### Wenn etwas klemmt

* **`Failed to start`, Unit tot:** `journalctl -u pocketra-mp -n 50`. Meist fehlt `websockets`
  im venv → `tools/mp_deploy.sh` erneut laufen lassen.
* **502 oder 426 statt 101:** läuft der Dienst? `ss -ltnp | grep 8787`. Steht `location /mp` in
  der Site? `grep -n 'location /mp' /etc/nginx/sites-available/pocketra.net`.
* **Verbindung fällt nach ~60 s:** `proxy_read_timeout` in der Site prüfen (600 s), der
  Vermittler selbst schickt alle 20 s einen WebSocket-Ping.
* **`desync` im Protokoll:** kein Serverfehler. Die Clients rechnen auseinander — der Rahmen und
  die Hashes im Protokoll nennen den Zeitpunkt, `user://logs/desync-<code>-<seat>.bin` auf den
  Geräten den Zustand.

## Protokoll in zwei Sätzen

Der Client meldet sich mit `hello`, legt mit `create` einen Raum an oder betritt einen mit `join`,
verstellt in der Lobby seinen Platz (`slot`, `ready`, Host: `map`, `visibility`, `bot`, `kick`,
`start`) und schickt
danach je Netzrahmen genau ein `order{frame, cmds, hash?}` — auch leer. Vor dem Beitritt holt er mit
`list` die Liste der **öffentlichen** Räume (`rooms`, eine Anfrage je zwei Sekunden). Der Vermittler
antwortet mit `welcome`, `created`, `lobby`, `rooms`, `start`, dann je Rahmen
`frame{frame, packets}`, dazwischen
`waiting`, `chat`, `desync`, `peer_left`, `pong` und im Fehlerfall `error{code}` mit einem der
Codes `full`, `nocode`, `mismatch`, `badstate`, `ratelimit`, `notallowed`, `nothost`,
`spawnoccupied` (Startpunkt schon von einem anderen Platz belegt).
Beim Anlegen und Beitreten kommt zusätzlich `session{code, seat, token, resume_s}` — **nur an diese
eine Verbindung**; damit holt `resume{code, token}` nach einem Abbruch denselben Platz zurück und
`watch{code, token}` hängt einen stillen Beobachter daran (§10).
Daneben läuft der **Sprechfunk**: `voice{scope, seq, data}` (Base64, ≤ 4096 Zeichen) wird wie der
Chat nach Team gefiltert weitergereicht — nur **nie** an den Absender zurück — und berührt den
Gleichschritt nicht (§11).
Die Felder stehen vollständig in `docs/MULTIPLAYER.md` §3, §9, §10 und §11.
