# Mehrspieler: Gleichschritt über einen kleinen Vermittler

Stand 2026-09-06. Entwurf (Toms Auftrag „Mehrspieler", Vorgaben: Räume mit Spielcode, Spielerzahl je
Karte, Textchat in Lobby und Spiel). Referenz ist OpenRA (`reference/OpenRA/OpenRA.Game/Network/`),
abweichende Entscheidungen sind gekennzeichnet. Ergänzt `docs/ARCHITEKTUR.md` §1 (Determinismus).

## 1. Modell: Gleichschritt mit Befehlsverzögerung

Übertragen werden **Befehle, kein Zustand**. Jeder Client rechnet dieselbe Sim mit denselben Befehlen in
derselben Reihenfolge (OpenRA `OrderManager`). Der Vermittler auf Toms Server (pocketra.net) ist
ein reiner Weiterleiter mit Lobby und Zeitüberwachung: keine Sim, keine Datenbank, kein Firebase.

| Größe | Wert (Fassung 1) | Herkunft |
|---|---|---|
| `NET_FRAME_TICKS` | 2 Sim-Ticks = 80 ms | eigene Wahl (12,5 Nachrichten/s statt 25 schont Funk und Akku) |
| `ORDER_LATENCY` | 3 Netzrahmen = 240 ms | OpenRA `mods/ra/mod.yaml` `default: OrderLatency 3` |
| `SYNC_EVERY` | 10 Netzrahmen ≈ 1,6 s | OpenRA prüft jeden Rahmen; wir sparen Funk |
| Zeitschritt | fest 40 ms (`GameSpeed.TIMESTEPS[2]`) | Geschwindigkeitswahl im Mehrspieler gesperrt |

Ablauf je Netzrahmen `F` auf jedem Client:

1. Lokal gesammelte Befehle als `order{frame: F + ORDER_LATENCY, …}` senden — **immer**, auch leer
   (Herzschlag und Taktschranke zugleich).
2. Warten, bis für `F` von **jedem** Platz ein Paket vorliegt (`OrderManager.IsReadyForNextFrame`).
   Fehlt eines länger als 500 ms: HUD zeigt „Warte auf Spieler …".
3. Alle Pakete für `F` in **fester Reihenfolge** (Sitznummer aufsteigend, dann Reihenfolge im Paket)
   über `RaSim.apply_order()` in die Sim geben — auch die eigenen erst jetzt.
4. `NET_FRAME_TICKS`-mal `RaSim.step()`.
5. Ist `F % SYNC_EVERY == 0`: `RaSim.state_hash()` ins nächste `order`-Paket legen.

Der Vermittler hat keine Spieluhr; er kann nicht selbst zur Desync-Quelle werden.

### Sync-Hash und Desync

Neu in der Sim: `uint64_t World::state_hash() const` (FNV-1a wie `rules_hash()`, `save.cpp`) über
`tick_`, `rng_`, `next_id_`, Geld je Spieler und je Actor `id, type, owner, alive, pos, facing, hp,
ammo, transport, inside`, dazu Projektile (`pos`, `target`). Nicht enthalten: Effekte, Zaps,
Smudges, Sounds (Darstellung). `state_hash_full()` = Hash über `save()` nur zur Forensik beim Desync.
Brücke: `String RaSim.state_hash()` (u64 als String).

Weichen die Hashes eines Rahmens ab, schickt der Vermittler `desync{frame, hashes}`; die Clients
halten an, melden „Die Spielstände laufen auseinander (Rahmen N) — Partie beendet", schreiben
Befehlsprotokoll und `save_state()` nach `user://logs/desync-<code>-<seat>.bin` und gehen ins Menü
(OpenRA `OrderManager.OutOfSync`).

## 2. Determinismus: Prüfung unserer Sim

**In Ordnung:** ein einziger Zufallsstrom (`World::rand()`, Xorshift, `world.cpp`), kein `std::rand`,
kein `mt19937`; kein `float`/`double` in der Spiellogik (nur Render-Pfade); Actor-Reihenfolge =
Speicherreihenfolge, `unordered_map` nur per `find()`, die neun `std::sort`-Stellen haben eindeutige
Zweitschlüssel (nachgezählt beim Audit, s. `docs/ARCHITEKTUR.md` §1); **die KI liegt in der Sim** (`sim/src/ai/bot.cpp`, würfelt aus `World::rand()`) und
läuft auf allen Clients identisch mit — keine Host-Sonderrolle; Kisten ebenso (`crates.cpp`);
`zap_seed_` sitzt in der Brücke und zeichnet nur Tesla-Blitze.

**Zu beheben:**

1. **(erledigt, Paket A)** `world.cpp` `World::step()`: `if (tick_ % 5 == 0) update_visibility(0);` ist Sim-Zustand
   (`production.cpp` liest `vis_[spy_owner]` für InfiltrateForExploration, `crates.cpp` schreibt).
   **Falsch** wäre `update_visibility(lokaler Spieler)` — Client A pflegt `vis_[0]`, Client B
   `vis_[1]`, der erste Spion desynct. **Richtig:** `World::set_visibility_players(uint32_t mask)`
   aus der Aufstellung, auf allen Clients gleich; `step()` läuft über alle gesetzten Bits.
   Einzelspieler behält `mask = 1`.
2. `proto_world.gd` `_spawn_start()`: `cos`/`sin`/`randf_range` bestimmen Startzellen — libm ist
   zwischen Android-Bionic und macOS nicht bitgleich. Startzellen und Starteinheiten werden deshalb
   **in der Aufstellung übertragen**, nie je Client berechnet.
3. `_place_players()` würfelt Startpunkt/Fraktion in einer Reihenfolge, die vom lokalen Spieler
   abhängt (lokal = Index 0 würfelt zuerst) → verschiedene Actor-IDs. Aufstellung vollständig explizit.
4. **(Brückenseite erledigt, Paket A)** `gdext/src/ra_sim.cpp`: `gps_dots()`, `gps_active()`, `frozen_actors()`, `visibility_map`,
   `drain_notifications` sind fest auf Spieler 0 → `RaSim.set_local_player(int)`; dazu ~15 Stellen
   `sim.<…>(0)` in `proto_world.gd` und `status_bar.gd`.
5. **(erledigt, Paket A)** `order_*` prüft keinen Eigentümer → `RaSim.apply_order(player, cmd)` verwirft fremde Actor-IDs und
   fremde Bau-/Gebäudebefehle.
6. Synchrone Rückgabewerte (`queue_build`, `place_building`, `sell`, `activate_support_power` …)
   gibt es im Gleichschritt nicht mehr; das HUD nimmt die lesenden Prüfungen (`can_place`, `credits`,
   `build_limit_reached`, `sell_value`, `can_deploy`, `can_chrono`, `can_unload`, `enter_kind_for`,
   `free_landing_pads`) für die sofortige Vorschau, die Wirkung folgt im Netzrahmen.
7. Spielgeschwindigkeit ist im Mehrspieler gesperrt (fest 40 ms).
8. Regel-Fingerabdruck beim Beitritt: `rules_hash`, `rules_format`, `state_version`, `sim_version`,
   `pack_version`, `app_version`, SHA-256 der Karten-JSON → bei Abweichung `error{code:"mismatch"}`
   und Angebot, die Aktualisierung zu holen.

### 2.3 Aufstellung (Startzustand)

Der Host baut sie einmal in der Lobby und schickt sie im `start`; alle Clients — auch der Host —
bauen die Welt ausschließlich daraus.

```json
{ "map": "keep-off-the-grass-2", "map_sha256": "…", "seed": 1234567,
  "tick_ms": 40, "net_frame_ticks": 2, "order_latency": 3, "sync_every": 10,
  "credits": 5000, "starting_units": "none", "crates": true, "explored_map": false, "fog": true,
  "conquest_victory": true,
  "seats": [
    {"seat":0,"sim":0,"kind":"human","client":"c1","name":"Tom","faction":"soviet","team":0,
     "color":2,"spawn":3,"spawn_cell":[12,44],"start_units":[{"type":"mcv","cell":[12,44],"facing":-1}]},
    {"seat":1,"sim":1,"kind":"human","client":"c2","name":"Jan","faction":"allies","team":0,
     "color":5,"spawn":0,"spawn_cell":[51,9],"start_units":[…]},
    {"seat":2,"sim":4,"kind":"bot","level":"normal","faction":"allies","team":2,"color":1,
     "spawn":1,"spawn_cell":[51,44],"start_units":[…]}
  ],
  "alliances": [[0,1]], "visibility_players": [0,1] }
```

Die Reihenfolge in `seats` ist die Aufbaureihenfolge in `_place_players()` und legt die Actor-IDs fest.
**Maximale Spielerzahl je Raum = Startplätze der Karte** (bis 8); freie Plätze belegt der Host mit KI.

## 3. Protokoll

**Transport:** WebSocket (`WebSocketPeer`), `wss://pocketra.net/mp`, Text-Frames mit JSON,
Feld `t` ist der Typ. Pakete < 200 Byte; lesbare Mitschnitte helfen beim Fehlersuchen.

**Client → Vermittler**

| `t` | Felder | Bedeutung |
|---|---|---|
| `hello` | `proto:1, app, pack, sim, state_version, rules_hash, rules_format, name` | erste Nachricht |
| `create` | `map, map_sha256, max_players, settings{…}, public, map_name?` | Raum anlegen (max_players = Startplätze der Karte); `public` stellt ihn in die Raumliste, Vorgabe **privat** |
| `join` | `code, map_sha256` | Raum betreten (Ablehnung `full`, wenn alle Plätze belegt) |
| `map` | `map, map_sha256, seats, settings?, map_name?` | Karte in der Lobby wechseln — **nur der Host** |
| `list` | – | Raumliste holen (nur öffentliche Räume); höchstens **eine Anfrage je 2 s** und Verbindung |
| `visibility` | `public: bool` | Raum öffentlich/privat schalten — **nur der Host**, nur in der Lobby |
| `slot` | `seat?, faction, team, color, spawn` | Platz ändern (Lobby); ohne `seat` der eigene, mit `seat` ein fremder — **nur der Host** (KI-Plätze). Belegter Startpunkt → `spawnoccupied` |
| `bot` | `add\|remove, seat?, level, faction, team` | nur der Host |
| `kick` | `seat` | nur der Host (Lobby) |
| `ready` | `on: bool` | Bereitschaft |
| `start` | `setup{…}` | nur der Host, Aufstellung nach §2.3 |
| `order` | `frame, cmds:[[…]], hash?` | eine je Netzrahmen, auch mit `cmds: []` |
| `chat` | `text, to: "all"\|"team"` | Lobby und Spiel; läuft nicht durch die Sim |
| `voice` | `scope: "all"\|"team", seq, data, codec?, end?` | Sprechfunk; `data` = Base64, ≤ 4096 Zeichen; läuft nicht durch die Sim (§10) |
| `ping` | `id` | Umlaufzeit |
| `leave` | – | sauber verlassen |

**Vermittler → Client**

| `t` | Felder |
|---|---|
| `welcome` | `client_id, server, proto` |
| `created` | `code, host: true` |
| `lobby` | `code, host, map, map_name, map_sha256, max_players, settings, public, clients:[{client_id, seat, name, faction, team, color, spawn, ready, ping, bot?}]` |
| `rooms` | `rooms:[{code, map, map_name, seats_used, seats_total, started, host_name, public}]` — Antwort auf `list` |
| `start` | `setup{…}` (vom Host, um `client_id → seat` ergänzt) |
| `frame` | `frame, packets:[{seat, cmds, hash?}]` — gebündelt, sobald **alle** da sind |
| `waiting` | `frame, seats:[…]` — nach 500 ms ohne Paket |
| `chat` | `seat, name, color, to, text, ts` |
| `voice` | `seat, name, color, scope, seq, codec, data, end?` — **nie** an den Absender zurück |
| `desync` | `frame, hashes:{seat: "…"}` |
| `peer_left` | `seat, frame` |
| `pong` | `id, t_server` |
| `error` | `code, field?, text` — `full, nocode, mismatch, badstate, ratelimit, notallowed, nothost, spawnoccupied` |

### Befehls-Serialisierung

Flaches Ganzzahl-Feld `[op, a, b, c, d, n, id…]`; `player` steht **nicht** darin (der Vermittler
stempelt den Platz). `game/scripts/net/net_orders.gd` hält Tabelle und Umsetzung.

| op | Befehl | a | b | c | d | ids |
|---|---|---|---|---|---|---|
| 0 | `order_move` | x | y | queued | – | Einheiten |
| 1 | `order_attack_move` | x | y | queued | – | ✓ |
| 2 | `order_attack` | Ziel-ID | queued | force | – | ✓ |
| 3 | `order_attack_cell` | x | y | – | – | ✓ |
| 4 | `order_stop` | – | – | – | – | ✓ |
| 5 | `order_scatter` | – | – | – | – | ✓ |
| 6 | `order_guard` | Ziel-ID | queued | – | – | ✓ |
| 7 | `order_harvest` | x | y | – | – | ✓ |
| 8 | `order_deliver` | Raffinerie-ID | – | – | – | ✓ |
| 9 | `order_deploy` | – | – | – | – | ✓ |
| 10 | `order_enter` | Ziel-ID | – | – | – | ✓ |
| 11 | `order_capture` | Ziel-ID | – | – | – | ✓ |
| 12 | `order_demolish` | Ziel-ID | – | – | – | ✓ |
| 13 | `order_infiltrate` | Ziel-ID | – | – | – | ✓ |
| 14 | `order_disguise` | Ziel-ID | – | – | – | 1 |
| 15 | `order_enter_transport` | Transport-ID | – | – | – | ✓ |
| 16 | `order_unload` | – | – | – | – | ✓ |
| 17 | `order_lay_mine` | – | – | – | – | ✓ |
| 18 | `order_detonate` | – | – | – | – | ✓ |
| 19 | `order_chrono` | x | y | – | – | ✓ |
| 20 | `order_repair` | Depot-ID | – | – | – | ✓ |
| 21 | `order_resupply` | Ziel-ID | – | – | – | ✓ |
| 22 | `order_land` | x | y | – | – | ✓ |
| 23 | `order_paradrop` | x | y | – | – | 1 |
| 24 | `set_stance` | Haltung | – | – | – | 1 |
| 30 | `queue_build` | Typ | – | – | – | – |
| 31 | `cancel_build` | Art | Typ | – | – | – |
| 32 | `pause_build` | Art | hold | – | – | – |
| 33 | `place_building` | Typ | x | y | – | – |
| 34 | `sell` | – | – | – | – | 1 |
| 35 | `toggle_repair` | – | – | – | – | 1 |
| 36 | `set_rally` | x | y | – | – | 1 |
| 37 | `set_primary` | – | – | – | – | 1 |
| 40 | `activate_support_power` | Art | x | y | x2\|y2 | – |
| 50 | Aufgeben | – | – | – | – | – |

Alles andere (`spawn`, `give_credits`, `set_alliance`, `enable_bot`, `set_handicap`, `reveal`,
`set_crate_spawner`, `set_faction`, `set_conquest_victory`) ist Aufbau und läuft nur einmal aus der
Aufstellung. **Regel ohne Ausnahme:** die Oberfläche ruft nie mehr direkt `sim.order_*`, sondern
`world.issue(cmd)` — im Einzelspieler sofort, im Mehrspieler über das Netz für `F + ORDER_LATENCY`.
`issue()` schreibt nebenbei das Befehlsprotokoll (Wiederholung).

## 4. Der Vermittler

Python 3 (`asyncio` + `websockets`; Server ist Debian Bookworm mit Python 3.11), eine Datei
`server/mp_server.py`, keine Datenbank, kein Zustand auf Platte.

