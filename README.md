# PocketRA

Ein Neubau von *Command & Conquer: Red Alert* für Android: Oberfläche und Touch-Bedienung in
Godot 4, die Spielsimulation in C++ (GDExtension), Spiellogik nach [OpenRA](https://www.openra.net).
Gefecht gegen KI, Mehrspieler über Spielcode, Deutsch und Englisch.

* Website: https://pocketra.net
* Lizenz: GPL-3.0-or-later (`LICENSE`), Herkunftshinweise in `NOTICE`

**EA has not endorsed and does not support this product.** *Command & Conquer* und *Red Alert*
sind Marken von Electronic Arts Inc. Dieses Repository enthält keine Spieldaten von EA.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `game/` | Godot-Projekt (GDScript, Szenen, Übersetzungen, Symbole) |
| `gdext/` | GDExtension-Brücke zur Simulation, `godot-cpp` als Submodul |
| `sim/` | C++-Simulation (deterministisch, Ganzzahlen) und Tests |
| `tools/` | Pipeline: MIX/SHP/AUD/VQA der Originaldateien → Atlanten, Sounds, Karten, Regeln |

## Bauen

Voraussetzungen: Godot 4.7, Python 3.11+, SCons, ffmpeg, Android SDK/NDK für die APK.

1. Spieldaten beschaffen (nicht im Repository): `ra-quickinstall.zip` von einem OpenRA-Spiegel
   (Liste: https://www.openra.net/packages/ra-quickinstall-mirrors.txt) nach `content/ra/`
   entpacken, oder `MAIN.MIX`/`REDALERT.MIX` der eigenen CD dorthin kopieren.
2. OpenRA-Referenz für Regeln und Karten: `git clone --depth 1 https://github.com/OpenRA/OpenRA reference/OpenRA`
3. Pipeline (erzeugt `game/assets/`):
   ```bash
   python3 tools/rules2json.py
   python3 tools/tileset2atlas.py temperat && python3 tools/tileset2atlas.py snow && python3 tools/tileset2atlas.py interior
   python3 tools/mapconvert.py
   python3 tools/audconvert.py $(cat tools/sounds.txt) -o game/assets/sfx
   ```
4. Simulation und Brücke:
   ```bash
   sim/tests/run.sh
   git submodule update --init
   cd gdext && scons platform=macos arch=arm64 target=template_debug
   cd gdext && scons platform=android arch=arm64 target=template_debug
   ```
5. Godot: `Godot --headless --path game --import`, dann `Godot --path game` zum Starten oder
   `Godot --headless --path game --export-debug Android ../build/pocketra.apk`.

Dieser Stand ist eine automatisch erzeugte, kommentarfreie Veröffentlichungskopie (`tools/publish.py`).
