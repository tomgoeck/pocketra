## Project context
Always read `project-docs/index.html` and `project-docs/MAINTENANCE.md` before planning any task in this repository. They contain the authoritative project state, file map, and editing protocol.

## Spiellogik
Alle Spiellogik folgt OpenRA (Toms Fork `tarek369/OpenRA`, lokaler Shallow-Clone unter `reference/OpenRA/`, gitignored). Vor neuer Logik die OpenRA-Stelle lesen und im Code referenzieren; Abweichungen kommentieren und in `docs/ARCHITEKTUR.md` §3a eintragen.

## Arbeitsablauf nach Sim-Änderungen
`sim/tests/run.sh` → `cd gdext && scons platform=macos …` → `scons platform=android …` (nacheinander) → `Godot --headless --path game --import` → Mac-Lauf auf Skriptfehler → Export → `adb devices` → `adb install -r build/pocketra-dist.apk` → App starten. Kommandos vollständig in `project-docs/index.html` (Architecture → Kommandos) und `README.md`.

## Arbeitsablauf nach Regeländerungen
Ändert sich `tools/rules2json.py` (neue Trait-Felder in `extract_actor`/`extract_weapon`), immer
**beide** Läufe: `python3 tools/rules2json.py && python3 tools/mapconvert.py`. `mapconvert.py` baut die
kartenlokalen `Rules:` mit derselben Funktion, und ein Actor im Karten-Delta **ersetzt** den globalen
Eintrag vollständig — sonst fehlt das neue Feld still auf jeder Karte. `game/assets/` liegt nicht im
Git, der Fehler wandert also nicht über Commits, sondern sitzt im Arbeitsbaum. Beide Ausgaben tragen
den Stempel `rules_format`; `RulesDb.build` warnt beim Kartenstart, wenn er auseinanderläuft.

## Testen
Tom testet selbst auf dem Sony Xperia 5 V. Während er testet keine `adb input`-Gesten schicken und keine APK austauschen.

## Veröffentlichung — alle Plattformen (Toms Regel 2026-09-09, erweitert 2026-09-04)
Nach jeder abgeschlossenen Änderungsrunde (Merge in den Integrationszweig, Tests grün) wird eine
neue Version veröffentlicht — nicht erst auf Nachfrage. EIN Kommando erledigt alle Plattformen:

```
tools/release_all.sh
```

Es baut nacheinander Android-, Windows- und macOS-Verteilfassung, schickt iOS zu TestFlight, lädt
Server und GitHub hoch. Einzelne Beine: `--only android,ios` (Komma-Liste aus `android,windows,
macos,ios,server,github`); Details, Voraussetzungen und Grenzen stehen im Kopf des Skripts. Ändert
sich die Extension (gdext/sim) oder `project.godot`/Startlader, vorher `version/name` und
`version/code` in `game/export_presets.cfg` sowie `config/version` in `project.godot` erhöhen.

**Downloads liegen nur auf pocketra.net, nicht auf GitHub** (Toms Entscheidung 2026-09-09): GitHub
ist reine Quellcode-Ablage für die GPL-Pflicht (s. u.), keine Downloadquelle für die App. Die
Website (`website/index.html`) verlinkt Android/Windows/macOS direkt auf `pocketra.net` und liest
Version/Größe/Hinweistext live aus `pocketra.net/version.json`.

**Nur Verteilfassungen ohne EA-Inhalte gehen öffentlich** (Entscheidung 2026-09-09: „um sich nicht
angreifbar zu machen"). Android/Windows/macOS haben dafür je ein `…-Preset` bzw. eine `--dist`-Fahne
(`Android Verteilung`, `Windows Verteilung`, `macOS`; export_presets.cfg schließt `assets/atlas|sfx|
video` aus) — Atlanten, Soundeffekte und Missionsfilme lädt die App zur Laufzeit über „Spielinhalte
einrichten" nach. Die Vollfassungen (Preset „Android"/„Windows", EA-Inhalte eingebacken) bleiben
Toms Entwicklerstand und werden von `tools/release_all.sh` nicht angefasst — niemals von Hand
irgendwo hochladen, wo sie öffentlich erreichbar wären.

Was die einzelnen Beine tun (auch einzeln aufrufbar):
- **Server** (`tools/update_pack.sh --slim --upload`): Aktualisierungspaket + version.json nach
  `https://pocketra.net/`, Upload-Ziel `build/update/upload.conf`, SSH-Alias `pocketra-upload`,
  Ordner `/var/www/pocketra`. Freunde bekommen Änderungen beim nächsten App-Start, ohne neue APK.
- **GitHub** (`tools/publish.py`): nur die kommentarfreie Quellcode-Kopie auf
  `github.com/tomgoeck/pocketra` (main) — keine Release-Anhänge mehr, die App-Fassungen liegen
  ausschließlich auf pocketra.net. Token in `build/github_token`. (`tools/gh_release.sh` bleibt als
  Werkzeug bestehen, wird von `release_all.sh` aber nicht mehr aufgerufen.)
- **TestFlight** (`tools/ipa_build.sh --release --upload`): interne Tester bekommen den Build ohne
  Prüfung; kein App-Store-Review, kein öffentlicher Link — das bleibt Toms manueller Schritt in App
  Store Connect.

Einmalige Einrichtung je Plattform (Zertifikate/Schlüssel) steht im Kopf von `tools/mac_build.sh`
und `tools/ipa_build.sh`.