* Räume: `code` = 6 Zeichen aus `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (`secrets.choice`),
  `MAX_ROOMS = 50`, je Raum höchstens `max_players` (≤ 8) menschliche Verbindungen. Raum ohne
  Verbindung **und ohne reservierten Platz** wird verworfen (§10: ein Abbruch in der Lobby
  reserviert den Platz 180 s); Lobby ohne Start nach 30 min, Partie ohne Verkehr nach 5 min.
* Takt: keiner. Sammelt je Rahmen die Pakete, bündelt `frame`, sobald alle da sind; höchstens
  `MAX_LEAD = 40` Rahmen Vorsprung (sonst `badstate` + Trennung).
* Zeitüberschreitung: 500 ms → `waiting`; 20 s → `peer_left{seat, frame}`, die übrigen tragen
  leere Pakete für den Platz ein und spielen weiter (OpenRA `ClientDisconnected`). Fassung 1 ohne
  Wiedereinstieg.
* Chat: `chat` wird mit Platz, Name, Farbe und Zeit an alle (oder nur an das Team) weitergereicht;
  Länge ≤ 200 Zeichen, kein HTML, 5 Nachrichten/5 s je Client.
* Sprechfunk: `voice` wird mit Platz, Name und Farbe an alle (oder nur an das Team) weitergereicht,
  **nie** an den Absender selbst; `data` ≤ 4096 Zeichen und nur Base64, eigener Eimer
  150 Pakete/5 s je Verbindung (60-ms-Pakete geben ~17/s). Ein Verstoß verwirft das Paket und
  meldet höchstens einmal je Sekunde `ratelimit` — die Verbindung bleibt. Protokolliert wird eine
  Zeile je **Redezug** (nach 2 s Stille), nie die Nutzdaten (§10).
* Sicherheit: 5 `create`/min und IP, 20 `join`/min und IP, drei falsche Codes → 60 s Sperre,
  Nachrichten > 16 KB verworfen, Namen ≤ 24 Zeichen. `cmds` wird nur formal geprüft.
* Protokoll: eine Zeile je Ereignis nach stdout (journald), Desync mit Rahmen und Hashes.

systemd `/etc/systemd/system/pocketra-mp.service` (User `pocketra-mp`, `ExecStart
/opt/pocketra-mp/venv/bin/python /opt/pocketra-mp/mp_server.py --host 127.0.0.1 --port 8787`,
`Restart=always`, `MemoryMax=256M`, `ProtectSystem=strict`). nginx in
`/etc/nginx/sites-available/pocketra.net` (443-Block):

```nginx
location /mp {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    proxy_buffering off;
}
```

Ausrollen: `tools/mp_deploy.sh` (rsync nach `/opt/pocketra-mp/` über den SSH-Alias
`pocketra-upload`, `systemctl restart pocketra-mp`, `is-active`). Docroot `/var/www/pocketra` bleibt.

### 4.1 Umsetzung (Stand 2026-09-06, läuft auf `wss://pocketra.net/mp`)

`server/mp_server.py` (eine Datei, `asyncio` + `websockets` 17 im venv `/opt/pocketra-mp/venv`,
Debian Bookworm mit Python 3.11) setzt §3 und §9 vollständig um. Betrieb, Logs und Fehlersuche
stehen in `server/README.md`. Ausrollen mit `tools/mp_deploy.sh` (idempotent: Benutzer, venv und
der nginx-Block entstehen nur, wenn sie fehlen), prüfen mit `server/mp_smoke.py` (57 Prüfungen,
lokal wie gegen den Server grün).

Kleine Zusätze zum Entwurf — nichts umbenannt, nur ergänzt:

* **`ping{id, rtt?}`:** der Vermittler kann die Umlaufzeit nicht selbst messen (er hat keine
  Uhr im Gleichschritt). Der Client hängt seine zuletzt gemessene Zeit in Millisekunden an; sie
  landet unverändert in der `ping`-Spalte der `lobby`. Ohne `rtt` steht dort 0.
* **`lobby.map_sha256`:** zusätzlich zu §9, damit ein Beitretender vor dem Start sieht, welche
  Karte gemeint ist.
* **`peer_left.reason`:** `gone` (Verbindung war schon weg) oder `timeout` (Verbindung steht,
  aber es kam kein Paket).
* **Rahmenzählung:** der Vermittler legt sich nicht fest, wo die Zählung beginnt — der erste
  `order` nach dem `start` setzt den ersten zu bündelnden Rahmen. So passt jede Wahl von
  `ORDER_LATENCY` in der App.
* **Nach `peer_left`** enthält das Bündel den Platz nicht mehr; die leeren Pakete tragen die
  Clients selbst ein (so steht es oben).
* **Rate-Limits getrennt:** `order` bekommt ein eigenes, weites Fenster (600 je 5 s; der
  Gleichschritt braucht ~13/s, `MAX_LEAD` hält ohnehin dagegen), alles andere 60 je 5 s →
  `ratelimit` und Trennung. Chat bleibt bei 5 je 5 s **ohne** Trennung (§9).
* **`full`** kommt auch, wenn `MAX_ROOMS` erreicht ist (nicht nur bei vollem Raum).
* **Prüfschalter** `--waiting-ms` und `--drop-s` verkürzen die Fristen für `mp_smoke.py`; im
  Dienst stehen sie auf 500 ms und 20 s.
* **`map{map, map_sha256, seats, settings?}`** (2026-09-06, Toms Befund „die Karte muss ich in der
  Lobby sehen und wechseln können"): nur der Host, nur in der Lobby (sonst `nothost` bzw.
  `badstate`). Der Raum bekommt Karte, Prüfsumme und Platzzahl neu; **Plätze jenseits der neuen
  Platzzahl werden geräumt** (ein Mensch dort bekommt `full` und wird getrennt, KI-Plätze fallen
  still weg), **Startpunkte gehen auf −1** und die **Bereitschaft auf den Stand direkt nach
  `create`** (nur der Host bleibt bereit). Danach eine `lobby` an alle. `settings` ist freiwillig —
  fehlt es, bleiben die Einstellungen des Raums stehen. **Der Vermittler muss dafür neu ausgerollt
  werden** (`tools/mp_deploy.sh`).

