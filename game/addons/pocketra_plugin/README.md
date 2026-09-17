# PocketRaPlugin — Benachrichtigungen ohne FCM

Godot-Android-Plugin (Format **v2**, ab Godot 4.2; das alte `.gdap` gibt es nicht mehr).
Vollständige Beschreibung: `docs/MULTIPLAYER.md` §10.

| Datei | Zweck |
|---|---|
| `plugin.cfg` | Editor-Addon-Kopf |
| `export_plugin.gd` | hängt die AAR über `EditorExportPlugin._get_android_libraries()` in den Gradle-Bau |
| `bin/pocketra_plugin-{debug,release}.aar` | Bauergebnis aus `android/pocketra_plugin/` — **nicht** im Git |

Der Quelltext liegt in `android/pocketra_plugin/` (Kotlin), gebaut wird mit
`sh tools/plugin_build.sh`.

## Was es tut

* legt zwei Benachrichtigungskanäle an (`mp_service` still und dauerhaft, `mp_events` für Ereignisse),
* fragt ab Android 13 `POST_NOTIFICATIONS` an,
* hält als **Vordergrunddienst** eine eigene WebSocket-Verbindung zum Vermittler
  (`watch{code, token}`) — Godot friert im Hintergrund die Hauptschleife ein und kann das nicht,
* meldet: jemand betritt den Raum, jemand schreibt im Raum-Chat, die Partie beginnt,
* ein Tipp auf die Meldung holt die App zurück in die Lobby.

## Voraussetzung

Ein Android-Plugin läuft **nur** mit dem Gradle-Bau. Das Projekt exportiert bisher mit den
vorgefertigten Vorlagen; die vier Schritte zum Umstellen stehen in `docs/MULTIPLAYER.md` §10.5.

Solange das nicht geschehen ist, passiert nichts Schlimmes: `game/scripts/net/net_notify.gd` findet
den Singleton `PocketRaPlugin` nicht und tut nichts, `export_plugin.gd` warnt und hängt nichts ein.
Das Wiederverbinden nach einem Hintergrundwechsel (§10.2/§10.3) hängt **nicht** an diesem Plugin.

## Zweite Aufgabe: Aufnahme fuer den Sprechfunk (seit 2026-09-09)

`VoiceInput.kt` nimmt ueber `AudioRecord` auf — `MediaRecorder.AudioSource.VOICE_COMMUNICATION`,
native Geraeterate (aus `AudioRecord.sampleRate` zurueckgelesen), mono, 16 Bit, eigener Lesefaden,
Ringpuffer von einer Sekunde. `PocketRaPlugin` reicht das ueber `micStart/micStop/micRate/
micAvailable/micRead/micInfo/micHasPermission/micRequestPermission` nach GDScript
(`game/scripts/net/voice_chat.gd`); `micRead(n)` gibt ein `float[]` zurueck, in Godot also ein
`PackedFloat32Array` am Stueck.

Grund: Godots eigener Android-Eingang fordert den Recorder **fest** mit 44 100 Hz an
(`SL_SAMPLINGRATE_44_1`) und liefert auf Geraeten mit 48 000 Hz nur Nullen — nachgemessen auf einem
Sony Xperia 5 V. Ausfuehrlich in `docs/MULTIPLAYER.md` §11.3.

Ohne dieses Plugin faellt der Sprechfunk auf Godots Eingang zurueck; auf Mac und Windows ist das
ohnehin der Weg.
