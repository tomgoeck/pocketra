# Umbenennung auf PocketRA und die Brücke auf `redalert.attomic.de`

Stand 2026-09-09. Toms Auftrag: „Wir müssten jetzt aber bitte es so verdrahten, dass die neueste
Version von pocketra.net/pocketra.apk heruntergeladen wird. Redalert soll nirgends mehr auftauchen."

## 1. Was sich geändert hat

| Was | Alt | Neu |
|---|---|---|
| Anzeigename der App | `Red Alert` / de `Alarmstufe Rot` | **`PocketRA`** (beide Sprachen) |
| Android-Paket-Kennung | `dev.tom.redalert` | **`net.pocketra.app`** |
| Nutzerordner | `Godot/app_userdata/redalert` | **`Godot/app_userdata/pocketra`** |
| Versionsdatei / Downloads | `redalert.attomic.de` | **`pocketra.net`** |
| Verteil-APK auf dem Server | `redalert-dist.apk` + `redalert.apk` | **`pocketra.apk`** (nur noch ein Name) |
| Vollfassung auf dem Server | `redalert-full.apk` | **entfällt** — seit 2026-09-09 wird nur noch die Verteilfassung veröffentlicht (s. §3) |
| Windows-Paket | `redalert-windows.zip` | **`pocketra-windows.zip`** |
| Kotlin-Paket des Plugins | `de.attomic.redalert.notify` | **`net.pocketra.app.plugin`** |
| Godot-Plugin (Singleton) | `RedAlertNotify` | **`PocketRaPlugin`** |
| Addon-Ordner | `game/addons/redalert_notify/` | **`game/addons/pocketra_plugin/`** |
| Kotlin-Modul | `android/redalert_notify/` | **`android/pocketra_plugin/`** |
| Bau-Skript des Plugins | `tools/notify_plugin_build.sh` | **`tools/plugin_build.sh`** |
| systemd-Unit des Vermittlers | `redalert-mp.service` | **`pocketra-mp.service`** |
| Web-Ordner auf dem Server | `/var/www/redalert` | **`/var/www/pocketra`** |

**Nicht** umbenannt: `ra::`, `RaSim`, `rasim.gdextension`, `librasim.*`, `sim/`, `gdext/` — „RA"
steckt im neuen Namen PocketRA weiter drin, es ist kein Markenbezug, und der Symbolname der
Extension samt Ladepfaden hängt daran. Ebenfalls unverändert bleiben die **sachlichen** Hinweise auf
das Originalspiel: woher die Spieldaten kommen (eigene Red-Alert-CD bzw. das EA-Freeware-Paket von
2008), OpenRA als Regelquelle und die Dateinamen der Originalinhalte (`MAIN.MIX`, `redintro`, …).

## 2. Warum das eine Neuinstallation erzwingt

Android identifiziert eine App über `package/unique_name`. Mit dem Wechsel von `dev.tom.redalert`
auf `net.pocketra.app` ist PocketRA für das Gerät eine **andere** App:

* sie lässt sich nicht über die alte installieren (kein In-Place-Update, keine Signaturprüfung),
* sie startet mit leerem `user://` — Spielstände, Einstellungen, das heruntergeladene Inhaltspaket
  (`user://content/`) und das eingehängte Aktualisierungspaket (`user://update/`) kommen **nicht**
  mit, weil auch `custom_user_dir_name` von `…/redalert` auf `…/pocketra` gewechselt ist,
* die alte App bleibt daneben installiert, bis der Nutzer sie von Hand löscht.

Tom hat das bewusst so entschieden. Die Brücke unten sorgt dafür, dass die alte Installation den
Umstieg trotzdem mitbekommt.

## 3. Die Brücke: `version.json` auf `redalert.attomic.de`

`redalert.attomic.de` bleibt bestehen und liefert genau **eine** Datei weiter, nämlich
`https://redalert.attomic.de/version.json`. Genau die fragt jede alte Installation beim Start ab
(`UpdateConfig.DEFAULT_URL` der Fassungen bis 0.15).

### Wie die alte App diese Datei auswertet

`game/scripts/update/update_service.gd` `_handle_version()` geht der Reihe nach vor:

1. `disabled: true` → sofort sperren.
2. `min_supported` höher als die eigene `application/config/version` (die alten Fassungen melden
   höchstens `0.15`) → **sperren**. `UpdateConfig.set_blocked()` schreibt Grund, `notes`, `apk_url`
   und die Fassungsbezeichnung nach `user://update/state.json` — die Sperre gilt damit auch beim
   nächsten Start **ohne Netz**.