* **Teams und Startpunkte (2026-09-09, Toms Befund „Mein Partner hatte auch Team 1, war aber im
  Gegnerteam; ich konnte auch nicht sehen, welches Team er hat"):** drei Ergänzungen, alle
  abwärtskompatibel — ein alter Client schickt weiter `slot{faction, team, color, spawn}` und
  bekommt dieselbe `lobby` wie bisher.
  * **`slot{seat?}`:** ohne `seat` gilt der eigene Platz (wie bisher). Mit `seat` setzt **nur der
    Gastgeber** einen fremden Platz — sonst `nothost`. Damit bekommen KI-Plätze eine Teamzahl;
    OpenRA erlaubt dasselbe (`LobbyCommands.Team`/`Spawn`: „Only the host can change other
    client's info").
  * **`spawnoccupied`:** ein Startpunkt, den schon ein anderer Platz hält, wird abgewiesen und der
    alte Wert bleibt stehen (OpenRA `SpawnOccupied`, LobbyCommands.cs:1169). `-1` heißt „zufällig"
    und ist nie belegt. Vorher nahmen zwei Spieler denselben Punkt, und der Gastgeber schob beim
    Bauen der Aufstellung still einen davon weg. Nach `map` stehen alle Punkte wieder auf −1, es
    kann also keine Altlast geben.
  * **`start` stempelt Team und Farbe:** der Gastgeber baut die Aufstellung aus **seiner Abschrift**
    der Lobby. Wechselt jemand sein Team, während der `start` schon unterwegs ist, stünde dort die
    alte Zahl — beide wären im Spiel Gegner, obwohl die Lobby bei allen „Team 1" zeigt. Der
    Vermittler setzt deshalb in jedem `seats`-Eintrag `team` und `color` auf seinen eigenen Stand
    (er stempelt ohnehin schon `client_id`, `kind` und `name`). Fraktion, Startpunkt, Startzelle
    und Starteinheiten bleiben beim Gastgeber — nur er löst „zufällig" auf und rechnet die Zellen
    aus (§2.3, §2 Punkt 2). Weicht der Startpunkt vom Lobby-Wunsch ab, steht das als
    `start_spawn_diff` im Protokoll. OpenRA kennt das Problem nicht: dort startet der Server selbst
    aus seiner `LobbyInfo` (`Server.cs StartGame`).
  * **Der Vermittler muss dafür neu ausgerollt werden** (`tools/mp_deploy.sh`). Ohne den neuen
    Vermittler bleibt es beim alten Verhalten; die App läuft trotzdem (die Zusatzfelder werden
    ignoriert).

## 5. Die App

* Menü „Mehrspieler" (`game/scripts/menu/multiplayer_page.gd`): *Erstellen* → Kartenliste wie im
  Gefecht (Name, Größe, Plätze), Vorschaubild mit nummerierten Startpunkten (Tipp = bildschirmfüllend)
  und die Einstellungen Startgeld, Starteinheiten, Kisten, Karte erkundet, Nebel und KI-Stärke, dann
  Lobby mit großem Spielcode; *Beitreten* → Code eingeben. Im Querformat zwei Spalten (Liste links,
  Vorschau und Einstellungen rechts).
* **Sichtbarkeit** (2026-09-07): unter den Einstellungen der Erstellen-Seite steht „Sichtbarkeit:
  Öffentlich / Privat" — Vorgabe **privat**, damit eine Runde unter Freunden nicht ungewollt
  gelistet ist. In der Lobby schaltet ein Knopf unter dem Spielcode um („Öffentlicher Raum" /
  „Privater Raum", `visibility{public}`); Gäste sehen den Zustand nur als Zeile.
* **Öffentliche Räume** (2026-09-07): unter der Codeeingabe der Beitreten-Seite steht die Liste der
  öffentlichen Räume — je Zeile die Kartenvorschau als Miniatur, Kartenname und Gastgeber,
  belegte/gesamte Plätze, Zustand (Lobby / läuft) und der Spielcode. Ein **Tipp auf die Zeile tritt
  bei** (derselbe Weg wie ein eingetippter Code, laufende Partien sind ausgegraut). Die Seite hält
  dafür eine Verbindung zum Vermittler und holt die Liste alle drei Sekunden neu, solange sie offen
  ist; „Zurück" baut die Verbindung wieder ab. Leere Liste → „Gerade keine öffentlichen Räume".
* Lobby (`multiplayer_lobby.gd`): Kartenvorschau mit **nummerierten Startpunkten in Spielerfarben**,
  je Platz eine Zeile (Name, Fraktion, Farbe, Team, Startpunkt, Bereit, Ping), Host fügt KI-Plätze
  hinzu/entfernt/wirft raus, **wechselt die Karte** und startet, wenn alle bereit sind;
  **Chatfenster** mit Verlauf und Eingabezeile.
* **Fremde Plätze lesbar** (2026-09-09, Toms Befund „Ich konnte nicht sehen, welches Team er hat"):
  Fraktion, Team und Startpunkt eines fremden Platzes stehen als **helle Beschriftung** in der
  Zeile, nicht mehr als abgeblendeter Knopf (graue Schrift auf grauem Blech war am Handy kaum zu
  lesen und gaukelte Bedienbarkeit vor). Ein gesetztes Team steht in Gold, „–" (kein Team) gedämpft.
  Der **Gastgeber** bedient zusätzlich die KI-Zeilen (Fraktion und Team, `slot{seat}`) — sonst
  bliebe jede KI auf „kein Team" und ein Team-Gefecht mit KI wäre nicht einzustellen.
* Kartenvorschau (`game/scripts/ui/map_preview.gd`, von beiden Seiten benutzt): Tipp auf das kleine
  Bild öffnet die bildschirmfüllende Karte; dort tragen belegte Startpunkte die Farbe ihres Platzes
  und sind gesperrt, freie sind antippbar — der Tipp schickt `slot{spawn}` (Host **und** Gäste), ein
  Tipp auf den eigenen Punkt stellt wieder „zufällig" ein. Der Aufbau folgt der Gefecht-Seite
  (`main_menu.gd _show_map_overlay`, Vorbild OpenRA `MapPreviewWidget`).
* Im Spiel: oben rechts Ping und Rahmenrückstand; „Warte auf <Name> …" mit Sekundenzähler bei
  `waiting`; „Verbindung verloren" mit Abbruch; **Chat**: Knopf in der Knopfleiste öffnet die
  Eingabezeile (an alle / an Team), die letzten Zeilen erscheinen oben links in Spielerfarbe und
  blenden nach 8 s aus, Verlauf im Pausenmenü unter **„Spieler"** (§12).
* Ende: `win_state(local_player)`; Endkarte mit allen Plätzen; Verlierer darf zuschauen. Aufgeben
  im Pausenmenü (op 50).
* Wiederholung: `order_log.gd` schreibt Aufstellung und jeden Rahmen nach
  `user://replays/<code>-<datum>.rajson`; Wiedergabe kommt nach Fassung 1.

**Fassung 1:** bis zu 8 Plätze je Karte (Menschen und KI gemischt), Chat in Lobby und Spiel, eine
Karte aus der Gefechtsliste, kein Wiedereinstieg, kein Zuschauen von außen, keine
Geschwindigkeitswahl, keine Missionen. Die **öffentliche Raumliste** kam am 2026-09-07 dazu (§4.1).
**Später:** Wiedereinstieg über Token (Vermittler hält die Befehlsliste vor), Replay-Wiedergabe,
Rangliste.

## 6. Aufgabenpakete

**A — Sim und Brücke: umgesetzt** (2026-09-06, Zweig `feature/mp-sim`). Endgültige Signaturen:

```cpp
// sim/include/ra/sim.h — World
uint64_t state_hash() const;                                   // Gleichschritt-Prüfsumme
uint64_t state_hash_full();                                    // Forensik, nur nach Partieende
void     set_visibility_players(uint32_t mask);                // Bit je Spielerindex, Vorgabe 1
uint32_t visibility_players() const;
void     set_rng_seed(uint32_t seed);                          // 0 → Vorgabewert
bool     apply_order(int32_t player, const int32_t* cmd, size_t n);
void     render(int32_t alpha_1024, RenderActor* out, int32_t viewer = 0) const;
```

```gdscript
# gdext/src/ra_sim.* — RaSim (Godot)
sim.set_local_player(player: int) -> void       # nur Anzeige, nie Sim
sim.local_player() -> int
sim.set_visibility_players(mask: int) -> void
sim.visibility_players() -> int
sim.set_rng_seed(seed: int) -> void
sim.state_hash() -> String                      # u64 als Hexstring, wie rules_hash()
sim.state_hash_full() -> String
sim.apply_order(player: int, cmd: PackedInt32Array) -> bool
sim.visibility_map(owner: int = -1) -> PackedByteArray      # -1 = örtlicher Spieler
sim.drain_notifications(owner: int = -1) -> PackedInt32Array
```

Dazu ohne Signaturänderung auf `set_local_player` umgestellt: `gps_dots()`, `gps_active()`,
`frozen_actors()`, `render_buffer()` (`apply_frozen`) und der Nebel im Render-Abzug. Die vorhandenen
`order_*`, `queue_build`, `place_building` … bleiben unverändert — Missionsskripte und Tests rufen
sie weiter direkt; `apply_order` ist der **einzige** Weg aus dem Netz.

`apply_order` verwirft fremde und tote Actor-Kennungen und stempelt Bau-, Gebäude-, Superwaffen- und
Aufgabe-Befehle auf `player` (den `sim`-Index der Aufstellung, nicht die Sitznummer). Der Rückgabewert
sagt „zugestellt", nicht „gelungen": `false` nur bei unbekanntem `op`, zu kurzem Feld, unmöglichem
Spieler oder wenn **alle** Kennungen fremd waren. Zwei Festlegungen zur Tabelle §3, die dort offen
blieben: `queued` (op 0/1 Feld `c`, op 2/6 Feld `b`) hängt den Befehl über `queue_order()` an, und
`d` bei op 40 trägt die zweite Zelle gepackt — obere 16 Bit `x`, untere 16 Bit `y`, `d < 0` = keine.

Neue Tests in `sim/tests/test_sim.cpp` (`sim/tests/run.sh`, alle grün):

* `test_mp_lockstep` — zwei Welten, gleicher Seed, gleiche Befehlsfolge über `apply_order` (Bewegung,
  angereihte Befehle, Bauleiste, Platzierung, Haltung, Stopp) plus ein KI-Platz, 5000 Ticks:
  `state_hash()` **Tick für Tick** gleich, am Ende auch `state_hash_full()`.
* `test_mp_desync_detected` — ein einziger Credit Unterschied bei Tick 600 fällt in Tick 601 auf.
* `test_mp_visibility_mask` — Maske 1 lässt die Karte des zweiten Spielers leer; Maske 0b11 pflegt
  beide und ergibt auf zwei Clients dieselben Karten; sechs Plätze mit 0b110011 pflegen 0/1/4/5 und
  lassen 2/3 (Neutral, Creeps) leer.
* `test_mp_apply_order_owner` — fremde Kennung verworfen, gemischte Liste teilweise angewandt,
  Baubefehl auf den Absender gestempelt, fremdes Gebäude nicht verkäuflich, kaputte Felder abgewiesen,
  op 50 trifft nur den Absender.
* `bench_visibility` — Kosten der Sichtbarkeit, s. u.

**Messung** (M-Mac, 64×64, 42 Actors, `-O2`): eine Auflösung 4,8 µs; ganzer Tick 11,9 µs bei einem
Betrachter, 13,7 µs bei drei, 15,7 µs bei sechs — rund 1 µs je zusätzlichem menschlichen Platz gegen
40 000 µs Budget bei 25 Hz. Die Maske ist damit kein Kostenproblem. `RaSim.last_step_usec()` gab es
schon und ist gebunden.

**Nicht enthalten (Stufe 2, eigener Commit):** `MAX_PLAYERS` 10, Neutral/Creeps auf 8/9, `detected_`
auf `uint16_t`, `SAVE_VERSION` hoch. Fassung 1 bleibt bei sechs bespielbaren Plätzen (§9).

Der Determinismus-Audit steht in `docs/ARCHITEKTUR.md` §1 („Determinismus-Audit"): kein `float` in
`sim/`, ein Zufallsstrom, `unordered_map` nie iteriert, **neun** (nicht vier) `std::sort`-Stellen —
alle mit Zweitschlüssel.

**B — Vermittler** — **fertig, ausgerollt (2026-09-06)**, Zweig `feature/mp-server`.
`server/mp_server.py`, `server/mp_smoke.py`, `server/pocketra-mp.service`, `server/nginx-mp.conf`,
`server/README.md`, `tools/mp_deploy.sh`: Protokoll §3 und §9 vollständig (hello/create/join/slot/
bot/kick/ready/start/order/chat/ping/leave → welcome/created/lobby/start/frame/waiting/chat/desync/
peer_left/pong/error), Räume mit Sechs-Zeichen-Code, `seats` je Raum bis 8, Host-Rechte mit
`nothost`, Raumliste (`create.public`/`list`/`visibility`), Rahmensammlung und gebündeltes `frame`,
`waiting` nach 500 ms, `peer_left` nach 20 s,
`MAX_LEAD` 40, Hash-Vergleich → `desync`, Chat mit Teamfilter und Rate-Limit, Sperren nach §4,
16-KB-Grenze, eine Protokollzeile je Ereignis, Aufräumen leerer Räume. Abweichungen und Zusätze:
§4.1. Läuft unter systemd auf `wss://pocketra.net/mp`; `server/mp_smoke.py` (76 Prüfungen,
vier Clients auf sechs Plätzen, 200 Rahmen, Kartenwechsel, Desync, Abbruch, Rate-Limit, Raumliste)
ist lokal grün. Offen für Fassung 2: Wiedereinstieg über Token.

**C — App: umgesetzt** (2026-09-06, Zweig `feature/mp-app`, gegen A und B gemessen).

| Datei | Inhalt |
|---|---|
| `game/scripts/net/net_orders.gd` | Befehlstabelle §3, `make()`/`apply()`; `apply()` geht über `RaSim.apply_order`, ohne die Brücke über die alten `order_*` |
| `game/scripts/net/net_client.gd` | `WebSocketPeer`, alle Nachrichten aus §3, Signale, Reconnect in der Lobby, Ping (`ping{id, rtt}`), URL aus `--mp`/`--mp-url`/`settings.cfg` |
| `game/scripts/net/net_session.gd` | Rahmenpuffer, `ORDER_LATENCY`, Schranke „alle Pakete da", Sync-Hash alle `SYNC_EVERY` Rahmen, feste 40 ms |
| `game/scripts/net/order_log.gd` | Aufstellung und Rahmen nach `user://replays/<code>-<datum>.rajson` |
| `game/scripts/net/net_hub.gd` | Autoload `Net`: Verbindung, Lobby, Chat und Sitzung über den Szenenwechsel; `build_setup()` nach §2.3 (nur der Host würfelt) |
| `game/scripts/menu/multiplayer_page.gd` | Erstellen (Kartenliste, Vorschau, Einstellungen, Umschalter Öffentlich/Privat) und Beitreten (sechs Codefelder, darunter die Liste der öffentlichen Räume) |
| `game/scripts/menu/multiplayer_lobby.gd` | Spielcode, Umschalter Öffentlich/Privat (Host), Kartenvorschau mit Startpunkten, Zeile je Platz, KI hinzufügen/rauswerfen, Kartenwechsel, Start |
| `game/scripts/ui/map_preview.gd` | gemeinsame Kartenvorschau: kleines Bild mit nummerierten Startpunkten, bildschirmfüllende Überlagerung, Startpunktwahl |
| `game/scripts/ui/chat_panel.gd` | Verlauf, sechs Kurzrufe, Eingabezeile, Umschalter „an alle / an Team" |

Änderungen: `proto_world.gd` (`issue()`, `local_player`, `_apply_setup()`, Tick-Schleife über
`net_session.pump()`), `proto_main.gd` (Chatknopf, Chatzeilen, Ping/Rückstand, „Warte auf …",
„Verbindung verloren", Aufgeben op 50, Spielerliste samt Chatverlauf im Pausenmenü (§12), Endkarte über alle Plätze),
`main_menu.gd` (Knopf „Mehrspieler", zwei Seiten, Prüfhaken), `build_bar.gd`/`status_bar.gd`/
`minimap.gd` (`local_player`), `gesture_recognizer.gd` (`input_blocked`), `hud_theme.gd`
(`chat_icon()`), `project.godot` (Autoload `Net`), `strings.csv` (56 Zeilen de/en).

**Offen für Fassung 2:** Wiedergabe der `.rajson`-Dateien, Wiedereinstieg, Farbwahl in der Lobby
(heute vergibt der Vermittler die Farbe fest über die Sitznummer).

Reihenfolge (erledigt): A und B parallel; C gegen B (Netzschicht, Lobby, Chat) und zieht A ein, sobald
`state_hash`/`apply_order` stehen.

## 7. Testplan

1. Zwei Instanzen am Mac gegen `python3 server/mp_server.py`: `--mp ws://127.0.0.1:8787/mp
   --mp-create` bzw. `--mp-join CODE`; beide protokollieren jeden 10. Rahmen `frame, tick,
   state_hash`; `tools/mp_diff.py` nennt den ersten abweichenden Rahmen.
2. Kopflos: `--mp-autoplay 3000` mit identischem Befehlsskript auf beiden Seiten.
3. Desync mit Absicht: `--mp-corrupt N` (einmal `give_credits` auf einer Seite) → `desync`.
4. Verzögerung: `--mp-lag 200 --mp-jitter 80`; bei 400 ms „Warte auf Spieler", aber synchron.
5. Abbruch: einen Client hart beenden → `peer_left` nach 20 s, der andere spielt weiter.
6. Handy gegen Mac (verschiedene libm/Compiler) — der eigentliche Prüfstein.
7. Fingerabdruck: Client mit älterem Paket → `mismatch` statt Desync.
8. Chat: Nachrichten in Lobby und Spiel kommen bei allen an, Team-Chat nur beim Team.

### Gemessen am 2026-09-06 (Zweig `feature/mp-app`, Mac, `tools/mp_local_test.sh`)

| Lauf | Ergebnis |
|---|---|
| 2 Instanzen, `keep-off-the-grass-2`, 400 Netzrahmen (800 Ticks) | desync-frei, jeder Sync-Hash gleich |
| 2 Instanzen, 700 Rahmen, eine Seite 5 s per `SIGSTOP` angehalten | „Warte auf Jan … (0 s)", danach synchron weiter, desync-frei |
| 4 Instanzen, `great-sahara-2` (8 Startpunkte → 4 belegt), 600 Rahmen | alle vier Hashes gleich; seat 0/1/2/3 → Sim 0/1/4/5 |
| 4 Instanzen, 1900 Rahmen (3800 Ticks), 511 Chatzeilen über den Vermittler | alle vier Hashes gleich — Chat ändert den `state_hash` nicht (§9) |
| Vermittler mitten in der Partie beendet | beide Seiten „Verbindung verloren" mit Endkarte über alle Plätze |
| `--test-layout` (12 Größen × de/en, Seiten `multiplayer` und `mp_lobby` dazu) | 0 Verstöße |

### Nachgemessen am 2026-09-09 (Zweig `feature/mp-sprechfunk`, §10)

| Lauf | Ergebnis |
|---|---|
| `server/mp_smoke.py` (mit Abschnitt 8 „Sprechfunk") | 100 geprüft, 0 Fehler |
| `--test-sprechfunk` (Codec, Knopfsitz und Tippflächen, Kanalfarben, Sprecheranzeige, Stummschalten, Erstinfo de/en, Mikrofonprobe, Layoutmatrix, untere Leiste gegen den Einzelspieler) | 0 Befunde, Rauschabstand 25,8 dB, 328 Zeichen je Paket, Tippflächen 48×48 Geräte-dp, 10 von 10 Knöpfen deckungsgleich |
| `--test-mikrofon 5` (echte Aufnahme, Stufe für Stufe) | Kette belegt: 48 000 Frames/s, 96 % ≠ 0, roh 0,1805 → Block 0,1763 → 12 Blöcke → 12 Pakete; Schleuse an acht eingespeisten Pegeln und alle drei Notbremse-Gründe 0 Befunde |
| 2 Instanzen, 250 Netzrahmen, `FUNK=team sh tools/mp_local_test.sh` | beide hören einander (`MP-FUNK seat N an`), `tools/mp_diff.py`: desync-frei |
| `--test-layout` (Spiel und Menü) | je 0 Verstöße |
| `--test-cycle` | Menü → Gefecht → Menü → Mission → Menü ohne Skriptfehler |

### Nachgemessen am 2026-09-06 (Zweig `feature/mp-lobby`, Kartenwahl und Lobby-Optik)

| Lauf | Ergebnis |
|---|---|
| `server/mp_smoke.py` (mit den neun neuen Prüfungen zur Nachricht `map`) | 57 geprüft, 0 Fehler |
| 2 Instanzen, `keep-off-the-grass-2`, 400 Netzrahmen | desync-frei, Hash gleich |
| `--test-layout` (12 Größen × de/en, dazu `multiplayer:create` und `multiplayer:join`) | 0 Verstöße |
| `--test-cycle` | Menü → Gefecht → Menü → Mission → Menü ohne Skriptfehler |

Prüfhaken dafür: `--mp-demo-lobby` füllt die Lobby ohne Vermittler mit Beispieldaten (sonst prüfte
die Matrix eine leere Fläche), `--mp-demo-zoom` schlägt zusätzlich die große Karte auf,
`--mp-demo-create` öffnet die Kartenwahl der Erstellen-Seite, `--mp-demo-join` die Beitreten-Seite
mit vier Beispielräumen in der Raumliste (solange Beispieldaten stehen, fragt die Seite den
Vermittler **nicht** ab). Die Unterseite überlebt einen Neuaufbau durch `_fit_page`
(`_mp_demo_mode` in `main_menu.gd`).

### Nachgemessen am 2026-09-09 (Zweig `feature/mp-teams`, Teams und Startpunkte)

Toms Befund: „Mein Partner hatte auch Team 1 gewählt, war aber im Gegnerteam. Ich konnte auch nicht
sehen, welches Team er hat; und wo wer spawnt sollte mit jedem geteilt werden."

| Lauf | Ergebnis |
|---|---|
| `server/mp_smoke.py` (13 neue Prüfungen, Abschnitt „[5] Teams und Startpunkte") | 89 geprüft, 0 Fehler |
| 2 Instanzen, `TEAMS="1 1"`, 200 Netzrahmen | `Mehrspieler-Teams: Sim 0 (Team 1) Gegner: []; Sim 1 (Team 1) Gegner: []`, `mp-bündnis … { 1: false }` auf beiden Seiten, Hash `552ae255eec381ae` gleich |
| 2 Instanzen, `TEAMS="1 2"`, 200 Netzrahmen (Gegenprobe) | `Gegner: [1]` bzw. `[0]`, `mp-bündnis … { 1: true }`, Hash `95fc25071e9059f8` gleich |
| 2 Instanzen, `STARTPUNKTE="0 0"` (beide wollen denselben Punkt) | zweiter Wunsch mit `spawnoccupied` abgewiesen, Lobby zeigt „Startpunkt ist schon belegt", der Platz bleibt auf „zufällig" |
| 2 Instanzen, `TEAMS="1 1" STARTPUNKTE="1 0"` | beide Wünsche erfüllt (seat 0 → Punkt 1, seat 1 → Punkt 0), verbündet |

Prüfhaken dafür: `--mp-team N` und `--mp-spawn N` schicken vor dem Bereitmelden ein `slot`
(`main_menu.gd`), `tools/mp_local_test.sh` verteilt sie über `TEAMS="1 1"` und `STARTPUNKTE="0 3"`.
`proto_world._apply_setup` schreibt beim Spielstart die Zeile `Mehrspieler-Teams: …` mit der
Gegnerliste je Sim-Spieler ins Protokoll (wie die Zeile `Lobby: …` im Gefecht), `--mp-autoplay`
schließt mit `T: mp-bündnis — …` ab: für jeden fremden Actor auf dem Feld steht dort, ob der
Tipp-Pfad (`world.hostile`) ihn angreifen dürfte.

Werkzeuge: `tools/mp_local_test.sh` (startet die Fenster, **mit `sh`**, nicht mit `zsh` — zsh
zerlegt die Argumentliste nicht), `tools/mp_diff.py` (vergleicht zwei Mitschriften und nennt den
ersten abweichenden Rahmen). Noch offen: Handy gegen Mac (Punkt 6), absichtlicher Desync
(`--mp-corrupt`) und die Verzögerungssimulation (`--mp-lag`).

## 8. Risiken

| Risiko | Gewicht | Umgang |
|---|---|---|
| Desync durch `update_visibility`/Spion | hoch | §2 Punkt 1 zuerst, Tests 3 und 6 |
| `cos`/`sin` in `_spawn_start` | hoch | Startzellen in der Aufstellung |
| GDScript-Einfluss auf die Sim außerhalb `issue()` | mittel | `sim.order_*` in HUD verbieten (grep in CI) |
| 240 ms Eingabeverzögerung | mittel | `ORDER_LATENCY` in der Lobby 2–6 einstellbar |
| Mobilfunk trennt | mittel | in der Lobby: Platz bleibt 180 s reserviert, die App verbindet mit `resume` neu (§10). In der Partie: Fassung 1 endet, Wiedereinstieg Fassung 2 |
| App geht in den Hintergrund (WhatsApp) | hoch | §10: reservierter Platz, `resume`, `NOTIFICATION_APPLICATION_RESUMED`; Benachrichtigungen über einen Vordergrunddienst |
| Akku (12,5 Nachrichten/s) | niedrig | `NET_FRAME_TICKS` erhöhbar |
| Vermittler fällt aus | niedrig | `Restart=always`, kein Zustand auf Platte |

## 9. Nachträge aus der zweiten Entwurfsrunde (verbindlich)

* **Plätze:** `sim/include/ra/sim.h` hat `MAX_PLAYERS = 8`, die App belegt davon fest
  `PLAYER_NEUTRAL = 2` und `PLAYER_CREEPS = 3` (`proto_world.gd`). Bespielbar sind 0, 1, 4, 5, 6, 7 —
  **Fassung 1 trägt höchstens 6 Plätze** (Karte mit 8 Startpunkten: zwei bleiben leer, die Lobby sagt
  es an). Die Aufstellung trennt deshalb `seat` (Nummer im Raum 0…n−1) von `sim` (Spielerindex).
  **Stufe 2** (Paket A, getrennt commitbar): `MAX_PLAYERS` 10, Neutral/Creeps auf 8/9, `detected_`
  von `uint8_t` auf `uint16_t`, `SAVE_VERSION` hoch; die Spielerpalette wächst von selbst.
* **Sichtbarkeitsmaske nur für Menschen:** `update_visibility` ist O(Zellen) alle 5 Ticks; die
  Maske enthält nur die menschlichen Plätze (KI liest die Sichtkarte nicht). `visibility_players`
  in der Aufstellung entsprechend.
* **Protokoll-Feldnamen (endgültig):** `create{map, map_sha256, seats, settings}` (nicht
  `max_players`); `chat{text, scope:"all"|"team"}` (nicht `to`); `bot{op:"add"|"remove", seat, level,
  faction, team}`; `kick{seat}` nur Host in der Lobby; Fehlercode `nothost` für `start`/`bot`/`kick`
  von Nicht-Hosts; `lobby{code, host_seat, map, seats_total, settings, clients:[{client_id, seat,
  kind, name, faction, team, color, spawn, ready, ping}]}`; `created{code, host:true, seats}`;
  `peer_left{seat, frame, reason}`; `chat` vom Server `{seat, name, color, scope, text, t_server}`.
* **Chat:** eigene Nachrichtenart, nie in der Sim, nicht im `state_hash`. Teamfilter und
  Absender-Stempel (seat, name, color) setzt der **Vermittler**, nicht der Client. ≤ 200 Zeichen,
  5 Nachrichten/5 s je Verbindung → `ratelimit` (Verbindung bleibt), Steuerzeichen entfernt, Chattexte
  werden serverseitig nicht protokolliert. **Kurzrufe** für den Daumen: `#attack #help #yes #no #wait
  #gg`, jeder Client zeigt sie in seiner Sprache (`chat.quick.*`). Im Spiel: Sprechblasenknopf, letzte
  vier Zeilen links oben je 12 s, `[Team]`-Präfix, Verlauf im Pausenmenü. Solange die Eingabe offen
  ist, sperrt `input_blocked` im Gestenerkenner die Kartengesten. Nach `peer_left` werden Zeilen
  dieses Platzes verworfen.
* **Kein `class_name` in neuen Skripten** (Klassencache liegt nur in der APK, s. `log_view.gd`);
  Netz-/Chat-Skripte per `preload("res://scripts/net/…")`. Mehrspieler braucht ohnehin eine neue
  APK (`state_hash`, `apply_order`, `set_local_player` sind nativ) → `min_extension` hoch.
* **Raumliste:** Stufe 2 (`create.public`, Nachricht `list`) — **umgesetzt am 2026-09-07**, s. §4.1
  und §5 (Vermittler `create.public`/`list`/`visibility`, App: Umschalter beim Erstellen und in der
  Lobby, Liste unter der Codeeingabe).
* **Zusätzliche Tests:** vier Instanzen auf einer Sechs-Platz-Karte (seat→sim, Maske mit drei
  Bits, Teamchat), 500 Chatzeilen ohne Änderung des `state_hash`, Bildschirmtastatur ohne
  Kamerabewegung, `RaSim.last_step_usec()` bei sechs Plätzen messen.

## 10. Hintergrund auf Android: Wiederverbinden und Benachrichtigungen

Toms Befund 2026-09-09: „Ich habe gestern einen Raum erstellt. Dieser war für den anderen auch kurz
sichtbar. Danach habe ich mit ihm in WhatsApp geschrieben, wodurch unser Spiel in den Hintergrund
auf Android gegangen ist. Dadurch scheint sich irgendwie die Verbindung unterbrochen zu haben.
Jedenfalls konnte er es danach nicht mehr sehen." Dazu der Wunsch: Benachrichtigungen **ohne FCM**,
wenn jemand beitritt oder im Raum schreibt.

### 10.1 Warum die Verbindung abriss

Schiebt Android die App in den Hintergrund, hält Godot die Hauptschleife an — kein `_process`, also
kein `WebSocketPeer.poll()`. Der Socket ist zwar noch offen, aber niemand liest ihn und niemand
beantwortet die WebSocket-Pings des Vermittlers (`ping_interval=20`, `ping_timeout=20`, also nach
rund 40 s Schluss). Danach lief im Vermittler `Hub.gone()`: in der Lobby **entfernte** er den Platz
und warf, wenn keine Verbindung übrig war, **sofort den ganzen Raum weg** (`drop_room(room, "leer")`).
Beim Gastgeber allein im Raum heißt das: Raum weg, Code tot, der Gast sieht nichts mehr.

Es gibt keine Godot-Einstellung, die das verhindert: `application/config/quit_on_go_back` betrifft
nur die Zurücktaste, `application/run/low_processor_mode` nur den Leerlauf im Vordergrund. Ein
Android-Vordergrunddienst hält den **Prozess** am Leben, nicht Godots Schleife — er hilft nur, wenn
er eine **eigene** Verbindung hält (§10.4).

### 10.2 Reservierter Platz und `resume` (Vermittler)

Neu im Protokoll (§3), rückwärtsverträglich — eine ältere App merkt nichts davon:

| Richtung | `t` | Felder | Bedeutung |
|---|---|---|---|
| ← | `session` | `code, seat, token, resume_s, host` | **nur an diese Verbindung**: Geheimnis des eigenen Platzes; kommt nach `create`, `join` und `resume` |
| → | `resume` | `code, token` | auf denselben Platz im selben Raum zurück (nur in der Lobby) |
| → | `watch` | `code, token` | denselben Platz nur **beobachten** (§10.4) |
| ← | `watching` | `code, seat` | Antwort auf `watch` |
| ← | `lobby.clients[].absent` | `true` | dieser Platz ist reserviert, die Verbindung fehlt gerade |

Regeln:

* Bricht die Verbindung in der **Lobby** ab, wird der Platz nicht mehr entfernt, sondern
  **reserviert** (`seat_absent` im Protokoll): `client = None`, `absent_since = jetzt`, Bereitschaft
  auf den Stand direkt nach `create`. Der Raum bleibt bestehen und bleibt in der Raumliste.
* Die Frist ist `--resume-s`, Vorgabe **180 s**. Läuft sie ab, fällt der Platz weg
  (`resume_expired`); ist danach niemand mehr da, verschwindet der Raum wie bisher.
* **Die Gastgeberrolle hängt an der Platznummer**, nicht am Client-Objekt (`Room.host_seat_num`,
  `Room.is_host()`). Wer zurückkommt, ist wieder Gastgeber.
* `leave` gibt den Platz dagegen **sofort** frei — ausdrücklich verlassen ist kein Abbruch.
* `resume` in einer laufenden Partie wird abgewiesen (`badstate`): Fassung 1 kennt keinen
  Wiedereinstieg in den Gleichschritt, dafür fehlte die Rahmengeschichte.
* Falsches Geheimnis → `notallowed` und ein Strich auf dem Sperrzähler der IP.
* `start` verlangt, dass **kein** Platz reserviert ist („ein Platz verbindet gerade neu").

### 10.3 Die App

`game/scripts/net/net_client.gd`:

* merkt sich `session{code, token, resume_s, seat}` und schickt nach **jedem** `hello` einer neu
  aufgebauten Verbindung automatisch `resume{code, token}`;
* `RECONNECT_TRIES` von 5 auf **90** (× 2 s ≈ 180 s — genau die Frist des Vermittlers);
* `_notification()` auf `NOTIFICATION_APPLICATION_PAUSED/RESUMED` (und `WM_WINDOW_FOCUS_OUT/IN` am
  Schreibtisch): beim Zurückkommen sofort `wake()` — Zähler zurück, Wartezeit weg, neu verbinden,
  bzw. bei stehender Verbindung ein sofortiger `ping`, damit eine halbtote Leitung auffällt;
* schlägt das `resume` fehl (Frist abgelaufen, Raum zu, rausgeworfen), wird nicht weiter geklopft:
  Geheimnis weg, `closed` — die App geht ins Menü zurück;
* `stop()` (also „Raum verlassen") wirft das Geheimnis weg.

`net_hub.gd` hält `token`/`reconnecting` und meldet `state_changed("reconnecting"/"resumed")`;
`multiplayer_lobby.gd` zeigt „Verbinde neu …" in der Kopfzeile und einen reservierten Platz blass
mit „⟳" und „weg" statt Ping — der Spieler verschwindet **nicht** aus der Liste.

### 10.4 Benachrichtigungen ohne FCM

Es braucht keinen Push-Dienst: Android kann lokale Benachrichtigungen (`NotificationManager`,
`NotificationChannel`, ab Android 13 die Berechtigung `POST_NOTIFICATIONS`). Es braucht nur jemanden,
der sie auslöst, während Godot schläft — also einen **Vordergrunddienst mit eigener Verbindung**.

| Teil | Ort |
|---|---|
| Kotlin-Plugin (Godot-Plugin-Format v2) | `android/pocketra_plugin/` |
| Godot-Addon, hängt die AAR in den Export | `game/addons/pocketra_plugin/` |
| GDScript-Schnittstelle (tut ohne Plugin nichts) | `game/scripts/net/net_notify.gd` |
| Bau | `tools/plugin_build.sh` |

Der Dienst (`WatchService.kt`) hängt mit OkHttp am Vermittler, schickt `hello` und
`watch{code, token}` und macht aus den Antworten Benachrichtigungen:

* **jemand betritt den Raum** — neue `client_id` in der `lobby`,
* **jemand schreibt** — `chat` (die eigene Zeile nicht),
* **die Partie beginnt** — `start`.

Dazu die stille Dauermeldung „Raum XYZ — verbunden" (Kanal `mp_service`, `IMPORTANCE_LOW`); die
Ereignisse laufen über `mp_events` (`IMPORTANCE_HIGH`). Ein Tipp auf jede Meldung holt die App
zurück in den Vordergrund — sie steht dann wieder in der Lobby. Die Texte kommen **übersetzt** aus
`strings.csv` (`mp.notify_*`) und werden dem Dienst beim Start mitgegeben; im Kotlin steht kein
deutscher oder englischer Satz.

`watch` belegt keinen Platz, hält aber Raum **und** Platz am Leben: solange der Dienst hängt, läuft
die 180-s-Frist nicht ab. Damit überlebt ein Raum auch ein langes WhatsApp-Gespräch.

Vordergrunddiensttyp ist `specialUse` (Manifest `android:foregroundServiceType="specialUse"` plus
`PROPERTY_SPECIAL_USE_FGS_SUBTYPE`). `dataSync` wäre inhaltlich näher, hat seit Android 15 aber ein
Zeitlimit von 6 h je 24 h; `connectedDevice` meint Hardware. Die App wird nicht über Google Play
verteilt, die Begründungspflicht des Play-Store entfällt. Berechtigungen stehen in
`game/export_presets.cfg` (`permissions/custom_permissions`): `POST_NOTIFICATIONS`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `WAKE_LOCK`.

### 10.4a Die Schalter in den Optionen (2026-09-09)

Toms Wunsch nach dem Gerätetest: „und benachrichtigung wäre ja cool wenn ich das in den Optionen
setzen könnte." Die Schalter stehen im Hauptmenü unter **Optionen**, direkt hinter dem Sprechfunk —
beides betrifft nur den Mehrspieler. Im Pausenmenü stehen sie **nicht**: dort läuft die Partie schon,
und `_on_started` beendet den Beobachter ohnehin (`_stop_watch()`), es gäbe nichts zu stellen.

| Zeile | Wirkung |
|---|---|
| **Benachrichtigungen** (aus/an) | Hauptschalter. Aus heißt: `net_hub._start_watch()` startet den Vordergrunddienst gar nicht erst — keine Ereignisse **und** keine stille Dauermeldung „Raum XYZ — verbunden". Damit entfällt zugleich das Offenhalten von Raum und Platz im Hintergrund; genau das sagt der Hinweis unter der Zeile (`menu.options.notify_hint`) |
| **Beitritt** / **Chat** / **Spielstart** | die drei Anlässe aus §10.4, einzeln. Sie erscheinen nur, wenn der Hauptschalter an ist — im Normalfall ist die Optionsseite deshalb nur **eine** Zeile länger als vorher |
| **Freigabe** | fehlt `POST_NOTIFICATIONS` (ab Android 13), steht statt stiller Wirkungslosigkeit eine rote Zeile plus Knopf „Erlauben" da (`net_notify.request_permission()`, danach baut sich die Seite neu auf) |

Gespeichert wird in `user://settings.cfg` in einem **eigenen** Abschnitt `[notify]`
(`enabled`, `join`, `chat`, `start`, alle Vorgabe `true`) — dieselbe Machart wie `[multiplayer] voice`
beim Sprechfunk. Die Lese- und Schreibfunktionen stehen als **statischer** Block am Ende von
`game/scripts/net/net_notify.gd` und fassen den Plugin-Teil der Datei nicht an.

Zwei Wege, auf denen die Einstellung wirkt:

* **im Godot-Prozess** — `net_hub._local_notify(titel, text, anlass)` fragt `NetNotify.event_enabled()`,
  bevor es etwas zeigt;
* **im Vordergrunddienst** — `startWatch` gibt die Flaggen als `events` im selben JSON mit, das schon
  die übersetzten Texte trägt (`net_notify.events_flags()`); `WatchService.applyTexts()` liest sie und
  meldet einen abgeschalteten Anlass nicht mehr. Eine **ältere APK** kennt den Schlüssel nicht und
  meldet weiter alle drei — der Hauptschalter greift dort trotzdem, weil der Dienst dann gar nicht
  erst gestartet wird. Die Einzelschalter im Hintergrund brauchen also eine neue APK, der
  Hauptschalter und die Schalter im Vordergrund reichen als Aktualisierungspaket.

Am Schreibtisch (Mac, Windows) gibt es den Abschnitt gar nicht — `NetNotify.supported()` sagt nein,
er könnte dort nichts tun. Für Prüfhaken und Bildschirmfotos schaltet ihn `--notify-demo` (und
`--test-layout` selbst) trotzdem ein und behandelt die Freigabe als fehlend, damit die Layoutprüfung
den größten Aufbau misst. Der eigene Haken heißt `--test-benachrichtigungen` (README).

### 10.5 Der Gradle-Bau (seit 2026-09-09 scharf)

Ein Android-Plugin läuft **nur mit dem Gradle-Bau**: Godot muss die APK aus der Android-Bauvorlage
selbst zusammensetzen, statt eine vorgefertigte Vorlage zu befüllen. Tom hat das am 2026-09-09
freigegeben („Ja baue Gradle um"), die Umstellung ist umgesetzt und die APK gebaut (§10.6).

**Was sich dauerhaft geändert hat**

| Ort | vorher | jetzt |
|---|---|---|
| `game/export_presets.cfg`, Preset „Android" und „Android Verteilung" | `gradle_build/use_gradle_build=false` | `=true` |
| `game/export_presets.cfg`, Preset „Update-Paket" und „… schlank" | `false` | bleibt `false` (die exportieren ein `.pck`, kein APK) |
| `game/project.godot` | kein `[editor_plugins]` | `enabled=PackedStringArray("res://addons/pocketra_plugin/plugin.cfg")` |
| `game/android/` (Bauvorlage) | gab es nicht | wird erzeugt, steht in `.gitignore` |
| `tools/apk_build.sh` | Export mit Vorlage | baut vorher die Plugin-AAR, installiert bei Bedarf die Bauvorlage, kennt `--ref`, `--wt`, `--no-gradle` |
| APK `minSdkVersion` | 24 | **29** (Godot setzt das beim Gradle-Bau selbst, weil der Mobile-Renderer Vulkan braucht — Android 10 aufwärts) |
| APK-Größe (gleicher Commit) | 206,7 MB | **264,8 MB** — siehe unten |

**Warum die APK größer ist.** Der Inhalt ist derselbe (unkomprimiert 356,4 gegen 356,8 MB). Der
Gradle-Bau legt die nativen Bibliotheken **unkomprimiert** in die APK
(`gradle_build/compress_native_libraries=false`, Godots Vorgabe, entspricht
`android:extractNativeLibs=false`) und legt im Debug-Export auch `classes.dex` ungepackt ab:
`libgodot_android.so` allein sind 76 MB statt 25 MB, `classes.dex` 7 MB statt 2 MB.
Auf dem Gerät ist das der bessere Weg — Android muss die Bibliotheken nicht auspacken, der Start ist
schneller und **belegt weniger** Speicher (sonst liegen APK *und* ausgepackte Bibliotheken dort).
Wer den kleineren Download will, setzt in beiden Presets
`gradle_build/compress_native_libraries=true`; die APK ist dann wieder ~207 MB, das Gerät braucht
aber ~78 MB mehr.

**Voraussetzungen des Baus**

* JDK **17** — Godot nimmt seine Editor-Einstellung `export/android/java_sdk_path`
  (`/opt/homebrew/opt/openjdk@17/…`). Ein neueres JDK weist Gradle 8 ab.
* Android SDK unter `~/Library/Android/sdk` (Editor-Einstellung `export/android/android_sdk_path`),
  Platform 35/36 und Build-Tools.
* Netz beim ersten Lauf: Gradle lädt AGP, Kotlin, `org.godotengine:godot` und OkHttp.
* Dauer: erster Lauf mehrere Minuten (Bauvorlage + Gradle-Abhängigkeiten), danach ~2–4 min für die
  ganze Kette (Extension, Import, Export).

**Bauen**

```bash
tools/apk_build.sh                                  # wie bisher: aus master, jetzt über Gradle
tools/apk_build.sh --ref feature/xyz --wt apk-xyz   # aus einem Zweig, eigener Arbeitsbaum
tools/apk_build.sh --dist                           # Verteil-APK ohne EA-Inhalte
tools/apk_build.sh --no-gradle                      # Notausgang: alter Weg, **ohne** Plugin
```

Das Skript erledigt selbst, was der Gradle-Bau braucht:

1. `tools/plugin_build.sh` baut die AAR — sie liegt **nicht** im Git, und `apk_build.sh`
   arbeitet in einem eigenen Arbeitsbaum, wo sie sonst fehlen würde.
2. Fehlt `game/android/build/`, installiert es die Bauvorlage
   (`Godot --install-android-build-template …`, den Schalter gibt es ab Godot 4.7.1).
3. Nach dem Export gibt es Berechtigungen, `minSdkVersion` und eine Kurzprobe aus, ob der
   Vordergrunddienst im gemergten Manifest steht.

**Wenn der Gradle-Bau klemmt**

| Bild | Ursache | Abhilfe |
|---|---|---|
| `Unsupported class file major version` / Gradle bricht sofort ab | falsches JDK | `export/android/java_sdk_path` auf JDK 17 stellen |
| `SDK location not found` | `local.properties`/`ANDROID_HOME` fehlt | `export/android/android_sdk_path` prüfen |
| `Could not resolve org.godotengine:godot` | kein Netz oder falsche Fassung | Netz prüfen; die Fassung in `android/pocketra_plugin/build.gradle` muss zur Godot-Fassung passen |
| Bauvorlage veraltet nach einem Godot-Update | `game/android/build/` stammt von der alten Fassung | `rm -rf game/android` (und im Arbeitsbaum des Baus), neu bauen lassen |
| irgendetwas sonst | — | `tools/apk_build.sh --no-gradle` baut wie früher weiter; nur die Benachrichtigungen fehlen dann |

Fehlt die AAR oder ist das Addon aus, ist das ohne Folgen: `net_notify.gd` findet den Singleton
`PocketRaPlugin` nicht und tut nichts, `export_plugin.gd` warnt und hängt nichts ein. **Teil A
(Wiederverbinden) hängt nicht am Plugin** und wirkt allein durch das Aktualisierungspaket.

Ebenfalls offen: der Wiedereinstieg in eine **laufende** Partie (dafür müsste der Vermittler die
Rahmen vorhalten, §5 „Später"), und die 6-h-Grenze eines langen Vordergrunddienstes.

### 10.6 Geprüft

| Lauf | Ergebnis |
|---|---|
| `server/mp_smoke.py` mit Abschnitt 8 (session, resume, watch, Frist) | im Verbund mit Abschnitt 5 (Teams/Startpunkte) und dem Sprechfunk: 132 geprüft, 0 Fehler |
| `sh tools/mp_bg_test.sh` — zwei Godot-Fenster, Gastgeber 60 s per `SIGSTOP` eingefroren | Raum blieb stehen (`seat_absent`, kein `room_closed`), der Gast sah `absent: true`, nach `SIGCONT` holte `resume` denselben Platz samt Gastgeberrolle zurück |
| `sh tools/plugin_build.sh` (Gradle 8.14 und 9.3.1, JDK 17, compileSdk 35) | `BUILD SUCCESSFUL`, beide AAR gebaut; im Manifest stehen `meta-data org.godotengine.plugin.v2.PocketRaPlugin`, der Dienst mit `foregroundServiceType="specialUse"` und die vier Berechtigungen |
| `Godot --headless --path game --import` | keine Skriptfehler |
| `--test-benachrichtigungen` (Optionen-Schalter, 2026-09-09) | 30 Proben, **0 Befunde**: Speichern/Wiederlesen `[notify]`, Hauptschalter über den Anlässen, `events_flags()`, stille Auslösestelle bei abgeschaltetem Anlass (Chat über `_on_chat`), Dienst startet nicht bzw. endet sofort beim Umlegen, Abschnitt fehlt am Schreibtisch, Tippflächen 30,0 dp gegen 25,5 dp Bestand |
| `--test-layout` an `main_menu.tscn`, de und en, **im Fenster** | 70 Verstöße — dieselben 70 wie ohne die Änderung (alle auf `mp_lobby`, Altbestand); die Optionsseite mit dem neuen Abschnitt: 0 |
| `--test-layout` und `--test-hit` im Spiel | 0 Verstöße / 0 Fehlschläge |
| `sh tools/plugin_build.sh debug` nach der `events`-Ergänzung in `WatchService.kt` | `BUILD SUCCESSFUL` |
| `tools/apk_build.sh --ref feature/mp-hintergrund --wt apk-gradle` (Gradle-Bau) | APK 264,8 MB, `minSdkVersion 29`, `targetSdkVersion 36`, signiert (Debug-Schlüssel); `aapt2 dump permissions`: INTERNET, ACCESS_NETWORK_STATE, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE, WAKE_LOCK. **Vor** dem Zusammenführen mit `feature/mp-sprechfunk` gebaut, deshalb ohne `RECORD_AUDIO`; die Verteil-APK der Veröffentlichungsrunde trägt sie |
| dieselbe APK, Manifestbaum (`aapt2 dump xmltree`) | `meta-data org.godotengine.plugin.v2.PocketRaPlugin → net.pocketra.app.plugin.PocketRaPlugin`; `service net.pocketra.app.plugin.WatchService` mit `exported=false`, `foregroundServiceType=0x40000000` (specialUse) und `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` |
| dieselbe APK, Inhalt (`unzip -l`) | `okhttp3/…`, `kotlin/…`, `classes.dex` 7,2 MB, `lib/arm64-v8a/librasim.android.arm64.so`, `libgodot_android.so` |
| Gegenprobe `--no-gradle` aus demselben Commit | APK 206,7 MB, `minSdkVersion 24`, „Benachrichtigungs-Plugin: NICHT in der APK" — der Unterschied ist reine Packung (unkomprimiert 356,4 gegen 356,8 MB) |

## 11. Sprechfunk (2026-09-09, Zweig `feature/mp-sprechfunk`)

Toms Wunsch nach seinem Mehrspieler-Test: „Einmal ein Teamspeak. Einfach einen Mikrofonknopf rechts
neben den Chatknopf, um das Mikrofon ein- oder auszuschalten, um mit seinem Team zu reden. Lang
gedrückt halten öffnet einen offenen Kanal an alle und ändert auch die Mikrofonfarbe."

### 11.1 Bedienung

* **Chat- und Mikrofonknopf stehen oben in der Kopfzeile, rechts neben dem Menüknopf** (Toms
  Wunsch 2026-09-09: „Somit sind unten unsere Buttons wieder aligned wie im Singleplayer") — in
  Leserichtung **Menü → Chat → Mikrofon**, in der Größe der übrigen Kopfzeilenknöpfe
  (`TOP_ICON_BTN_DP` = 56 dp). Die **untere** Knopfleiste ist damit im Mehrspieler Knopf für Knopf
  dieselbe wie im Einzelspieler: `_cmd_order` bleibt `CMD_ORDER`, `_layout_command_bar()` sieht die
  beiden gar nicht. Gesetzt werden sie in `_layout_top_comm()`. Ist die Kopfzeile zu schmal (die
  Statusleiste sitzt mittig; betrifft nur hochformatige Fenster), stehen sie **senkrecht unter dem
  Menüknopf** und schieben die Kontrollgruppen nach unten — beides bleibt im linken/oberen
  HUD-Streifen (`HUD_LEFT_DP` 132 dp) und damit aus der Kartenfläche.
* **Mikrofonknopf** derselbe Symbolknopf-Stil (`HudTheme.style_icon_button`), das Mikrofon wird zur
  Laufzeit gezeichnet (`HudTheme.mic_icon()`), also kein neues Bild in der APK.
* **Tipp**: Mikrofon an das **eigene Team** (`scope: "team"`) — Symbol **grün**
  (`HudTheme.VOICE_TEAM` `#4DE073`), daneben steht „Team". Nochmal tippen = aus.
* **Langdruck** (≥ `HudTheme.HELP_PRESS_MS` = 600 ms): **offener Kanal an alle**, auch an die
  Gegner (`scope: "all"`) — Symbol **Signalorange** (`HudTheme.VOICE_ALL` `#FF731A`), daneben steht
  „An alle". Nochmal lang drücken = aus. Ein ausgeschaltetes Mikrofon ist gedämpftes Grau
  (`VOICE_OFF`) und so durchscheinend wie die übrigen Symbolknöpfe; ein eingeschaltetes steht voll
  deckend da. Jeder Wechsel sagt im Klartext an, wer mithört.
* **Abweichung, bewusst:** dieser eine Knopf hat **keine** Langdruck-Hilfetafel — der Langdruck ist
  hier die Funktion, die Tom bestellt hat. Die Erklärung steht im Tooltip (`cmd.mic.tip`), als
  Meldung beim Umschalten und unter `help.btn.mic`. Dafür gibt es
  `HudTheme.wire_tap_hold()` neben `wire_help()`.
* **Wer redet gerade:** oben links unter den Chatzeilen „spricht: <Name>" in der Spielerfarbe des
  Platzes, offener Kanal mit dem Zusatz „(an alle)". Erscheint mit dem ersten Paket und verschwindet
  0,6 s nach dem letzten.
* **Stummschalten:** im Pausenmenü unter **„Spieler"** (bis 2026-09-09 „Chatverlauf", s. §12)
  steht in der Zeile jedes fremden menschlichen Platzes ein Knopf — ein Tipp schaltet ihn stumm
  (Vermerk „stumm" statt „hörbar", Name grau), ein zweiter wieder frei. Absichtlich dort und
  nicht als neuer Menüpunkt: Toms Pausenmenü soll nicht länger werden.
* **Erstinfo beim ersten Mehrspielerstart** (Toms Wunsch 2026-09-09): beim zweiten Netzrahmen
  erscheint einmalig eine kleine Tafel, die Tippen (grün, eigenes Team) und Langdruck (orange,
  offener Kanal an alle) mit **beiden Mikrofonfarben** erklärt. Es ist dieselbe Machart wie die
  Langdruck-Hilfe (`HudTheme.show_help_popup`, neu mit optionalem BBCode-Text) — ein Tipp
  irgendwohin schließt sie. Sie hält **nichts** an: der Gleichschritt tickt weiter, sie schickt
  keinen Befehl und ändert keinen `state_hash`; im Zwei-Instanzen-Lauf blieben die Hashes gleich.
  Der Merker steht bei den übrigen dauerhaften Schaltern in `user://settings.cfg`
  (`[multiplayer] voice_intro`), also je Gerät, nicht je Partie. Wieder aufschlagen lässt sie sich
  jederzeit über „Sprechfunk erklären" im Pausenmenü unter „Spieler".
* **Optionen:** Regler „Sprechfunk" (eigener Audio-Bus, s. u.) und ein Ein/Aus-Schalter. Beide
  stehen im Hauptmenü unter Optionen; im Pausenmenü erscheinen sie nur im Mehrspieler. Aus heißt
  aus: das Mikrofon lässt sich dann nicht einschalten und ankommende Pakete werden verworfen.

### 11.2 Aufnahme, Sprachschleuse und Notbremse (2026-09-09, nach Toms Handtest)

Toms Befund: zwei Instanzen auf dem **Mac**, echte Partie über den Live-Vermittler (Raum QWQPY3),
in beide Richtungen gesprochen — **nichts kam an**, und der Vermittler protokollierte keine einzige
`voice`-Zeile. Es wurde also nie ein Paket abgeschickt.

**Was nachgemessen wurde** (Haken `--test-mikrofon`, s. u.):

| Stufe | Messwert am Mac |
|---|---|
| `AudioEffectCapture.get_frames_available()` → `get_buffer()` | ~48 000 Frames/s, 94–96 % der Abtastwerte ≠ 0 — die Aufnahme **läuft** |
| roher Effektivwert im Ruhezustand | 0,0004 … 0,0011 (Spitze 0,0021) — Raumstille bei geringer Eingangsverstärkung |
| Herunterrechnen auf 8 kHz | roh 0,1805 → Block 0,1763 bei eingespieltem Sinus: **kein Pegelverlust** (2 %) |
| Schleuse, ADPCM, `_send_packet()` | mit echtem Ton auf dem Aufnahmebus: 12 Blöcke → **12 Pakete** |
| `client.send_voice()` → Vermittler | im Zwei-Instanzen-Lauf belegt (`voice room=… seat=… scope=team`) |

**Die Kette ist also vollständig** — was fehlte, war Signal. Auf dem Prüfrechner wurde in einem
Lauf **durchgehend exakt 0** über Hunderttausende Frames gemessen; ein echtes Mikrofon rauscht
immer, das ist digitale Stille. macOS liefert genau das, wenn die Mikrofonfreigabe fehlt
(Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon), **ohne** einen Fehler zu melden;
Godot bietet dort keine Abfrage an (`OS.request_permission()` ist Android). Toms Lauf sagt damit
**nichts** über Android aus — die Aufnahme auf dem Gerät ist weiterhin ungeprüft.

**Der bestätigte Fehler ist das stille Scheitern.** Dagegen drei Änderungen:

1. **Selbsteinstellende Sprachschleuse** (vorsorglich, *nicht* die Ursache): statt der festen
   Schwelle `GATE_ON = 0.035` wird das Grundrauschen geschätzt und die Schwelle daraus gebildet —
   `Öffnen = clamp(Rauschen × 2,5; 0,0030; 0,0150)`, `Schließen = Öffnen × 0,6`, danach 0,45 s
   Nachlauf. Das Rauschen folgt nach unten schnell (0,35 je Block) und nach oben langsam (0,03) und
   nur bei geschlossener Schleuse, damit die eigene Stimme die Schwelle nicht hinter sich herzieht.
   Gemessen: bei ruhigem Raum (0,001) öffnet sie ab 0,0030, bei lautem Raum (0,005) erst ab 0,0125 —
   die alte feste Zahl lag beim **18-fachen** des hier gemessenen Ruhepegels.
2. **Mikrofonprobe in den Optionen** (`HudTheme.mic_probe_row`): ein Knopf „Starten", ein
   Live-Pegelbalken mit der Schleusenschwelle als goldene Marke und eine Klartextzeile
   („Sendet · Pegel 0.0300 · Schwelle 0.0047" bzw. „Zu leise zum Senden"). Sie nimmt auf und
   **sendet nichts**. Steht in den Optionen des Hauptmenüs und — im Mehrspieler — im Pausenmenü.
3. **Notbremse**: ist das Mikrofon an und geht nach vier Sekunden **kein einziges** Paket raus,
   meldet `mic_trouble` einen von drei Gründen, jeweils als Meldung im Spiel und als Zeile im
   Protokoll:

   | Grund | Bedingung | Meldung |
   |---|---|---|
   | `no_input` | gar keine Frames | „Sprechfunk: keine Aufnahme — der Eingang liefert nichts." |
   | `no_signal` | Frames, aber **jeder** Abtastwert exakt 0 | „Sprechfunk: kein Mikrofonsignal — Freigabe fürs Mikrofon prüfen." |
   | `too_quiet` | Ton kommt an, Schleuse öffnet nie | „Mikrofon zu leise — Sprechfunk sendet nicht." |

**Freigabe auf macOS:** `VoiceChat.has_permission()` kann sie außerhalb von Android nicht abfragen
und gibt `true` zurück; erkannt wird der Fall über `no_signal`. Handgriff: Systemeinstellungen →
Datenschutz & Sicherheit → Mikrofon → die Anwendung (im Entwicklerlauf **Godot**) freigeben. Die
Meldung im Spiel nennt den Weg.

### 11.3 Der stumme Eingang auf Android (Xperia 5 V) — Stand 2026-09-09

Toms Gerätetest, dann per `adb` nachgemessen. **Der Fehler ist eingegrenzt, aber noch nicht behoben.**

**Was gemessen wurde** (Sony Xperia 5 V, XQ-DQ54, Android 15, App 0.14 + Paket 21):

| Messung | Ergebnis |
|---|---|
| Diagnosezeile der Mikrofonprobe | `Freigabe ja · Default · 40000 F/s (hochzählend) · ≠0 0% · roh 0.0000 · Neu 3` |
| `cmd appops get … RECORD_AUDIO` | `allow; duration=+9s234ms` — **Android hat 9,2 s wirklich aufgenommen**, Mikrofonsymbol war an |
| `dumpsys package …` | `RECORD_AUDIO: granted=true` (systemseitig) |
| `logcat` | **keine** Meldung von `AudioRecord`, `AudioFlinger`, `AudioPolicy` |
| `dumpsys media.audio_flinger` | alle Ein- und Ausgabepfade des Geräts laufen mit **48 000 Hz** |
| Wiedergabe | die Durchsage eines Freundes kam an → Bus „Funk", Dekodierung, Ruckelpuffer in Ordnung |
| Sendekette | auf dem Gerät des Freundes belegt → ADPCM, Vermittler, beide Kanäle in Ordnung |

**Damit ist entlastet:** Berechtigung, Androids `AudioRecord`, unsere Sendekette, die Sprachschleuse
und die Wiedergabe. Der Ton geht **innerhalb der Engine** verloren — zwischen Androids laufender
Aufnahme und dem, was `AudioStreamMicrophone` auf unseren Bus mischt.

**Was das Wiederöffnen betrifft:** Der Wächter aus der Runde davor hat sauber gearbeitet (`Neu 3`)
und **es hat nicht geholfen**. Der Weg ist damit widerlegt. Er bleibt drin, weil er gegen die zu
spät erteilte Freigabe und gegen [godotengine/godot#108915](https://github.com/godotengine/godot/issues/108915)
(Aufnahme stirbt nach 5–7 s Stille) der richtige Griff ist — aber er ist **nicht** die Lösung für
Toms Gerät.

#### Befund am Quelltext: die Abtastrate ist fest verdrahtet

`platform/android/audio_driver_opensl.cpp`, Zweig `4.7` **und** `master`:

```cpp
SLDataFormat_PCM format_pcm = {
    SL_DATAFORMAT_PCM, 1,
    SL_SAMPLINGRATE_44_1,               // <— fest, nicht aus einer Einstellung
    SL_PCMSAMPLEFORMAT_FIXED_16, SL_PCMSAMPLEFORMAT_FIXED_16,
    SL_SPEAKER_FRONT_CENTER, SL_BYTEORDER_LITTLEENDIAN
};
…
int AudioDriverOpenSL::get_mix_rate() const { return 44100; }   // "hardcoded for Android"
```

Und in `servers/audio/audio_stream.cpp` liefert `AudioStreamPlaybackMicrophone::_mix_internal()`
**Stille**, solange der Eingangspuffer nicht gefüllt ist:

```cpp
unsigned int playback_delay = MIN(((50 * mix_rate) / 1000) * 2, buf.size() >> 1);
if (playback_delay > input_size) {
    for (int i = 0; i < p_frames; i++) p_buffer[i] = AudioFrame(0.0f, 0.0f);
    input_ofs = 0;
} else { … }
```

Füllt die OpenSL-Rückrufkette den Puffer nie, bleibt `input_size` bei 0 und der Strom mischt für
immer Nullen — **ohne** Fehlermeldung, und Android zählt die Aufnahme trotzdem als laufend. Genau
das Bild vom Xperia.

Das Gerät fährt nachweislich 48 000 Hz, Godot fordert den **Recorder** fest mit 44 100 Hz an. Für
die *Wiedergabe* rechnet Android das um (Musik und EVA laufen auf Toms Gerät einwandfrei); für die
*Aufnahme* verlangt Androids OpenSL-Empfehlung ausdrücklich die native Geräterate. Das erklärt auch,
warum es beim Freund geht: anderes Gerät, andere native Rate.

**Wichtig — und anders, als man hoffen würde:** `audio/driver/mix_rate` in `project.godot` hilft
**nicht**. Der Android-Treiber liest die Einstellung überhaupt nicht (weder in `init()` noch in
`init_input_device()`, weder in 4.7 noch in master); die 44 100 stehen als Konstante im Code. Eine
Überschreibung `audio/driver/mix_rate.android` gibt es dort ebenso wenig. Es gibt also **keinen
Projektschalter**, mit dem sich das beheben ließe — die Einstellung zu setzen wäre wirkungslose
Kosmetik und ist deshalb unterblieben.

#### Die Lösung: eigene Aufnahmequelle im Android-Plugin (2026-09-09, App 0.15)

Tom hat zugestimmt, den Weg an der Engine vorbei zu gehen. Aufgenommen wird auf Android jetzt mit
**`AudioRecord`** im vorhandenen Kotlin-Plugin (`android/pocketra_plugin/`,
`src/main/java/net/pocketra/app/plugin/VoiceInput.kt`).

**Warum in das bestehende Plugin und nicht in ein zweites:** Gradle-Bau, `EditorExportPlugin`,
Manifest-Merger, AAR-Einhängung und beide Werkzeugskripte stehen dort schon. Ein zweites Plugin
hieße eine zweite AAR, ein zweites `plugin.cfg`, ein zweiter `[editor_plugins]`-Eintrag und ein
zweiter Bau — ohne dass eine Zeile davon besser liefe. Der Klassenkopf sagt, dass das Plugin zwei
Aufgaben hat; der Name ist deshalb bewusst neutral. Bei der Umbenennung auf PocketRA (2026-09-09)
wurde er von `RedAlertNotify` auf **`PocketRaPlugin`** gezogen — dabei mussten alle sechs Stellen
gleichzeitig mitwandern (Kotlin-Paket + Klasse, Manifest-Schlüssel
`org.godotengine.plugin.v2.PocketRaPlugin` samt Klassenwert, `plugin.cfg`/`export_plugin.gd` im
`addons/`-Ordner, `project.godot` `[editor_plugins]`, `net_notify.gd`, `voice_chat.gd` und
`update_config.gd`); weicht eine ab, findet Godot den Singleton nicht mehr.

| Punkt | Umsetzung |
|---|---|
| Quelle | `MediaRecorder.AudioSource.VOICE_COMMUNICATION` — das System schaltet Echounterdrückung und Rauschfilter dazu; `AcousticEchoCanceler`/`NoiseSuppressor` werden zusätzlich ausdrücklich eingeschaltet, wenn das Gerät sie hat |
| Rate | erst die, die das Gerät selbst nennt (`AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`), sonst 48 000 / 44 100 / 32 000 / 16 000 / 8 000. Genommen wird die **zurückgelesene** `AudioRecord.sampleRate`, nicht die angeforderte |
| Format | mono, 16 Bit PCM; Puffer `max(getMinBufferSize × 4, 200 ms)` |
| Faden | ein eigener Lesefaden füllt einen Ringpuffer (1 s); `micRead()` schöpft im Godot-Faden nur daraus ab und blockiert nie |
| JNI | `float[]` → `PackedFloat32Array` **am Stück** (`platform/android/jni_utils.cpp`), nicht Wert für Wert; höchstens 0,5 s je Abholung |
| Berechtigung | `RECORD_AUDIO` steht im App- **und** im Plugin-Manifest. Eine **zusätzliche** Laufzeitabfrage braucht es nicht — der vorhandene Weg (`VoiceChat.ensure_permission()` → `OS.request_permission`) genügt; das Plugin bietet `micRequestPermission()` nur als Zweitweg an. Neu ist, dass `has_permission()` auf Android das Plugin fragt (`checkSelfPermission`) statt Godots Zwischenspeicher |

**Beide Wege bleiben, die App wählt selbst** (`VoiceChat.Source`):

* Android **mit** Plugin → `micStart()`; liefert es eine Rate > 0, läuft die Aufnahme darüber.
* Sonst — Mac, Windows, jede APK ohne Gradle-Bau, und Android, falls `micStart()` scheitert —
  unverändert `AudioStreamMicrophone` + `AudioEffectCapture`. Der Mac bleibt damit der Prüfstand.

Beide münden in **`VoiceChat._feed_mono(samples, src_rate)`**. Von dort an ist die Kette für beide
Quellen dieselbe: Kastenfilter auf 8 kHz, Sprachschleuse, IMA-ADPCM, Versand. **An der Sendekette
wurde nichts geändert** — sie ist auf echter Hardware belegt (das Gerät von Toms Freund).

Die Diagnosezeile der Mikrofonprobe sagt, welcher Weg gerade läuft:

```
Freigabe ja · Quelle: Plugin 48000 Hz · Default · 47990 F/s · ≠0 96% · roh 0.0110 · Neu 0
Plugin: geladen · Benachr.: ja · micStart=48000 · AudioRecord 48000 Hz · Puffer 19200 B · … · AEC · NS
Geräte (1): Default
```
gegen `Quelle: Engine 44100 Hz` auf dem alten Weg.

#### Was bleibt

1. **Umgesetzt** (s. o.): eigene Aufnahme über das Android-Plugin. Braucht eine **neue APK**
   (0.15 / Code 15) — ein Aktualisierungspaket allein reicht nicht, weil nativer Code dazukommt.
2. Bleibt der Ton auch damit aus, wäre ein gepatchtes Android-Exportvorlagen-Binary (Godot mit
   variabler Recorder-Rate) der nächste Schritt — ungleich mehr Bau- und Pflegeaufwand.
3. Abwarten, bis Godot es behebt — im `master` ist es unverändert.

Schlägt auch das fehl, sagt die App es weiterhin im Klartext: „Freigabe steht, der Eingang bleibt
stumm. Erst die App einmal vollständig schließen und neu starten. Hilft das nicht, kann dieses Gerät
den Sprechfunk nur **empfangen** — Mithören geht weiter, Sprechen nicht."

#### Wenn das Plugin gar nicht anspringt (Gerätetest mit 0.15)

Toms erster Lauf mit App 0.15 zeigte weiter `Quelle: Engine 44100 Hz`, Gerät `Default`, **ohne**
Fehlerzeile. Am gebauten Paket war alles in Ordnung (Manifest-`meta-data`, `PocketRaPlugin` und
`VoiceInput` in `classes.dex`, `getPluginName()`, `@UsedByGodot`, gleicher Name in
`voice_chat.gd`). Zwei völlig verschiedene Ursachen sahen gleich aus — das trennt die Diagnose
jetzt:

| Zeile | Bedeutung | nächster Griff |
|---|---|---|
| `Plugin: nicht geladen` | `Engine.has_singleton("PocketRaPlugin")` ist falsch — Godot hat die Klasse aus dem Manifest **nicht** instanziiert | logcat, s. u. |
| `Plugin: geladen (JNI) · kann: … · fehlt: micStart …` | Singleton da, die genannten Methoden meldet er aber nicht an — dann (und **nur** dann) ist eine ältere AAR ein Verdacht | AAR neu bauen (`tools/plugin_build.sh`) und APK neu exportieren |
| `Plugin: geladen (JNI) · kann: micStart, … · micStart=0 · …` | Plugin läuft, `AudioRecord` verweigert — `micInfo()` nennt den Fehler | Gerät/Freigabe |
| `Plugin: geladen (JNI) · kann: … · micStart=48000 · AudioRecord 48000 Hz …` | alles gut | — |

Die Zeile zählt auf, **welche** Methoden des Plugins benutzbar sind (`kann:` / `fehlt:`) — darunter
`showNotification` und `restartApp`, also auch der Benachrichtigungs- und der Neustartteil desselben
Plugins. Fehlen die auch, ist es nicht die Aufnahme, sondern das ganze Plugin. `(JNI)` sagt, wie das
ermittelt wurde: über `JNISingleton.has_java_method()`, s. u. Eine **Ursache** behauptet die Zeile
nicht mehr — die frühere Fassung sagte „ohne micStart (alte AAR)" und schickte die Suche einen
ganzen Tag in die falsche Richtung.

**Im logcat nachsehen** — Godots Lader ist `GodotPluginRegistry`
(`platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPluginRegistry.java`,
Fassung 4.7). Er schreibt genau diese Zeilen:

```
adb logcat -s GodotPluginRegistry:V        # oder: adb logcat | grep -E "Godot plugin|GodotPluginRegistry"
```

| Meldung | heißt |
|---|---|
| `Initializing Godot plugin PocketRaPlugin` (I) | Manifest-Eintrag gefunden, Reflexion beginnt |
| `Completed initialization for Godot plugin PocketRaPlugin` (I) | geladen — dann liegt es **nicht** am Laden |
| `Unable to load Godot plugin PocketRaPlugin` (W, **mit Stapelspur**) | Reflexion gescheitert; die Ausnahme im Anhang nennt den Grund (`ClassNotFoundException`, `NoSuchMethodException`, …) |
| `Invalid plugin loader class for PocketRaPlugin` (W) | `meta-data`-Wert leer |
| `Meta-data plugin name does not match … X =/= Y` (W) | Name im Manifest ≠ `getPluginName()` |
| `Unable load Godot Android plugins from the manifest file.` (E) | Manifest gar nicht lesbar |
| `Registering runtime plugin …` (I) | zur Laufzeit angemeldetes Plugin (nicht unseres) |

Fehlt **jede** dieser Zeilen, hat Godot den `meta-data`-Eintrag nicht gesehen. Kommt
`Initializing …` ohne `Completed …`, steht der wahre Grund in der Stapelspur direkt darunter.
Achtung: Godot fängt dort nur `Exception` — ein `NoClassDefFoundError` (fehlende Bibliothek) wäre
ein `Error` und käme als Absturz, nicht als Warnung; das schließt „Kotlin-Laufzeit fehlt" praktisch
aus, zumal Godots eigene `godot-lib` selbst in Kotlin geschrieben ist und die Laufzeit mitbringt.

Übrige Verdächtige, geprüft und für unwahrscheinlich befunden: Konstruktor-Signatur
(`PocketRaPlugin(Godot)` steht so in der AAR, `javap` bestätigt), `godot-lib` als `compileOnly`
(richtig — die App bringt sie mit, Fassung identisch 4.7.2), R8/ProGuard (`minifyEnabled false`,
und `consumer-rules.pro` hält `net.pocketra.app.plugin.**` ohnehin), mehrere dex-Dateien
(Android lädt alle). Godot meldet fehlgeschlagene Plugin-Ladevorgänge außerdem nicht immer —
[godotengine/godot#63731](https://github.com/godotengine/godot/issues/63731).

#### Der zweite, davon unabhängige Fehler: `has_method()` lügt auf dem Plugin-Singleton (0.16)

Gerätetest mit **0.16**, 2026-09-09. Diesmal war es **nicht** die Godot-Rate von oben, sondern
unsere eigene Absicherung. Symptom: **keine einzige** Methode des Plugins war aus GDScript
erreichbar — kein Mikrofon, keine Benachrichtigungen, kein Neustart-Knopf.

**Beleg am Gerät** (Sony Xperia 5 V, PocketRA 0.16, per `adb`):

| Messung | Ergebnis |
|---|---|
| `logcat` | `Initializing Godot plugin PocketRaPlugin` **und** `Completed initialization for Godot plugin PocketRaPlugin` — das Plugin lädt sauber |
| installierte APK zerlegt, `apkanalyzer dex code` | `net.pocketra.app.plugin.PocketRaPlugin` enthält `micStart`, `micRead`, `micInfo`, `micRate`, `micAvailable`, `micHasPermission`, `hasPermission` …, und **jede** trägt `.annotation runtime Lorg/godotengine/godot/plugin/UsedByGodot;` — R8 hat nichts gestrippt |
| Diagnosezeile der App | `Plugin: geladen, ohne micStart (alte AAR)` und `Benachr.: NEIN` |

Die AAR war also in Ordnung, das Laden war in Ordnung, die Annotationen waren da — und die App sagte
trotzdem Nein. Der Fehler saß in der Prüfung: **wir haben jeden Zugriff mit `Object.has_method()`
abgesichert.**

**Quelltextbeleg** (Godot 4.7, `platform/android/api/jni_singleton.h` / `.cpp`):

```cpp
class JNISingleton : public Object {
    GDCLASS(JNISingleton, Object);
    RBMap<StringName, MethodData> method_map;    // hier stehen die @UsedByGodot-Methoden
    virtual Variant callp(...) override;         // NUR das ist überschrieben (dazu `_get`)
    bool has_java_method(const StringName &p_method) const { return method_map.has(p_method); }
};

void JNISingleton::_bind_methods() {
    ClassDB::bind_method(D_METHOD("has_java_method", "method"), &JNISingleton::has_java_method);
}
```

`Object::has_method()` ist in `core/object/object.h` **nicht virtuell**; die Umsetzung in
`core/object/object.cpp` schaut ausschließlich in die Skriptinstanz und in ClassDB. Die
`method_map` des Singletons sieht sie nie. `get_method_list()` (`ClassDB::get_method_list` +
Skript) listet sie aus demselben Grund nicht. `callp()` dagegen **ist** virtuell und findet den
Namen — `JNISingleton::callp()` reicht ihn an das umschlossene Java-Objekt weiter.

| auf einem Plugin-Singleton | trägt? |
|---|---|
| `has_method("micStart")` | **nein** — immer `false`, auch wenn der Aufruf funktioniert |
| `get_method_list()` | **nein** — die `@UsedByGodot`-Methoden stehen nicht darin |
| `call()` / `callv()` / `p.micStart()` | **ja** — über `JNISingleton::callp()` |
| `has_java_method("micStart")` | **ja** — die einzige in ClassDB gebundene Methode, und damit auch die einzige, die ihrerseits über `has_method()` auffindbar ist |

**Lehre — bitte merken:** `has_method()` ist auf Android-Plugin-Singletons **kein gültiger Test**.
Wer eine Plugin-Methode absichern will, fragt `has_java_method()`.

**Behoben in** `game/scripts/android_plugin.gd` (neu): ein Ort für Singleton-Zugriff und Prüfung,
Ergebnis je Methodenname genau einmal ermittelt und gemerkt (kein blinder Aufruf je Frame — ein
Aufruf ins Leere stürzt in Godot 4 zwar nicht ab, schreibt aber eine Fehlerzeile ins Protokoll):

```gdscript
static func _probe(p: Object, method: StringName) -> bool:
	if p == null:
		return false
	if p.has_method(method):                     # gewöhnliches Objekt (Attrappe, andere Plattform)
		return true
	if p.has_method(&"has_java_method"):
		return bool(p.has_java_method(method))   # JNISingleton (Android)
	return false
```

Umgestellt sind alle sechs Fundstellen: `voice_chat.gd` (`micHasPermission`, `micStart`,
`showNotification`), `net/net_notify.gd` (`requestPermission`, `hasPermission`,
`showNotification`, `startWatch`, `stopWatch`) und `update/update_config.gd` (`restartApp`).
Bleibt der Singleton aus (Mac, Windows, APK ohne Gradle-Bau), ist alles unverändert wie vorher.

**Prüfbar ohne Gerät:** am Mac gibt es den Singleton nicht, der Fehlerfall entsteht dort gar nicht.
`AndroidPlugin.self_test()` stellt ihn mit zwei Attrappen nach — `AttrappeJni` verhält sich wie ein
`JNISingleton` (`has_method("micStart")` falsch, `has_java_method("micStart")` wahr), `AttrappeSkript`
wie ein gewöhnliches Objekt. `--test-mikrofon` druckt die Prüfung mit („`Attrappen …`", Sollwert
0 Fehlschläge). Ob das Plugin auf Toms Gerät danach wirklich antwortet, entscheidet nur das Gerät.

**Reine GDScript-Änderung** — sie geht als Paketaktualisierung, ohne neue APK.

#### Diagnose auf dem Gerät

Die Mikrofonprobe zeigt unter dem Pegelbalken zwei Zeilen zum Abfotografieren — seit dem Gerätetest
mit **Mischrate der Engine** und **Geräteliste**, denn genau die beiden mussten damals per `adb`
nachgemessen werden:

```
Freigabe ja · Default · Engine 44100 Hz · 47990 F/s · ≠0 96% · roh 0.0011 · Neu 0
Geräte (1): Default
```

`≠0 0%` heißt stummer Eingang; `Freigabe NEIN` heißt fehlende Berechtigung; steht bei `Engine` eine
andere Zahl als die native Rate des Geräts, ist es der Ratenkonflikt von oben.

**Warum der Mac-Prüfstand das nicht finden konnte.** Am Mac gibt es weder die Laufzeitberechtigung
noch den OpenSL-Treiber; der Mac benutzt CoreAudio mit der Geräterate. Der Fall entsteht dort
prinzipiell nicht. Was sich am Mac belegen lässt, ist die Fallunterscheidung der Meldungen, der
Wächter und dass `reopen_input()` die Aufnahme wieder anwirft — **ob** eine Änderung den stummen
Strom auf Android rettet, entscheidet nur Toms Gerät.

### 11.3a Der Eingang auf iPhone und iPad — was Godot dort tut (2026-09-09)

Toms Frage: „Geht Mikrofon auch mit Teamspeak?" Antwort: **grundsätzlich ja, und der Weg ist ein
anderer als auf Android** — aber es fehlten zwei Einträge außerhalb des Codes, ohne die es gar nicht
laufen konnte. Beide sind jetzt drin. Am Gerät geprüft ist **nichts** davon; der Mac kann iOS nicht
ausführen. Was hier steht, ist am Godot-Quelltext belegt, nicht gemessen.

#### Der Befund: die Abtastrate ist auf Apple-Geräten **nicht** fest verdrahtet

Der Android-Fehler aus §11.3 hat auf iOS **kein Gegenstück**. `drivers/coreaudio/audio_driver_coreaudio.mm`
(Zweig `4.7`; die Datei heißt `.mm` und wird von macOS **und** iOS benutzt), `init_input_device()`:

```objc
#ifdef MACOS_ENABLED
    double hw_mix_rate;
    …
    AudioObjectPropertyAddress property_sr = { kAudioDevicePropertyNominalSampleRate, … };
    result = AudioObjectGetPropertyData(device_id, &property_sr, 0, nullptr, &hw_mix_rate_size, &hw_mix_rate);
#else                                                    // <— iOS
    double hw_mix_rate = [AVAudioSession sharedInstance].sampleRate;
#endif
    capture_mix_rate = hw_mix_rate;
    …
    strdesc.mSampleRate = capture_mix_rate;
    result = AudioUnitSetProperty(input_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, …);
```

Godot fragt das Gerät also nach seiner Rate und stellt den Recorder darauf ein. Das
`SL_SAMPLINGRATE_44_1` aus dem Android-Treiber gibt es hier nicht — **es braucht auf iOS deshalb
auch kein eigenes Aufnahme-Plugin.** `AudioDriverCoreAudio::get_input_mix_rate()` gibt genau diese
Zahl zurück, und die Diagnosezeile zeigt sie seit heute mit an (s. u.).

Damit ist die Quellenwahl auf iOS entschieden: **ENGINE**, und zwar als der richtige Weg, nicht als
Rückfall. `VoiceChat._start_capture()` kommt dort ohnehin nie an einen Plugin-Singleton — die AAR
steckt nur in der APK.

#### Zwei Einträge, ohne die nichts geht

**1. Die AVAudioSession-Kategorie.** Godots Vorgabe ist `Ambient`, und damit ist Aufnahme schlicht
nicht erlaubt. `core/config/project_settings.cpp:1760`:

```cpp
GLOBAL_DEF(PropertyInfo(Variant::INT, "audio/general/ios/session_category", PROPERTY_HINT_ENUM,
        "Ambient,Multi Route,Play and Record,Playback,Record,Solo Ambient"), 0);   // Vorgabe 0
```

`drivers/apple_embedded/app_delegate_service.mm:100 ff.` setzt sie beim App-Start:

```objc
int sessionCategorySetting = GLOBAL_GET("audio/general/ios/session_category");
AVAudioSessionCategory category = AVAudioSessionCategoryAmbient;
…
} else if (sessionCategorySetting == SESSION_CATEGORY_PLAY_AND_RECORD) {
        category = AVAudioSessionCategoryPlayAndRecord;
        options |= AVAudioSessionCategoryOptionDefaultToSpeaker;      // Ton bleibt am Lautsprecher
        options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
        options |= AVAudioSessionCategoryOptionAllowAirPlay;
}
[[AVAudioSession sharedInstance] setCategory:category withOptions:options error:nil];
```

Eingetragen in `game/project.godot` als `audio/general/ios/session_category=2` (= „Play and
Record"). Godot setzt dazu von selbst `DefaultToSpeaker` — die Sorge, der Ton lande beim
Sprechfunk am Telefonhörer statt am Lautsprecher, erledigt sich damit. Auf Android, Mac, Windows
und Linux liest diese Einstellung **niemand**; sie steht nur im iOS-App-Delegate.

**2. `NSMicrophoneUsageDescription`.** Fehlt der Schlüssel, **beendet iOS die App** beim ersten
Zugriff auf den Eingang — ohne Dialog, ohne Fehler, die App ist einfach weg. Die beiden
Preset-Schlüssel heißen (geprüft an `editor/export/editor_export_platform_apple_embedded.cpp:1972-2026`,
nicht geraten):

| Preset-Schlüssel | landet in |
|---|---|
| `privacy/microphone_usage_description` | `Info.plist` **und** `en.lproj/InfoPlist.strings` (Zeile 1992) — die Grundfassung ist also **englisch** |
| `privacy/microphone_usage_description_localized` | Wörterbuch Sprache → Text, je Sprache eine `<lang>.lproj/InfoPlist.strings` (Zeile 2020-2022); `"en"` wird dabei übersprungen (Zeile 1997) — **Deutsch gehört hierhin** |

Godot schreibt die `.lproj`-Dateien nur, wenn das Projekt überhaupt Übersetzungen führt (Zeile
1983) — bei uns der Fall (de/en). Beide Einträge stehen im Preset „iOS" in
`game/export_presets.cfg`. Apple verlangt einen Satz, der den **konkreten** Zweck nennt; „Diese App
braucht das Mikrofon" wird abgelehnt.

**Beide Einträge stecken in der IPA und lassen sich durch ein Aktualisierungspaket NICHT
nachtragen** (`project.godot` und das Preset sind nicht Teil des Pakets, s. Kopf von
`update_boot.gd`). Sie mussten also vor der ersten IPA hinein.

#### Die Freigabe: iOS meldet sie nicht, es liefert Stille

Anders als Androids OpenSL-Fassung prüft der Apple-Treiber **gar nichts**:

```objc
Error AudioDriverCoreAudio::input_start() {
    ERR_FAIL_NULL_V(input_unit, FAILED);
    input_buffer_init(capture_buffer_frames);
    OSStatus result = AudioOutputUnitStart(input_unit);      // keine Berechtigungsabfrage
    if (result != noErr) { ERR_PRINT("AudioOutputUnitStart failed, code: " + itos(result)); }
    return OK;
}
```

Den Systemdialog bringt iOS selbst, sobald der Eingang das erste Mal anläuft. **Abfragen können wir
ihn nicht:** `OS.request_permission()` ist in Godot 4.7 Android-only, und
`AVAudioSession.recordPermission` ist nicht nach GDScript durchgereicht. Verweigert der Nutzer,
liefert der Eingang **Nullen** — genau dasselbe Bild wie Toms Xperia, aber aus einem anderen Grund.

Daraus folgen drei Dinge im Code:

* `VoiceChat.has_permission()` gibt außerhalb von Android weiterhin `true` zurück. Das ist Absicht:
  die Notbremse soll `no_signal` melden („kein Signal, Ursache offen") und nicht `no_permission`
  („Freigabe fehlt nachweislich") behaupten, was wir gar nicht wissen können.
* Neu ist `VoiceChat.permission_state()` → `"ja" | "nein" | "unbekannt"`. Nur Android sagt ja/nein;
  iOS und macOS bekommen **„unbekannt"**. Bis zum 2026-09-09 stand in der Diagnosezeile dort
  „Freigabe ja", und das war schlicht falsch.
* Neu ist `VoiceChat.trouble_text_key(grund, praefix)`: der **Grund** bleibt plattformneutral (er
  misst nur Zählerstände), der **Handgriff** nicht. `no_signal` heißt auf Android und macOS „App
  einmal ganz schließen und neu starten", auf iOS zuerst „Einstellungen → PocketRA → Mikrofon"
  (`mp.mic_no_signal_ios` / `toast.mic_no_signal_ios`). Die vier Gründe aus §11.2 bleiben
  unverändert vier — es kommt kein fünfter dazu, nur ein zweiter Text für einen davon.

#### Die Diagnosezeile

`VoiceChat.diagnose()` zeigt jetzt **zwei** Raten statt einer und benennt die Plattform:

```
Freigabe unbekannt · Plattform iOS · Quelle: Engine 48000 Hz (Eingang 48000 Hz) · Default · … 
```

`Quelle` ist die Mischrate, mit der wir den Aufnahmebus auslesen; `Eingang` ist
`AudioServer.get_input_mix_rate()`, also die Rate, mit der das Gerät **wirklich aufnimmt**. Auf
Toms Xperia klaffen die beiden auseinander (44 100 gegen 48 000 — genau der Fehler aus §11.3), auf
iOS **müssen sie zusammenfallen**, weil der Apple-Treiber die Geräterate übernimmt. Damit lässt sich
der Befund oben am Gerät in einer Zeile nachprüfen, statt ihn wieder zu erraten.

#### Was erst ein Gerät entscheiden kann

Ehrlich benannt, damit niemand es für geprüft hält:

1. **Wann der Berechtigungsdialog kommt.** `init_input_device()` wird schon beim Start gerufen
   (`init()`, sobald `audio/driver/enable_input` steht) — ob iOS den Dialog dort, erst bei
   `AudioOutputUnitStart()` oder erst beim ersten Aufnahmeversuch zeigt, sagt der Quelltext nicht.
   Kommt er beim App-Start, wäre das unschön und ein Grund, `enable_input` erst bei Bedarf zu setzen.
2. **Ob `Play and Record` die Musikwiedergabe verändert.** `DefaultToSpeaker` ist gesetzt, die
   Lautstärke der Kategorie kann sich aber trotzdem anders anfühlen als unter `Ambient`.
3. **Ob godotengine/godot#108915** (Aufnahme stirbt nach 5–7 s Stille) auf iOS zuschlägt — der
   Fehlerbericht nennt Android/iOS/macOS. Unser `reopen_input()`-Wächter greift dort genauso, weil er
   am Engine-Weg hängt; belegt ist das nur am Mac.
4. **Ob überhaupt Ton ankommt.** Alles oben sagt nur, dass nichts mehr im Weg steht.

### 11.4 Technik

| Größe | Wert | Warum |
|---|---|---|
|---|---|---|
| Abtastrate | 8 kHz mono | Telefonband reicht für Sprache und halbiert die Datenmenge gegenüber 16 kHz |
| Paketlänge | 60 ms = 480 Abtastwerte | ~17 Pakete/s: flüssig, und weit unter dem Eimer des Vermittlers |
| Kompression | IMA-ADPCM, 4 Bit je Abtastwert | in GDScript in ~40 Zeilen, keine Fremdbibliothek, Rauschabstand gemessen 25,8 dB |
| Paket | 4 Byte Kopf + 240 Byte = 244 Byte → **328 Zeichen Base64** | der Vermittler kennt nur Text-Rahmen; weit unter 16 KB |
| Bandbreite | ~6,3 kB/s ≈ **50 kbit/s je aktivem Sprecher** | mit JSON-Rahmen; die Sprachschleuse sendet nur, solange wirklich geredet wird |

Aufnahmeweg (`game/scripts/net/voice_chat.gd`): `AudioStreamMicrophone` spielt auf den zur Laufzeit
angelegten, **stummen** Bus „FunkAufnahme" mit `AudioEffectCapture`; `_process` holt die Frames,
rechnet sie mit einem Kastenfilter auf 8 kHz mono herunter (`AudioServer.get_mix_rate() / 8000` ist
bei 44,1 kHz keine ganze Zahl), bildet 60-ms-Blöcke, misst den Effektivwert und schickt nur, wenn
die **Sprachschleuse** offen ist (auf ab 0,035, zu nach 0,45 s unter 0,018). Godot rechnet die
Effekte eines stummen Busses weiter — die Stummschaltung wirkt erst beim Mischen in den Zielbus,
darum hört sich niemand selbst über den Lautsprecher.

Jeder Block wird **eigenständig** kodiert: die ersten vier Byte tragen Vorhersagewert und
Schrittindex des ADPCM-Zustands. Ein verlorenes Paket kostet damit nur seine eigenen 60 ms statt
den Rest des Redezugs.

Wiedergabeweg: je sprechendem Platz ein `AudioStreamPlayer` mit `AudioStreamGenerator`
(`mix_rate = 8000`) auf dem Bus **„Funk"** (`default_bus_layout.tres`, Regler `radio` in
`Sfx.BUSES`) — getrennt von Musik, Effekten und EVA. Ruckelpuffer: 120 ms sammeln, bevor ein Platz
zu hören ist, höchstens 1,2 s Rückstand (mehr wird vorne gekappt).

**Berechtigungen:** `audio/driver/enable_input=true` in `game/project.godot` (Godot öffnet den
Eingang erst, wenn ein `AudioStreamMicrophone` spielt) und auf Android
`android.permission.RECORD_AUDIO` in `game/export_presets.cfg`; zur Laufzeit fragt
`voice_chat.gd request_permission()` mit `OS.request_permission()` und wartet auf das SceneTree-
Signal `on_request_permissions_result`. Verweigert der Nutzer, bleibt das Mikrofon aus und das HUD
sagt es an. **Beides braucht eine neue APK** — ein Aktualisierungspaket ersetzt weder
`project.godot` noch das Manifest.

**Warum kein Opus:** Opus wäre bei ~16 kbit/s deutlich sparsamer und besser. Dafür müsste libopus
in `gdext/` für macOS **und** Android gebaut, gebunden und mit `sim_version` verglichen werden — für
Fassung 1 unverhältnismäßig, zumal die Sprachschleuse die Funkzeit ohnehin auf das Gesprochene
beschränkt. Der Schritt lohnt erst, wenn 50 kbit/s je Sprecher im Feld stören; die Schnittstelle
(`codec`-Feld im Paket, `VoiceChat.CODEC`) ist dafür schon vorgesehen.

### 11.5 Sprache berührt die Sim nicht

Wie der Chat (§9): eigene Nachrichtenart, eigener Eimer, kein `world.issue()`, kein
`net_session`, nichts im Befehlsprotokoll `order_log.gd`, nichts im `state_hash`. `mp_smoke.py`
Abschnitt 8 prüft das ausdrücklich: während 20 Netzrahmen laufen Sprachpakete mit, die Bündel
tragen weiterhin nur `seat`, `cmds` und `hash`, und die Rahmenfolge bleibt lückenlos.

### 11.6 Was die Team-Zuordnung angeht

Der Vermittler filtert den Team-Kanal mit **demselben** Vergleich wie den Team-Chat:
`room.seats[seat]["team"]`, gesetzt über `slot{team}` aus der Lobby. Vorgabe ist heute für jeden
Platz `team = 0` — solange niemand ein Team wählt, erreicht der „Team-Kanal" damit alle. Sobald die
Lobby echte Teams vergibt (Zweig `feature/mp-teams`), stimmt es von selbst. Offen für Fassung 2:
`team = 0` als „kein Team" zu lesen (in OpenRA spielt jeder mit Team 0 für sich) — das gehört dann
für Chat **und** Sprechfunk gemeinsam geändert.

### 11.7 Prüfläufe

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
# HUD, Kanalfarben, Erstinfo, Mikrofonprobe, untere Leiste gegen den Einzelspieler
$G --path game --resolution 1920x1080 res://scenes/gesture_proto.tscn --quit-after 40000 -- \
   --dpi 420 --map keep-off-the-grass-2 --ai 0 --seed 1 --reveal --starting-units light \
   --test-sprechfunk --screenshot /tmp/funk.png
# Aufnahmekette mit dem ECHTEN Mikrofon, fünf Sekunden lang, Stufe für Stufe
$G --path game --resolution 1280x720 res://scenes/gesture_proto.tscn --quit-after 60000 -- \
   --dpi 420 --map keep-off-the-grass-2 --ai 0 --seed 1 --starting-units light --test-mikrofon 5
```

`--test-mikrofon [SEKUNDEN]` gibt je Sekunde Eingabegerät, Frames (und wie viele davon ≠ 0), rohen
Effektivwert, Effektivwert nach dem Herunterrechnen, Grundrauschen, Schleusenschwelle und -zustand
sowie erzeugte und abgeschickte Pakete aus, dann einen Klartext-Befund (`kein Frame` /
`durchgehend EXAKT 0` / `Schleuse hat nie geöffnet` / `Kette vollständig`). Danach schiebt er einen
Sinus in Sprechlautstärke auf den Aufnahmebus — damit läuft **echter** Ton durch dieselbe Strecke —
und prüft zum Schluss die Schleuse an acht eingespeisten Pegeln, den Nachlauf, alle **vier** Gründe
der Notbremse, das Wiederöffnen des Eingangs und den Wächter (genau drei Versuche bei durchgehend
Null) samt der Diagnosezeile. **Genau dieser Haken fehlte** vor Toms Handtest: `--test-sprechfunk` belegte den Weg
mit einem Sinuston *statt* des Mikrofons, die Aufnahmestrecke war nie geprüft.

### 11.8 Dateien

| Datei | Inhalt |
|---|---|
| `game/scripts/net/voice_chat.gd` | Quellenwahl (Plugin/Engine), `_feed_mono()`, Kastenfilter, Sprachschleuse, IMA-ADPCM, Wiedergabe je Platz, Berechtigung, Stummliste |
| `android/…/notify/VoiceInput.kt` | `AudioRecord` mit nativer Rate, `VOICE_COMMUNICATION`, AEC/NS, Ringpuffer, Lesefaden |
| `android/…/notify/PocketRaPlugin.kt` | `mic*`-Methoden nach GDScript (`@UsedByGodot`), dazu `restartApp()` |
| `game/scripts/update/update_config.gd` | `restart_supported()`/`restart()` gehen auf Android über `PocketRaPlugin.restartApp()` |
| `game/scripts/net/net_client.gd` | `send_voice()`, Signal `voice_packet`, Empfang von `voice` |
| `game/scripts/net/net_hub.gd` | `ensure_voice()`, Verdrahtung mit dem Client, `seat_name()`, `other_human_seats()` |
| `game/scripts/ui/hud_theme.gd` | `mic_icon()`, `wire_tap_hold()`, `VOICE_OFF/TEAM/ALL`, BBCode-Fassung von `show_help_popup()`, `mic_probe_row()` |
| `game/scripts/proto/proto_main.gd` | Chat-/Mikrofonknopf in der Kopfzeile (`_layout_top_comm()`), Kanalzeile, Sprecheranzeige, Stummliste, Erstinfo, Optionen, `--test-sprechfunk`, `--mp-voice` |
| `game/scripts/sfx.gd`, `game/default_bus_layout.tres` | Bus „Funk" und Regler `radio` |
| `game/project.godot`, `game/export_presets.cfg` | `audio/driver/enable_input`, `RECORD_AUDIO` |
| `server/mp_server.py` | Nachricht `voice`, Teamfilter, Größen- und Rate-Grenze, eine Protokollzeile je Redezug |
| `server/mp_smoke.py` | Abschnitt 8 |

## 12. Spielerliste im Spiel (2026-09-09, Zweig `feature/mp-spielerliste`)

Toms Wunsch aus dem Handtest: „Kann man bei Mehrspieler im Game bei den Optionen Spieler anzeigen
machen, wo ich sehen kann, wer noch spielt, welche Farbe, welche Allianz, welches Team?"

### 12.1 Wo sie sitzt

Im **Pausenmenü** als Eintrag **„Spieler"**, an der Stelle, an der bis dahin „Chatverlauf" stand.
Beides ist zusammengelegt, statt zwei Listen nebeneinander zu führen: die Stummschalter des
Sprechfunks (§11.1) standen ohnehin schon je Mitspieler unter „Chatverlauf" und sitzen jetzt in der
Zeile des jeweiligen Platzes; Chatverlauf und „Sprechfunk erklären" stehen darunter in derselben
Tafel. Das Pausenmenü bleibt dadurch im Mehrspieler bei **sechs** Einträgen.

Im **Gefecht gegen die KI** gibt es dieselbe Liste (ohne Chatverlauf und ohne Stummschalter): dort
ist sie der achte Eintrag im Pausenmenü. Sie verlängert es nicht — im Querformat waren zwei Spalten
× vier Reihen schon bei sieben Einträgen nötig, die achte Zelle stand leer. In einer **Mission**
fällt der Eintrag weg (`_place_players()` läuft dort nicht, es gäbe keine Plätze zu zeigen).

### 12.2 Was in einer Zeile steht

| Spalte | Inhalt | Quelle |
|---|---|---|
| Farbklecks | Spielerfarbe wie in der Lobby und auf dem Feld | `ProtoWorld.player_colors[sim]` (= `ChatPanel.player_color(color)` der Lobby) |
| Name | Spielername; KI als „KI *n* (Stufe)"; im Gefecht der eigene Name aus den Mehrspieler-Einstellungen, sonst „Ich" | `setup.seats[].name` / `kind` / `level` |
| Team | „Team *n*" in Gold, „–" gedämpft für „kein Team" | `setup.seats[].team` (der Vermittler stempelt es beim `start`, §4.1) |
| Verhältnis | „ich" (gold) / „verbündet" (grün) / „feindlich" (rot) | `World::hostile(local, sim)` — dieselbe Quelle wie der Tipp-Pfad |
| Zustand | „im Spiel (*n*)", „besiegt", „Verbindung weg", „keine Antwort" | `World::alive_count`, `World::win_state`, `net_session.alive_seats` / `waiting_seats` |
| Stumm | „hörbar" / „stumm" (nur fremde menschliche Plätze im Mehrspieler) | `voice_chat.is_muted(seat)` (§11.1) |

Die Reihenfolge der Zustände folgt OpenRA `WidgetUtils.WithSuffix`: **weg > gewonnen > verloren**,
danach erst „keine Antwort" und „im Spiel". „Noch im Spiel" heißt genau das, was Tom gemeint hat:
der Platz hat noch Actors (`World::alive_count`, Einheiten **und** Gebäude — die Zahl in Klammern).

Sortiert wird nach Team (aufsteigend), „kein Team" hinten; innerhalb eines Teams nach Sim-Index.

### 12.3 Woher die Angaben kommen — eine Stelle

`ProtoWorld.player_roster` ist die **einzige** Abschrift: eine Liste
`{sim, seat, name, faction, team, kind, level, bot_no, color, color_index}`, gefüllt in
`_apply_setup()` (Mehrspieler, aus der Aufstellung des `start`) und in `_place_players()` (Gefecht,
aus der Lobby-Wahl). Sie enthält nur **feste** Angaben. Alles Veränderliche liefert
`ProtoWorld.roster_status(sim)` (`alive`, `win_state`, `relation`) frisch aus der Sim; den
Netzzustand steuert `net_session` bei. Nichts wird an einer zweiten Stelle nachgerechnet.

**Keine neue Netznachricht.** Team, Farbe, Name, Art und KI-Stufe stehen seit dem 2026-09-09 alle in
`setup.seats` (§4.1), `peer_left` und `waiting` gab es schon.

Eine bekannte Lücke im **Gefecht**: der Spielstand (`save_game.gd`) trägt Karte, Fraktionen,
KI-Zahl und KI-Stärke im Kopf, aber **keine Teamzahlen** (`next_player_team`/`next_ai_slots`). Nach
dem Laden kann die Team-Spalte deshalb von der gespeicherten Runde abweichen; „verbündet /
feindlich" stimmt trotzdem, weil es aus der geladenen Sim kommt (`World::hostile`), nicht aus der
Teamzahl.

### 12.4 Determinismus

Reine Anzeige. Kein `world.issue()`, kein Paket, kein Eintrag im Befehlsprotokoll `order_log.gd`,
nichts im `state_hash`; `alive_count`, `win_state` und `hostile` sind lesende Aufrufe. Das Öffnen
hält bei niemandem die Partie an — im Mehrspieler pausiert schon das Pausenmenü selbst nicht
(`world.paused = _menu_panel.visible and not _mp_active()`). Die Zeilen ziehen im Sekundentakt nach,
solange die Tafel offen steht.

### 12.5 Abweichungen von OpenRA (bewusst)

Vorbild ist das Beobachterfenster `ObserverStatsLogic` (Reiter „Basic", nach Team gruppiert):

1. **Keine Team-Überschriften.** OpenRA setzt je Gruppe eine Zeile darüber; am Handy kosten bis zu
   sechs Überschriften mehr Höhe, als sie einbringen. Die Teamzahl steht deshalb je Zeile.
2. **Eigene Spalte „verbündet / feindlich / ich".** OpenRA drückt das Verhältnis durch **Umfärben
   der Spielerfarbe** aus (`Player.SetupRelationshipColors`, `PlayerStanceColorSelf/Allies/Enemies`).
   Das würde hier genau die Farbe unbrauchbar machen, nach der Tom gefragt hat; die drei Farben
   sitzen darum im Verhältnistext.

### 12.6 Dateien

| Datei | Inhalt |
|---|---|
| `game/scripts/proto/proto_world.gd` | `player_roster`, `_roster_add()`, `roster_status()`; gefüllt in `_place_players()` und `_apply_setup()` |
| `game/scripts/proto/proto_main.gd` | `_show_player_list()`, `_player_row()`, `_player_cell()`, `_roster_name()`; `PAUSE_GRID`/`MP_PAUSE_GRID`; Prüfhaken `--test-spielerliste`; Seite „spieler" in `--test-layout` |
| `game/i18n/strings.csv` | `pause.players*`, `pause.rel_*`, `pause.state_*`, `mp.voice_audible` (de/en) |

### 12.7 Gemessen am 2026-09-09 (Mac)

| Lauf | Ergebnis |
|---|---|
| `--test-spielerliste` (Gefecht + Mehrspieler-Aufstellung, de/en) | 0 Befund(e); 4 von 4 Plätzen, Farben `f2bc18/f50606/2f86f2/06f739` deckungsgleich mit der Lobby, Zeilen „ich / verbündet / feindlich", „Verbindung weg" nach `peer_left{seat:2}`, „besiegt" bei `alive_count 0`, 2 Stummschalter, Layout 0 Verstöße |
| `--test-layout` (Spiel, jetzt mit Seite „spieler", de/en) | je 0 Verstöße |
| `--test-layout` (Menü, de/en) | je 0 Verstöße |
| `--test-sprechfunk` | 0 Befund(e) — die Stummschalter wirken weiter |
| `--test-hit` (Xperia/iPhone/iPad) | 0 Fehlschläge |
| `--test-cycle` | Menü → Gefecht → Menü → Mission → Menü ohne Skriptfehler |

### 11.9 Neustart per Knopfdruck nach einer Paketaktualisierung (2026-09-09)

Toms Wunsch: „falls es easy machbar ist, wenn eine Paketaktualisierung da war, dann muss ich ja die
App neu starten, geht das nicht auch per Knopfdruck?"

Godot kann sich auf Android nicht selbst neu starten — `OS.set_restart_on_exit()` wirkt nur auf dem
Desktop. Das vorhandene Plugin kann es: `PocketRaPlugin.restartApp()` holt sich den Start-Intent des
eigenen Pakets (`PackageManager.getLaunchIntentForPackage`), hängt `FLAG_ACTIVITY_NEW_TASK` und
`FLAG_ACTIVITY_CLEAR_TASK` an, startet die Activity neu und beendet 400 ms später den alten Prozess
(`Process.killProcess`) — erst damit hängt `UpdateBoot` das frische `current.pck` vor allen
Autoloads ein.

`UpdateConfig.restart_supported()` gibt deshalb auf Android jetzt `true` zurück, **sobald** das
Plugin da ist; die Statuszeile des Hauptmenüs zeigt dann denselben Knopf „Jetzt neu starten" wie auf
dem Desktop (`update.restart_now`). Ohne Plugin — APK ohne Gradle-Bau, oder wenn `restartApp()`
`false` liefert — bleibt es unverändert beim Hinweis „Beim nächsten Start der App aktiv."
(`update.restart_hint`). Neue Texte braucht es dafür keine, beide stehen schon zweisprachig in
`strings.csv`.