3. sonst: ist `apk_version` höher als die eigene, kommt **einmal je Version** ein Hinweisfenster
   („Neue Version %s verfügbar"), das Spiel läuft aber normal weiter.
4. danach erst Paketvergleich (`pack_version`) — bei gesperrter App wird der Punkt nie erreicht.

Gesperrt zeigt `main_menu.gd` die nicht wegdrückbare Seite `UpdatePage`:
Überschrift „Diese Fassung wird nicht mehr unterstützt", darunter der Text aus `notes`, dann die
Knöpfe **„Neue App herunterladen"** (`OS.shell_open(apk_url)`, öffnet den Browser), „Erneut prüfen"
und „Beenden". Gefecht, Missionen und Tutorial sind gesperrt. Genau das brauchen wir: die alte App
kann sich nicht selbst ersetzen, sie muss den Nutzer zum Download schicken.

**Welche URL der Knopf öffnet**, entscheidet `UpdateConfig.apk_choice()` anhand der installierten
Fassung (liegt `res://assets/atlas/atlas_temperat.json` in der APK → Vollfassung):
Vollfassung → `apk_url_full`, sonst → `apk_url`. Fehlt `apk_url_full`, bekommt auch die Vollfassung
`apk_url`.

Toms Regel 2026-09-09 — „wir verteilen keine Vollfassung mehr, nur noch die `-dist`-Variante, um
uns nicht angreifbar zu machen" — macht diesen Rückfall zum **Normalfall**: die Brücke setzt
`apk_url_full` gar nicht mehr, jede alte Installation landet auf
`https://pocketra.net/pocketra.apk`. Das ist gewollt. Wer die Vollfassung hatte, holt sich die
Spieldaten in PocketRA über die Seite „Spielinhalte einrichten" neu — bei der neuen Paket-Kennung
wären sie ohnehin nicht mitgekommen (§2).

### Die Datei, die auf `redalert.attomic.de` liegen muss

```json
{
  "pack_version": 0,
  "pack_label": "umzug-pocketra",
  "pack_url": "https://pocketra.net/update.pck",
  "pack_sha256": "",
  "pack_size": 0,
  "min_extension": "0",

  "apk_version": "0.16",
  "apk_url": "https://pocketra.net/pocketra.apk",
  "apk_size": 130000000,

  "min_supported": "0.16",
  "disabled": false,

  "notes": "Das Spiel heißt jetzt PocketRA und liegt unter pocketra.net. Diese Fassung wird nicht mehr versorgt. Bitte einmal die neue App laden und installieren: https://pocketra.net/pocketra.apk — sie läuft neben der alten, Spielstände und heruntergeladene Spieldaten kommen nicht mit, die Spieldaten lädt PocketRA beim ersten Start neu. Danach kann die alte App gelöscht werden. / The game is now called PocketRA at pocketra.net. Please install the new app once; saves and downloaded game data do not carry over."
}
```

Feld für Feld:

| Feld | Wert | Warum |
|---|---|---|
| `min_supported` | `"0.16"` | Auslöser der Sperre. `UpdateBoot.cmp_version()` vergleicht **zahlenweise** je Punktgruppe, `0.15 < 0.16` ist also wahr — jede je verteilte Fassung unter der alten Paket-Kennung (höchstens `0.15`) wird gesperrt. `"0.16"` statt einer Fantasiezahl, weil das die erste PocketRA-Fassung ist und der Grund damit selbsterklärend bleibt. |
| `disabled` | `false` | Der Notschalter wird **nicht** gebraucht; `min_supported` sperrt schon alles und liest sich als Versionsgrenze statt als „Server hat abgeschaltet". Beide Wege enden auf derselben Seite. |
| `notes` | s. o. | Steht wörtlich auf der Sperrseite. Kein `tr()`, kein Umbruchzwang — die Seite bricht selbst um (`AUTOWRAP_WORD_SMART`). Deutsch zuerst, ein englischer Satz hinterher. |
| `apk_url` | `https://pocketra.net/pocketra.apk` | Ziel des Knopfes „Neue App herunterladen" für alle **Verteilfassungen**. Genau die Adresse, die Tom weitergibt. |
| `apk_url_full` | **nicht gesetzt** | Es gibt keine veröffentlichte Vollfassung mehr (Toms Regel 2026-09-09). Ohne das Feld bietet `apk_choice()` auch einer Vollfassung `apk_url` an — genau das soll passieren. Früher stand hier `https://pocketra.net/pocketra-full.apk` (Toms Befund 2026-09-06). |
| `apk_size` | echte Bytezahl | nur Anzeige („Verteilfassung (130 MB)"). `0` blendet die Größe aus, kaputt geht nichts. |
| `apk_version` | `"0.16"` | Für den Fall, dass jemand `min_supported` später herausnimmt: dann greift statt der Sperre der sanfte Hinweis auf dieselben URLs. |
| `pack_version` | `0` | Muss **kleiner oder gleich** dem sein, was die alte Installation schon hat, damit nach einem entfernten `min_supported` kein Paket mehr gezogen wird. `0` ist immer sicher. |
| `pack_url` / `pack_sha256` / `pack_size` | Platzhalter | wird bei gesperrter App nie gelesen. Nicht weglassen: `_handle_version()` liest die Felder erst nach der Sperre, ein fehlendes Feld wäre trotzdem unhöflich gegenüber späteren Fassungen. |
| `min_extension` | `"0"` | dito. |

### Sanftere Variante (Übergangsfrist)

Soll die alte App noch eine Weile spielbar bleiben, `min_supported` **weglassen** und nur
`apk_version` setzen. Dann kommt beim Start einmal je Version das Fenster „Neue Version 0.16
verfügbar" mit demselben `notes`-Text und den Knöpfen „Herunterladen" / „Später"; gespielt werden
darf weiter. Später `min_supported` nachtragen macht aus dem Hinweis die Sperre — die alte App
fragt bei jedem Start neu.

### Grenzen der Brücke

* Wer **„Aktualisierungen beim Start prüfen"** ausgeschaltet hat (`user://settings.cfg`
  `[update] check_on_start=false`), fragt gar nicht und sieht nichts.
* Wer den Server nie erreicht, spielt unverändert weiter — Absicht: ein Serverausfall darf niemandem
  das Spiel wegnehmen.
* Wer in `user://settings.cfg` `[update] url=…` von Hand gesetzt hat, hängt an seiner eigenen
  Adresse.
* Eine Installation, die schon eine `state.json` mit Sperre hat, bleibt gesperrt, bis der Server
  wieder ohne `min_supported` antwortet.

### Was auf `redalert.attomic.de` sonst noch liegen sollte

Nur die `version.json` und eine kleine `index.html`, die auf `https://pocketra.net/` weiterleitet.
Die alten APKs (`redalert-dist.apk`, `redalert.apk`, `redalert-full.apk`,
`redalert-windows.zip`) und `update.pck` können weg, sobald die Brücke steht — die neue App fragt
sie nie, und die alte kommt wegen der Sperre nicht mehr bis zum Paketvergleich. Der
Mehrspieler-Pfad `wss://redalert.attomic.de/mp` darf ebenfalls verschwinden: gesperrte alte
Installationen kommen nicht mehr ins Gefecht, neue sprechen `wss://pocketra.net/mp`.

## 4. Der Name des Android-Plugins — die sechs Stellen

Weicht **eine** davon ab, findet Godot den Singleton nicht mehr und Benachrichtigungen,
Mikrofonaufnahme und Neustart auf Android fallen still aus:

| Stelle | Wert |
|---|---|
| `android/pocketra_plugin/src/main/java/net/pocketra/app/plugin/PocketRaPlugin.kt` — `getPluginName()` | `PocketRaPlugin` |
| `android/pocketra_plugin/src/main/AndroidManifest.xml` — `meta-data android:name` | `org.godotengine.plugin.v2.PocketRaPlugin` |
| dieselbe Zeile — `android:value` (Klasse) | `net.pocketra.app.plugin.PocketRaPlugin` |
| `game/addons/pocketra_plugin/export_plugin.gd` — `PLUGIN_NAME` und `AndroidExportPlugin.NAME` | `PocketRaPlugin` |
| `game/scripts/net/net_notify.gd` — `SINGLETON` | `PocketRaPlugin` |
| `game/scripts/net/voice_chat.gd` — `PLUGIN_SINGLETON`, `game/scripts/update/update_config.gd` — `ANDROID_PLUGIN` | `PocketRaPlugin` |

Dazu, unabhängig vom Singleton-Namen, aber genauso zwingend gleich: das Kotlin-Paket
`net.pocketra.app.plugin` (Dateikopf, `build.gradle` `namespace`, `consumer-rules.pro`
`-keep class net.pocketra.app.plugin.**`, `WatchService.ACTION_START`) und der AAR-Name
`pocketra_plugin-{debug,release}.aar` (`settings.gradle` `rootProject.name`, `export_plugin.gd`,
`tools/plugin_build.sh`, `.gitignore`).

Prüfen ohne Gerät:

```sh
sh tools/plugin_build.sh
cd /tmp && rm -rf aarcheck && mkdir aarcheck && cd aarcheck \
  && unzip -o ~/Projects/redalert/game/addons/pocketra_plugin/bin/pocketra_plugin-release.aar > /dev/null \
  && grep -o 'org.godotengine.plugin.v2.[A-Za-z]*' AndroidManifest.xml \
  && unzip -o classes.jar > /dev/null \
  && javap -classpath . net.pocketra.app.plugin.PocketRaPlugin | head -3
```

## 5. Was außerhalb von Git angepasst werden muss

* `build/update/upload.conf` (liegt in `build/`, nicht im Repository):
  `TARGET=pocketra-upload:/var/www/pocketra/` und `BASE_URL=https://pocketra.net`
* `~/.ssh/config`: Alias `pocketra-upload` (Kopie des alten `redalert-upload`-Blocks, ohne
  `RemoteCommand`, damit `rsync` funktioniert). `tools/update_pack.sh` und `tools/mp_deploy.sh`
  benutzen ihn.
* Auf dem Server: alte Unit `redalert-mp` stoppen, deaktivieren und
  `/etc/systemd/system/redalert-mp.service` löschen, bevor `tools/mp_deploy.sh` die neue Unit
  `pocketra-mp` startet — beide wollen `127.0.0.1:8787`. Danach `/opt/redalert-mp` und den
  Systembenutzer `redalert-mp` entfernen.
