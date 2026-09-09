## Lizenz und Herkunft

Der Code in diesem Repository steht unter der GNU General Public License v3.0
(Volltext in [`LICENSE`](LICENSE)). Die Spielregeln und die Missionslogik sind von
[OpenRA](https://github.com/OpenRA/OpenRA) (ebenfalls GPLv3) abgeleitet bzw. eng
daran angelehnt; Abweichungen sind im Code kommentiert. Die Original-Grafiken, -Sounds
und -Videos gehören Westwood Studios/Electronic Arts und liegen diesem Repository
nicht bei — wer selbst bauen will, bezieht sie über das EA-Freeware-Paket
(`ra-quickinstall.zip`, siehe Abschnitt „Setup" unten). Dieser Kommentar-freie Stand
ist eine automatisch erzeugte Veröffentlichungskopie (`tools/publish.py`).

---

# PocketRA

Ein eigenständiges Echtzeit-Strategiespiel für Android in der Bauart der 90er — eigene Engine,
eigenes für Touch entworfenes Bedienkonzept, Spiellogik nach [OpenRA](https://github.com/OpenRA/OpenRA).
Die Grafik-, Ton- und Missionsdaten bringt PocketRA **nicht** mit: der Spieler lädt sie im Spiel aus
seiner eigenen *Command & Conquer: Red Alert*-Ausgabe bzw. dem 2008 von Electronic Arts
freigegebenen Freeware-Paket (siehe „Rechtliches“ am Ende dieser Datei).

**Status:** Bewegung, Kampf und Wirtschaft laufen nach OpenRA-Regeln in der C++-Sim auf dem Handy; Ton, Stimmen und Musik sind drin. Als Nächstes: Bauen.

---

## Warum neu bauen statt portieren

[OpenRA](https://github.com/OpenRA/OpenRA) ist die naheliegende Basis, lässt sich aber nicht sinnvoll
nach Android bringen: Desktop-OpenGL über SDL2, eine komplett auf Maus und Tastatur ausgelegte
Bedienung, und ein Trait-System mit 571 Klassen, das zu tief in der eigenen Engine sitzt, um es
herauszulösen. Offizielle Anfragen nach einem Android-Port wurden zuletzt 2025 als *not planned*
geschlossen.

Wiederverwendet werden deshalb **Assets und Daten**, nicht der Code:

- Sprites, Terrain-Kacheln und Sounds aus den originalen MIX-Archiven
- Balance-Daten aus `rules.ini` — der kanonischen Quelle, die selbst in EAs Source-Release fehlt
- Sprite-Sequence-Definitionen aus OpenRA, weil die Zuordnung von Frames zu Animationen und
  Blickrichtungen sonst nirgends dokumentiert ist

---

## Technische Entscheidungen

| Bereich | Entscheidung |
|---|---|
| Engine | Godot 4.7.2 |
| Simulation | C++ via GDExtension — deterministisch, Ganzzahl-Mathematik, 25 Ticks/s |
| Präsentation | GDScript — UI, Touch-Input, Kamera, Audio |
| **Kein C#** | Godots C#-Android-Export ist seit 4.2 **experimentell** und ist es in 4.7 noch |
| Rendering | Palettenindizierte R8-Texturen, Palettenlookup im Fragment-Shader, `MultiMesh`-Batching |
| Steuerung | Ein Finger = Einheiten, zwei Finger = Kamera. Langes Drücken = Radialmenü (auf eigenen/verbündeten Zielen mit „Zwangsangriff") |
| Pathfinding | Flow Fields pro Gruppenbefehl statt A* pro Einheit |

Begründungen in [`docs/ARCHITEKTUR.md`](docs/ARCHITEKTUR.md).

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [`docs/ARCHITEKTUR.md`](docs/ARCHITEKTUR.md) | Systemaufbau, Verzeichnisstruktur, Aufbaureihenfolge |
| [`docs/research/01-openra-assets-und-daten.md`](docs/research/01-openra-assets-und-daten.md) | Binärformate, MiniYAML, Trait-System, Extraktionspipeline, Lizenzlage |
| [`docs/research/02-engine-entscheidung.md`](docs/research/02-engine-entscheidung.md) | Engine-Vergleich, warum kein C#, Toolchain-Abgleich |
| [`docs/research/03-touch-steuerung.md`](docs/research/03-touch-steuerung.md) | Gestenvokabular, Bauplatzierung, Zoomstufen, Bildschirmaufteilung |

---

## Stand und nächste Schritte

Die Aufbaureihenfolge ist so sortiert, dass die riskantesten Annahmen zuerst geprüft werden
(siehe [Architektur, §6](docs/ARCHITEKTUR.md)):

- [x] Godot 4.7.2 + JDK 17 installiert
- [x] **2 — Asset-Pipeline:** MIX → SHP → R8-Atlas → Palettenshader zeigt Einheiten mit Teamfarben (auf dem Mac)
- [x] **0a — iOS/iPadOS-Export:** signierte `.ipa` (arm64), am 2026-09-04 aufs iPad (10. Generation)
  aufgespielt und gestartet. Die C++-Sim liegt dort als statisches `.xcframework` in der App, nicht als
  nachgeladene Bibliothek (s. „iOS/iPadOS bauen und aufspielen").
- [x] **0 — Android-Export:** APK (arm64) läuft auf dem Sony Xperia 5 V mit Vulkan/Adreno 740, 60 FPS.
  (Im Emulator nur mit OpenGL-Renderer — sein Software-Vulkan kann nicht präsentieren, das ist ein Emulator-Problem.)
- [x] **3 — Gestenprototyp:** Steuerungskonzept am Gerät validiert — ein Finger Einheiten, zwei Finger Kamera,
  Radialmenü, Rahmenauswahl, Minimap. Urteil: „Alles ist perfekt bisher." Details in Recherche 03, §11a.
- [x] **1 — GDExtension:** C++-Extension (`sim/` + `gdext/`) für macOS und Android arm64 gebaut, auf dem Gerät geladen:
  `RaSim geladen: v0.1.0 Zelle=1024 25 Ticks/s`. Die Simulation tickt in C++ mit 25 Hz neben der GDScript-Präsentation.

**Damit sind alle vier Risikomeilensteine (0–3) abgeschlossen.**

- [x] **4 — Simulationskern:** Karte, Actors, Flow Fields pro Gruppenbefehl, zellenbasierte Bewegung mit
  Belegung nach OpenRAs `Move.cs` (nearEnough 8, WaitAverage 40±10, Nudge-Kette, lokale Umplanung, Überholen),
  3×3-Teilziele gegen Kolonnenbildung, Snapshot-Interpolation, MultiMesh-Puffer direkt aus C++.
  **Gemessen auf dem Xperia 5 V: 300 Einheiten, 29–141 µs pro Sim-Tick, 59 FPS.** Budget wären 40 000 µs.

- [x] **5 — Kampf:** Waffen, Sprengköpfe und Panzerung 1:1 aus `mods/ra/weapons` und `rules`
  (`90mm`, `25mm`, `M1Carbine`, `M60mg`; `SpreadDamage` mit Falloff und Versus), Zielerfassung nach `AutoTarget`
  (Stance Defend, Scan alle 3–8 Ticks), Angriffsbefehl nach `AttackFollow`, Angriffsbewegung, Türme, Projektile
  (`Bullet`/`InstantHit`), Sterbeanimationen je Schadensart, Explosionen nach `sequences/misc.yaml`, Lebensbalken.
  Audio: Waffen, Einschläge, Stimmen, EVA, Musik (Lautstärke nach Sichtbarkeit, Deckel gegen Überlagerung).

- [x] **6 — Wirtschaft:** Erzfelder (`ResourceLayer`, Dichte 1–12), Harvester-Automat nach
  `FindAndDeliverResources` (Suche 8/15 Zellen, 20 Ballen, 25 Credits/Ballen), Raffinerie mit Andockwinkel,
  Ladepips, Ernte-Befehl per Tippen auf Erz, Credits-Ticken.

- [x] **7 — Bauen:** `ClassicProductionQueue`/`ProductionItem` (Bauzeit Cost×60 %, progressive Bezahlung,
  LowPowerModifier), Voraussetzungen/Provides, Strom, Platzierung nach `RequiresBuildableArea` +
  `GivesBuildableArea` + `BaseProvider` (nur wo `Building.RequiresBaseProvider` gesetzt ist — Mauern
  und Zäune brauchen keinen Bauhof in der Nähe und dürfen bei uns überall im Baubereich stehen),
  Bauanimationen, Fabrik-Ausgang + Sammelpunkt, Raffinerie bringt Harvester mit (`FreeActor`). Bauleiste mit
  Original-Cameos; Platzieren: Icon tippen, Karte tippen, gleicher Punkt nochmal = bauen. Start nur mit Bauhof.

- [x] **8 — HUD:** Statusleiste (Credits, Strombalken), Kontrollgruppen-Spalte, Gebäudeauswahl mit Sammelpunkt
  (`RallyPoint`), Verkaufen mit Bestätigung (`Sellable`), Reparieren (`RepairableBuilding`), Primärgebäude
  (`PrimaryBuilding`); Bauleiste springt auf die Queue des gewählten Gebäudes. Radar-Optik und Porträts offen.
- [x] **9 — Gegner-KI:** OpenRAs ModularBot nachgebaut (`sim/src/ai/bot.cpp`): Basisbau nach
  `BaseBuilderBotModule` (Strom-Override, Raffinerie-Soll, BuildingFractions/Limits, Platzierung im Ring um
  den Bauhof), Einheitenbau nach `UnitBuilderBotModule` (UnitsToBuild-Anteile), Harvester-Nachschub, Squads
  nach `SquadManagerBotModule` (Reserve → Angriffstrupp, Rush, Schutz der Basis, Idle/AttackMove/Attack/Flee
  mit den AttackOrFlee-Regeln). Parameter aus `ai.yaml` je Bot-Typ. Beide Seiten starten nur mit Bauhof.
  **KI-Stärke** im Gefecht-Menü (leicht/mittel/schwer): OpenRA kennt statt Stufen die Bot-Typen
  `ModularBot@RushAI/NormalAI/TurtleAI` — schwer nimmt die Rush-Parameter + 10 % `Player.Handicap`,
  mittel die Normal-Parameter + 25 % Handicap, leicht ebenfalls die Normal-Parameter mit 50 % Handicap
  (`^PlayerHandicaps`: 50 % Feuerkraft, 50 % Trefferpunkte, 150 % Bauzeit), doppelter Truppgröße und
  abgeschaltetem Rush. Alle drei Stufen bekommen ein Handicap, weil die KI keinen Bau- oder
  Preisbonus hat (Bauzeitformel für Bot und Spieler identisch) und ohne Handicap zu früh und zu stark
  angreift (Toms Handtest 2026-09-04, docs/ARCHITEKTUR.md §3a).

- [x] **10 — Skirmish komplett:** Sieg/Niederlage nach `ConquestVictoryConditions` (ShortGame: ohne Gebäude
  verloren) mit Anzeige und Neustart; Verteidigungs-Queue mit Pillbox (`Vulcan`) und Geschützturm
  (`TurretGun`), die KI baut sie Richtung Gegner; Service Depot (`RepairsUnits` 1000 HP je 7 Ticks für 20 %
  des Wertes, Fahrzeug antippen → Depot antippen); 2TNK braucht wie in OpenRA `fix`.

- [x] **11 — Echte Karten:** OpenRAs `.oramap`-Karten (map.bin/map.yaml) und Tilesets temperat/snow
  (`tools/mapconvert.py`, `tools/tileset2atlas.py`, MiniYAML-Parser mit Vererbung in `tools/rafmt/miniyaml.py`);
  Terraintypen mit Locomotor-Geschwindigkeiten (foot/wheeled/tracked) und Wegekosten, Bounds, Rohstoffe
  (Erz/Edelsteine mit RecalculateResourceDensity), Bäume/Minen/Zivilgebäude/Wände als neutrale Actors,
  Spawnpunkte für Spieler und KI. Standardkarte „Keep off the Grass 2".

- [x] **12 — Menü:** Hauptmenü (Gefecht, Missionen, Optionen, Beenden), Gefecht-Setup mit Kartenliste,
  Vorschau, KI-Gegner und Startgeld (gespeichert in `user://settings.cfg`), Missionsliste (Kampagnenkarten,
  Skripte folgen), Spielmenü ≡ mit Pause, Neustart, Aufgeben.

- [x] **13 — Fraktionen aus den Originalregeln:** `tools/rules2json.py` liest OpenRAs rules/weapons/sequences/
  audio/fluent → `assets/rules.json`; `RulesDb` baut daraus alle Typen (235 Actors: Alliierte und Sowjets,
  Infanterie, Fahrzeuge, Gebäude, Verteidigung, Wände, Dekorationen), 77 Waffen mit Sprengköpfen, Effekte,
  Stimmen mit Fraktionsvarianten, KI-Anteile aus ai.yaml. Sim: sechs Schadensarten mit Todesanimationen,
  fraktionsabhängige Voraussetzungen (structures.allies/soviet), MCV-Ausklappen (Transforms), Skirmish-Start
  „MCV only", KI klappt ihr MCV selbst aus. Fraktionswahl im Menü. Nicht unterstützt: Schiffe,
  Superwaffen, Tarnung, Minenleger.

- [x] **14 — Shroud &amp; Fog of War:** Sichtweiten aus `RevealsShroud`, Sichtbarkeit je Spieler in der Sim
  (unerkundet/erkundet/sichtbar, alle 5 Ticks), Gegner-Einheiten nur im Sichtbereich, Gebäude ab Erkundung
  (wie FrozenActors), Nebel-Overlay mit weichen Kanten, Minimap mit Shroud.

- [x] **15 — Missionen:** Skript-Laufzeit `MissionApi` nach OpenRAs Lua-API (Trigger OnKilled/OnAllKilled/
  OnAnyKilled/OnDamaged/OnIdle/OnEnteredFootprint/Proximity/AfterDelay/OnTimerExpired, Reinforcements.Reinforce,
  Player.Build/HasNoRequiredUnits/Objectives, Actor Move/AttackMove/Hunt/Kill, Media, UserInterface, DateTime);
  Kampagnenkarten mit Spielerzuordnung, Kartenfarben, Allianzen, NonCombatant, Briefing aus map.ftl, Zieltexte
  aus fluent/lua.ftl, Timer und Zielliste im HUD. Übertragene Missionen: Allies 02 „Five to One", Soviet 01
  „Lesson in Blood" (ohne Yaks; Fallschirmspringer laufen vom Kartenrand), Allies 13 „Focused Blast" (Innenraum-Tileset,
  Kameras als Aufdeckung, Patrouillen, Sprengladungen per Pionier), Soviet 04a „Behind the Lines" (Skript-KI
  baut Basis nach, Patrouillen, Verstärkungen), Allies 10b „Suspicion" (Pioniere an Konsolen, Tanya, Timer).
  Kampagnenfortschritt in `user://progress.cfg`, „Nächste Mission" nach dem Sieg.
  Tilesets: temperat, snow, interior (desert fehlen Kacheln im Freeware-Paket).

- [x] **16 — Feinschliff:** Wandanschlüsse (`WithWallSpriteBody`, 16 Frames nach Nachbarn), Pioniere erobern
  Gebäude (`Captures`/`Capturable`, CaptureDelay 200 Ticks, Pionier tippen → feindliches Gebäude tippen),
  Gefecht mit bis zu drei KI-Gegnern (wechselnde Fraktionen), Spielerfarben für acht Spieler, Starteinheiten
  nach OpenRA `StartingUnits` (nur MCV / leichte / schwere Unterstützung), Edelsteine 50 je Ballen,
  Lagerkapazität nach `StoresPlayerResources` (Raffinerie 2000, Silo 3000; Rohstoffe vor Bargeld ausgegeben,
  „Silos needed" bei vollem Lager), UI-Klicksound. HUD und Menü nach Toms Designvorlage (goldgerahmte
  Panels, Bauleiste als Kartenraster, Menübilder mit Nano Banana Pro erzeugt: `game/assets/ui/`).

- [x] **17 — Luftfahrt & Transport:** Transporter nach `Cargo`/`Passenger` (Einheit wählen, Transporter
  antippen → einsteigen; Radialmenü „Entladen"; Passagiere sterben mit dem Wrack), Flugzeuge nach
  `Aircraft`/`AttackAircraft`/`AmmoPool` (eigene Höhenachse ohne Zellbelegung, Schatten und Rotor,
  Starten/Landen, Nachladen am Flugfeld, Schwebe- und Überflugangriff, Abschuss), Bau-Queue
  „Flugzeuge" an `hpad`/`afld`, Flugabwehr wieder scharf (`agun`, `sam`, und `ftrk`/`e3` mit zweitem
  Armament), Fallschirme nach `ParaDrop`/`Parachutable` samt
  `Reinforcements.ReinforceWithTransport` in der Missions-API — die Ersatzlösungen in soviet-01/02a/02b
  und allies-03a/03b/04 sind zurückgebaut.
- [x] **18 — Speichern und Laden:** Vollständiger Zustandsabzug der Sim (`World::save/load`,
  `sim/src/world/save.cpp`: Karte, Actors mit allen Komponenten, Projektile, Spieler, KI, Sicht, Tick, RNG)
  mit Magic, Version und Regel-Fingerabdruck. Spielstand als `user://saves/<slot>.ras`: JSON-Kopf
  (Karte, Modus, Gefechtseinstellungen, Seed, Zeitstempel, Spielzeit), zstd-gepackte Sim-Bytes und der
  Godot-Zustand (Kamera, Zoom, Auswahl, Kontrollgruppen). Fünf Handslots und drei rotierende Autosaves
  (alle drei Minuten Spielzeit sowie beim Verlassen, Beenden und wenn Android die App pausiert).
  Pausenmenü „Speichern"/„Laden", Hauptmenü „Weiter"/„Laden". Missionen sichern nur den Neustartpunkt
  (docs/ARCHITEKTUR.md §3a).

**Lebende Projektdoku:** [`project-docs/index.html`](project-docs/index.html) (Status, File Map, Entscheidungen, Wishlist).

**Spiellogik folgt OpenRA.** Referenz ist der Fork [tarek369/OpenRA](https://github.com/tarek369/OpenRA)
(lokal unter `reference/OpenRA`, nicht eingecheckt). Abweichungen sind im Code als solche kommentiert.

### Pipeline benutzen

```bash
python3 tools/mixextract.py list                          # alle Archive und Auflösungsstand
python3 tools/mixextract.py find 2tnk.shp rules.ini       # in welchem MIX liegt was
python3 tools/mixextract.py extract -o out rules.ini      # Rohdateien herausziehen
python3 tools/shp2png.py 2tnk.shp --cols 8                # Sprite als PNG-Sheet ansehen
python3 tools/radar2png.py                               # Radar-Aus-Bild (natoradr/ussrradr) → game/assets/ui/radar_*.png
python3 tools/shp2rgba.py allyrepair.shp -o game/assets/ui/repair_wrench.png   # Reparatur-Schraubenschlüssel (OpenRA bits/)
python3 tools/buttons2icons.py                             # Toms Nano-Banana-Pro-Knopfentwürfe (design/app/buttons/*.png)
                                                             # → game/icons/ui/btn_*.png, 192×192 Lanczos (Pillow, sonst ffmpeg-full)
python3 tools/shp2atlas.py vehicles 2tnk.shp 1tnk.shp harv.shp jeep.shp   # → game/assets/atlas/
# Die Atlanten des Spiels (nach jeder Sprite-Ergänzung neu bauen, dann Godot --import):
python3 tools/shp2atlas.py proto_units 2tnk.shp 1tnk.shp jeep.shp harv.shp e1.shp 120mm.shp 50cal.shp piff.shp piffpiff.shp veh-hit3.shp veh-hit2.shp art-exp1.shp fball1.shp proc.shp procmake.shp fact.shp factmake.shp powr.shp powrmake.shp tent.shp tentmake.shp weap.shp weapmake.shp weap2.shp facticon.shp powricon.shp tenticon.shp weapicon.shp procicon.shp 2tnkicon.shp 1tnkicon.shp jeepicon.shp harvicon.shp e1icon.shp flagfly.shp tabs.shp powerbar.shp power.shp pbox.shp pboxmake.shp gun.shp gunmake.shp fix.shp fixmake.shp pboxicon.shp gunicon.shp fixicon.shp
python3 tools/shp2atlas.py proto_terrain clear1.tem w1.tem gold01.tem gold02.tem gold03.tem gold04.tem bib1.tem bib2.tem bib3.tem
# Seit Meilenstein 11 benutzt das Spiel je Tileset einen Gesamt-Atlas (Kacheln + Dekorationen + Einheiten aus
# tools/unit_sprites.txt) und OpenRAs Karten aus reference/OpenRA/mods/ra/maps:
python3 tools/png2cameo.py design/app/volkov/volkov_3.png volkicon.shp   # Volkovs Cameo (Toms Entwurf) → reference/OpenRA/mods/ra/bits
                                                             # und game/data/bits (gen_volkicon.py ist nur noch der Rückfall)
                                                             # (gitignored, vor jedem frischen reference/OpenRA-Checkout neu ausführen)
python3 tools/tileset2atlas.py temperat && python3 tools/tileset2atlas.py snow && python3 tools/tileset2atlas.py interior
python3 tools/rules2json.py                                # Regeln → game/assets/rules.json + tools/unit_sprites.txt (vor tileset2atlas!)
python3 tools/mapconvert.py                                # alle 142 Karten (OpenRA + tools/maps_extra/) → game/assets/maps/ (immer zusammen mit rules2json!)
# mapconvert.py übersetzt die kartenlokalen `Rules:` mit rules2json.extract_actor. Ein Actor im
# Karten-Delta ersetzt den globalen Eintrag vollständig — kommt in rules2json.py ein Feld dazu,
# müssen deshalb **beide** Läufe neu; sonst fehlt es allen Karten (game/assets/ liegt nicht im Git).
# Beide Ausgaben tragen dafür denselben Stempel `rules_format`; RulesDb warnt, wenn er auseinanderläuft.
python3 tools/audconvert.py $(cat tools/sounds.txt) -o game/assets/sfx   # alle Sounds/Stimmen aus den Regeln
                                                             # (sucht auch in reference/OpenRA/mods/ra/bits)
python3 tools/vqa2ogv.py                                     # Startintro (redintro + prolog)
python3 tools/vqa2ogv.py --missions --quality 5              # alle Missionsfilme beider CDs (80 Stück, ~70 MB)
python3 tools/audconvert.py cannon1.aud gun11.aud await1.v01              # AUD/Stimmen → game/assets/sfx/*.wav
python3 tools/audconvert.py --music intro.aud map.aud -o game/assets/music # Musik → MP3
python3 tools/cameo_de_labels.py --preview design/cameos/_uebersicht.png  # deutsche Cameos der
                                                             # Erweiterung nachbauen (Original-Bild +
                                                             # Cameo-Schrift von der CD) → build/cameos_de
python3 tools/cameos2atlas.py                                # deutsch beschriftete Cameos von der
                                                             # deutschen CD + build/cameos_de → atlas_cameos_de + Rezept
/Applications/Godot.app/Contents/MacOS/Godot --path game  # Testszene starten
```

### Inhalte auf dem Gerät (ohne EA-Dateien in der APK)

Die Verteil-APK enthält keine EA-Inhalte. Der Nutzer lädt im Spiel das Freeware-Paket und legt
optional CD-Abbilder bereit; ausgewertet wird alles auf dem Gerät durch die Extension-Klasse
`RaContent` (`gdext/src/content/`): MIX auspacken (auch Blowfish-verschlüsselt und verschachtelt),
ISO-Abbilder lesen, Atlanten und Sounds bauen, Musik und Filme direkt aus den Archiven abspielen.

In der APK liegen dafür nur eigene und GPL-Daten (`game/data/`, zusammen 1,6 MB):

```
game/data/atlas/*.recipe   Atlas-Rezepte (Sprite-Liste in Packreihenfolge + Metadaten aus OpenRA)
game/data/bits/*.shp       OpenRAs eigene Sprites (GPL), 185 Dateien
game/data/bits/volkicon.plate  Hintergrundplatte für Volkovs Cameo (Eigenarbeit)
game/data/mix_names.dat    XCC-Namensverzeichnis (MIX speichert nur Hashes)
game/data/sounds.txt       Liste der zu wandelnden Sounds
```

Neu erzeugen, wenn sich Sprites oder Regeln ändern (die Rezepte gehören zu den Atlanten):

```bash
python3 tools/tileset2atlas.py temperat --recipe game/data/atlas    # … snow, interior ebenso
python3 tools/cameo_de_labels.py && python3 tools/cameos2atlas.py   # deutsche Cameos + Rezept
cp tools/sounds.txt game/data/sounds.txt
```

Prüfen (beides ohne Gerät):

```bash
gdext/tests/run.sh          # C++-Leser Byte für Byte gegen tools/rafmt und ffmpeg
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --test-content
```

Der zweite Lauf baut alle Atlanten und Sounds nach `user://content`, schreibt das Manifest, misst
die Zeiten und spielt zwei Sekunden Film und Musik an. Am Mac (M4 Pro): Archive öffnen 13–23 ms,
drei Atlanten 115–172 ms, deutsche Cameos 1–3 ms, 310 Sounds 35–40 ms, 282 deutsche Sounds 44 ms.

Zur Laufzeit entscheidet `game/scripts/content/content_paths.gd`, woher die Daten kommen: erst
`user://content`, sonst `res://assets` — die Entwicklung am Mac bleibt damit unverändert.

#### Deutsche Sprachausgabe von der deutschen CD

Wo die deutschen Stimmen stecken (nachgesehen mit `python3 tools/mixextract.py --content content/ra_de list …`):

| Archiv | Weg | Clips aus `game/data/sounds.txt` | Was |
|---|---|---|---|
| `sounds.mix` | in `MAIN.MIX` | 106 | Infanterie- und Sonderrufe (`eyessir1`, `myessir1`, `syessir1`, `dedman*`) und Effekte |
| `allies.mix` | in `MAIN.MIX` | 34 | Bestätigungen der Alliierten (`ackno.v00`–`.v03`, `await1`, `yessir1`, `report1` …) |
| `russian.mix` | in `MAIN.MIX` | 34 | dieselben Rufe der Sowjets (`.r00`–`.r03`) |
| `speech.mix` | in `INSTALL/REDALERT.MIX` | 107 | EVA-Ansagen (`conscmp1`, `unitrdy1`, `baseatk1` …) |

Zusammen 281 Clips, davon vier auf der deutschen CD **leere Hüllen** à 84 Byte (`girlokay`,
`girlyeah`, `guyokay1`, `guyyeah1` — die Zivilistenrufe sind in der deutschen Fassung
herausgenommen). Sie stehen in `ContentManager.LANG_STUBS` und bleiben englisch, sonst wären sie im
Spiel stumm: die Sprachfassung hat in `ContentPaths.sfx()` Vorrang. Bleiben **277**.

Die Kette auf dem Gerät: `ContentPage._bg_cd_import` liest die Archive aus der ISO, löscht MAIN.MIX
und ruft danach `ContentManager.build_language_sounds("de")` — `RaContent.convert_sounds(…, lang:
"de")` schreibt nach `user://content/sfx/de/`. Beim Abspielen wählt `ContentPaths.sfx()` erst die
Sprachfassung, dann die Grundfassung; fehlt ein Clip auf Deutsch, spielt er englisch weiter.
Reihenfolge-unabhängig ist das von selbst: das Freeware-Paket schreibt nur nach `sfx/`, die CD nur
nach `sfx/de/`.

Wer die deutsche CD **vor** dieser Änderung eingespielt hat, hat `sfx/de/` gar nicht — die
Einrichtungsseite zeigt dann „Sprachausgabe: Englisch — die deutschen Stimmen sind noch nicht aus
der CD ausgelesen" und den Knopf **„Deutsche Stimmen auslesen"**: ein Lauf über die schon behaltenen
Archive, ohne Download und ohne Atlasbau. Weil `allies.mix`/`russian.mix` damals nicht behalten
wurden, kommen dabei 209 statt 277 Clips zusammen; die Seite sagt das im Klartext und nennt den
Ausweg (deutsche CD einmal löschen und neu einlesen). Geprüft mit `--test-content-lang`.

#### Was die Seite erklärt

Beim Erststart steht der Nutzer sonst vor Download-Knöpfen ohne Begründung. Die Seite sagt deshalb in
kurzen Absätzen, jeweils in der Karte des betreffenden Abschnitts:

* **Warum** — die App enthält nur eigenen Code; Grafiken, Sounds, Filme und Musik von Westwood/
  Electronic Arts sind urheberrechtlich geschützt und dürfen nicht mitgeliefert werden. Alles
  Geladene bleibt nur auf dem Gerät, die App lädt nichts hoch und gibt nichts weiter, und unter
  „Optionen → Spielinhalte" ist alles wieder löschbar.
* **Freeware-Paket (Pflicht)** — was drin ist (Einheiten, Gebäude, Gelände, Karten, Regeln, Sounds)
  und woher es kommt (2008 von Electronic Arts kostenlos freigegeben, Community-Spiegel
  openra.ppmsite.com, derselbe wie bei OpenRA).
* **CD-Inhalte (optional)** — was jede CD bringt (Missionsfilme der Alliierten bzw. Sowjets samt
  Original-Musik, die deutsche CD zusätzlich Sprachausgabe und Beschriftungen), woher die Abbilder
  kommen (Internet-Archiv, archive.org — die App lädt nur herunter und gibt nichts weiter), dass nur
  die nötigen Archivdateien ausgelesen werden und das Abbild danach sofort gelöscht wird.
* **Eigene CD oder eigenes Abbild** — schon vorhandene Dateien lassen sich ohne Download auslesen,
  die Datei des Nutzers bleibt unverändert liegen.

#### Haftungsausschluss vor dem ersten Download

Vor dem **ersten** Download erscheint ein Hinweisfenster im Rahmenstil (`ContentPage._show_disclaimer`,
Texte `content.disclaimer_*` de/en). In sechs kurzen Sätzen, ohne Juristendeutsch: die App enthält
keine Spieldaten von Westwood oder Electronic Arts; sie lädt sie auf Wunsch des Nutzers von Dritten
(Freeware-Paket vom Community-Spiegel openra.ppmsite.com, von EA 2008 freigegeben; CD-Abbilder aus
dem Internet-Archiv archive.org); der Nutzer ist selbst dafür verantwortlich, dass er die Inhalte
nutzen darf (z. B. weil ihm die Original-CDs gehören); die Autoren stellen die Inhalte nicht bereit
und übernehmen keine Haftung; heruntergeladene Abbilder werden nach dem Auslesen sofort gelöscht;
die Rechte an Alarmstufe Rot liegen bei Electronic Arts.

„Ich habe verstanden und stimme zu" wird **einmal** in `user://settings.cfg` (`[content]
disclaimer_accepted`) gemerkt — die Zustimmung gilt für die App und überlebt „Spielinhalte löschen".
„Abbrechen" lädt nichts. Nachzulesen ist der Text jederzeit über „Optionen → Spielinhalte → Hinweis
noch einmal lesen"; eine Kurzfassung (`content.disclaimer_short`) steht dauerhaft in der Karte
„Warum Du etwas herunterladen musst". Geprüft mit `--test-content-disclaimer`; `--test-content-fit`
misst das Fenster in allen sechs Profilen mit.

Alle Texte liegen als `content.*`-Schlüssel de/en in `game/i18n/strings.csv` (einzeilig — Godots
CSV-Import verträgt zwar mehrzeilige Felder, aber zeilenweise Werkzeuge nicht; mehrere Absätze
stehen deshalb in getrennten Schlüsseln, z. B. `content.why` und `content.why2`).

#### Lesbarkeit und Rollen

Der ganze Inhalt (Erklärtexte, Karten, Knöpfe) liegt in einem `ScrollContainer`; die senkrechte
Rollleiste ist eigens breiter und in Gold gesetzt, damit sichtbar ist, dass es weitergeht.

**Fingerzug über Text, Karte und Knopf** (Toms Handtest 2026-09-06): Godot gibt einen Fingerzug nur
an den obersten Control unter dem Finger und bricht die Weitergabe an die Eltern ab, sobald einer
davon `MOUSE_FILTER_STOP` trägt — voreingestellt sind das `PanelContainer` (also jede Karte) und
jeder `Button`. Gerollt werden konnte deshalb nur auf freien Flächen. `HudTheme.touch_scroll(scroll)`
setzt alles im Rollbereich auf `MOUSE_FILTER_PASS`: der Knopf bekommt den Tipp weiterhin, der Zug
läuft zusätzlich bis zur Rollfläche durch, und wird aus dem Tipp ein Zug, schickt Godots
ScrollContainer den Kindern von sich aus einen Abbruch (kein versehentlicher Knopfdruck).
Ausgenommen bleiben Schieberegler, Texteingaben und verschachtelte Rollflächen — deren Zug gehört
ihnen. Angewandt auf diese Seite, die Optionen und die Protokolltafel; gemessen mit
`--test-touch-scroll`. Die Fußzeile (Protokoll/Zurück/Weiter) steht
außerhalb der Rollfläche und ist immer zu sehen. Schriftgrößen haben eine Untergrenze in **echten
Geräte-dp** (10 dp): `Dp.px()` schrumpft auf schmalen Handys um bis zu 0,8, ein 11-dp-Text wäre am
Xperia nur noch 8,8 echte dp groß. Wird die Seite dadurch höher als der Bildschirm, rollt sie — das
ist der gewollte Ausweg, nicht kleinere Schrift. Geprüft wird das mit `--test-content-fit`.

#### Warteschlange und Speicherplatz

Die Seite „Spielinhalte einrichten" arbeitet Downloads **nacheinander** ab, reiht sie aber sofort
ein: Jeder Tipp auf einen Download-Knopf hängt einen Auftrag an, die Kopfzeile meldet „Auftrag 2 von
3", eingereihte Zeilen zeigen „In Warteschlange", und „Abbrechen" verwirft die ganze Warteschlange.
Echte Parallelität bringt bei einer Leitung nichts und würde beide Downloads verlangsamen — die
Bedienung blockiert trotzdem nie (Toms Handtest 2026-09-05).

Ein **heruntergeladenes** Abbild wird direkt nach `iso_extract` gelöscht (noch vor dem Auspacken von
MAIN.MIX, damit der Höchststand an belegtem Speicher klein bleibt), auch wenn das Auslesen scheitert;
`MAIN.MIX` selbst danach ebenso. Eine vom Nutzer **gewählte** Datei bleibt liegen — außer sie liegt im
Datenordner der App, ist also eine von uns angelegte Kopie. Vor jedem ISO-Auftrag prüft die Seite den
freien Speicher (mindestens 1,5 GB): `RaContent.free_space()` benutzt POSIX `statvfs` und läuft damit
auch auf Android und iOS, wo `OS.execute("df", …)` nicht zur Verfügung steht; nur wenn die Extension
fehlt, wird auf Desktop-Systemen `df -k` versucht. Ist beides nicht möglich, erscheint statt einer
Sperre der Hinweis „Freier Speicher lässt sich auf diesem Gerät nicht prüfen".

#### iOS: ISO ohne Dateiauswahl

`DisplayServer.file_dialog_show()` gibt es auf iOS nicht. Dort (und überall, wo
`DisplayServer.FEATURE_NATIVE_DIALOG_FILE` fehlt) zeigt die Karte „ISO- oder MIX-Datei wählen"
stattdessen den Ordnerweg plus einen Knopf **„Ordner prüfen"**: Der Nutzer legt die ISO mit der
Dateien-App in den Ordner `original/` im Dokumente-Ordner der App, tippt auf „Ordner prüfen", und die
Seite bietet jede gefundene `*.iso`/`*.mix` als eigenen Knopf an. Nichts wird kopiert oder
verschoben, die Datei des Nutzers bleibt liegen. Damit der Ordner in der Dateien-App überhaupt
auftaucht, braucht ein iOS-Export in der `Info.plist`

```
UIFileSharingEnabled                 = YES   (Godot-Preset: „Application/Sharing/…", sonst Custom-Plist)
LSSupportsOpeningDocumentsInPlace    = YES
```

Alles andere auf dem iOS-Weg ist plattformunabhängiger Godot-/C++-Code: `HTTPRequest` lädt nach
`user://` (auf iOS der Dokumente-Ordner), `ZIPReader` entpackt, `RaContent` liest ISO und MIX mit
`fopen`/`fread` über `ProjectSettings.globalize_path()`. Kein Unterprozess, kein Android-Aufruf.
Am Mac prüfbar mit `--force-no-file-dialog`; **am Gerät ungeprüft**, solange es kein iOS-Export-Preset
gibt (`game/export_presets.cfg` hat bisher nur Android-Presets).

### Eigene Karten

`reference/OpenRA` ist gitignored (Recherche/README: `git clone --depth 1 …`) — eigene Karten und
Kampagnen dürfen dort also nicht liegen, sonst sind sie nach einem frischen Checkout weg. Stattdessen
versioniert in `tools/maps_extra/`:

```
tools/maps_extra/<slug>/map.yaml, map.bin, rules.yaml, map.ftl, map.png   # ein Kartenordner wie mods/ra/maps/<name>/
tools/maps_extra/campaigns.yaml                                          # zusätzliche Kampagnen im missions.yaml-Format
```

`tools/mapconvert.py` liest zusätzlich zu `reference/OpenRA/mods/ra/maps` diese Kartenordner ein (eine
Extra-Karte überschreibt keine gleichnamige Referenzkarte, sie ergänzt nur) und stellt die Kampagnen aus
`campaigns.yaml` vor die OpenRA-Kampagnen aus `missions.yaml`, sodass sie oben in der Missionsliste
stehen. Beispiel: die Tutorial-Kampagne (`tools/maps_extra/tutorial/`, Kampagne „Tutorial" in
`tools/maps_extra/campaigns.yaml`, Skript `game/scripts/missions/tutorial.gd`). Danach wie gewohnt
`python3 tools/rules2json.py && python3 tools/mapconvert.py` laufen lassen.

### Simulationskern und Datenpipeline ohne Godot testen

```bash
sim/tests/run.sh              # Mathe, Flow Field, Determinismus, 100-Einheiten-Gruppenbewegung, Benchmark
python3 tools/test_pipeline.py  # MiniYAML-Mischsemantik, campaign-rules.yaml, Valued.Cost
```

### GDExtension (C++-Simulationskern) bauen

```bash
git submodule update --init --depth 1          # godot-cpp
brew install scons
cd gdext
scons platform=macos   arch=arm64 target=template_debug -j10
scons platform=android arch=arm64 target=template_debug -j10 \
      ANDROID_HOME=$HOME/Library/Android/sdk ndk_version=28.2.13676358
scons platform=ios     arch=arm64 target=template_debug -j10
brew install mingw-w64                          # Kreuzübersetzer für Windows
scons platform=windows arch=x86_64 target=template_debug use_mingw=yes -j6
```

Ergebnis: `game/bin/librasim.<platform>.{arm64,x86_64}.{dylib,so,dll}` bzw. für iOS
`game/bin/librasim.ios.xcframework` (statisch, s. Abschnitt „iOS/iPadOS bauen und aufspielen"),
registriert über `game/bin/rasim.gdextension`.
Die Godot-API kommt aus `gdext/extension_api.json`, gedumpt aus dem installierten Godot
(`Godot --headless --dump-extension-api --dump-gdextension-interface`) — nach einem Godot-Update neu dumpen.
Nach dem ersten Build einmal `Godot --headless --path game --import` ausführen, damit der Editor die Extension registriert.

### Spiel am Mac starten und prüfen (Testhaken)

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path game --import                 # nach neuen Skripten/Szenen
$G --path game --quit-after 300                    # Startszene, Skriptfehler sichtbar machen

# Gefecht direkt, mit Bildschirmfoto (alles nach `--` geht an das Spiel)
$G --path game --resolution 2560x1096 res://scenes/gesture_proto.tscn --quit-after 6000 -- \
   --dpi 420 --map keep-off-the-grass-2 --ai 1 --screenshot /tmp/shot.png
```

| Haken | Wirkung |
|---|---|
| `--map SLUG` / `--mission SLUG` | Karte bzw. Kampagnenmission laden |
| `--ai N` | Zahl der KI-Gegner |
| `--faction allies\|soviet`, `--ai-faction …` | Fraktionen ohne Umweg über `user://settings.cfg` |
| `--ai-difficulty easy\|normal\|hard` | KI-Stärke (Standard `normal`); leicht = Normal-Bot + 50 % Handicap, doppelte Truppgröße, kein Rush; mittel = Normal-Bot + 25 % Handicap; schwer = Rush-Bot + 10 % Handicap |
| `--starting-units none\|light\|heavy`, `--credits N` | Startklasse und Startgeld |
| `--seed N` | reproduzierbare Spawn-Zuteilung (die Sim selbst ist deterministisch) |
| `--reveal` | Shroud abschalten — sonst ist jedes Foto der Gegnerbasis schwarz |
| `--fog an\|aus`, `--explored-map an\|aus` | die beiden Lobby-Kästchen des Gefechts ohne Umweg über das Menü. `--fog aus` ist **nicht** `--reveal`: der Shroud bleibt, nur der Nebel fällt weg — jede **erkundete** Zelle löst als sichtbar auf, samt der Einheiten darin (OpenRA `Shroud.cs:149`, `HiddenUnderFog.cs:26-29`) |
| `--screenshot PFAD` | Bildschirmfoto und beenden |
| `--screenshot-at TICK` | Zeitpunkt des Fotos (Standard Tick 600) |
| `--dpi N` | mit der Pixeldichte eines Zielgeräts rechnen (Xperia: `--resolution 2560x1096 --dpi 420`) |
| `--diag` | Messzeile (Geste, Auswahl, Zoom, FPS, Sim-Kennzahlen) einblenden |
| `--lang de\|en` | Sprache für diesen Lauf erzwingen (sonst `user://settings.cfg` bzw. `OS.get_locale_language()`) — auch für `main_menu.tscn`-Screenshots |
| `--test-ai [--test-ai-until N]` | KI-Bestand alle 1000 Ticks; endet bei Tick N (Standard 6000), meldet den ersten Angriff auf den Spieler und am Ende Sieg/Niederlage. `--quit-after` (Frames!) groß genug wählen: 9600 Ticks brauchen ≈ 60 000 Frames |
| `--test-ai-audit` | Setzt `--test-ai` voraus (schaltet es selbst ein) und prüft alle 60 Ticks jeden lebenden Actor gegen das Terrain seiner Zelle: Schiffe an Land, Landeinheiten auf Wasser, Wassergebäude (`syrd`/`spen`) an Land und umgekehrt, dazu als HINWEIS (kein Fehler) Schiffe im Bestand eines Spielers ohne eigene Werft — auf einer Karte mit Wasser darf eine Kiste der KI ein Schiff schenken. Zelle und Terrain kommen aus der Sim (`actor_cell`/`cell_terrain`), nicht aus der interpolierten Bildposition — eine laufende Fußtruppe gleitet zwischen ihren Subzellen sichtbar über die Nachbarzelle. Jeder Actor wird nur einmal gemeldet, am Ende steht `AUDIT Ende: N Befund(e), M Hinweis(e)` (Sollwert N = 0). Weil die KI keine Kisten sucht (OpenRA hat dafür kein BotModule) und in 24 000 Ticks auf einer großen Karte **null** Kisten aufnimmt, legt der Haken zusätzlich alle 300 Ticks eine Kiste auf das Ziel einer fahrenden KI-Einheit — erst damit werden die Kistenaktionen oft genug gezogen (gemessen: 107 Aufnahmen je Lauf). Beispiel: `--map ardennes --ai 3 --seed 1 --ai-difficulty hard --starting-units none --test-ai-audit --test-ai-until 24000 --quit-after 250000` |
| `--test-ui [--test-tab 0..3] [--test-scroll] [--test-locked] [--test-orders]` | Basis hinstellen, Bauleiste/Befehlswege prüfen. Reiter 0/1 (Gebäude/Abwehr) brauchen nur den Bauhof; ab Reiter 2 (Infanterie, Fahrzeuge) stellt der Haken zusätzlich Kaserne, Waffenfabrik, Technikzentrum und ein zweites Kraftwerk hin — sonst gibt es die Warteschlange gar nicht und die Leiste fällt still auf „Gebäude" zurück. Für Sowjets kommt ab Reiter 2 auch die Tesla-Spule und ein drittes Kraftwerk dazu, sonst fehlte dem Tesla-Panzer die Voraussetzung `tsla`. Beispiel Volkov-Cameo: `--faction soviet --test-ui --test-tab 2`; Tesla-Panzer im Fahrzeug-Reiter: `--faction soviet --test-ui --test-tab 3 --test-scroll` |
| `--test-ready [zu\|auf\|platziert\|kette]` | „Fertig"-Leuchten (grüner Puls am Kranhaken-Knopf und am betroffenen Bauleisten-Reiter): setzt auf `--test-ui` auf, stellt ein Kraftwerk in die Warteschlange und spult per direktem `sim.step()` bis „fertig" vor. `zu` = Bauleiste zugeklappt (nur der Kranhaken leuchtet, **kein** Platzierungsmodus), `auf` = Leiste offen mit aktivem Reiter „Abwehr" (der Reiter „Gebäude" leuchtet mit), `platziert` = danach gesetzt (beides muss erloschen sein). `kette` spielt Toms ganzen Handtest-Fall mit echten Fingertipps durch (7 Schritte): Leiste zu → keine Platzierung; Tipp auf den Bau-Knopf → Angebot; „Abbrechen" → Gebäude bleibt „Fertig"; Bau-Knopf erneut → zu und still; zweites Gebäude fertig bei zugeklappter Leiste → keine Platzierung; Tipp auf die eigene Produktionsstätte → Leiste geht auf, Platzierung startet **nicht**; erst Zu-/Aufklappen über den Bau-Knopf bietet an |
| `--test-hit` | Tippflächen aller HUD-Knöpfe vermessen (Toms Handtest 2026-09-04, Punkt 3: „Bau-Knopf auf dem iPhone schlecht zu treffen"). Baut sich eine Basis mit Produktion und allen vier Superwaffen, geht dann die drei Geräteprofile Xperia (2560×1096 @ 420 dpi), iPhone (2556×1179 @ 460) und iPad (2360×1640 @ 264) durch und schickt an jeden Knopf synthetische Fingertipps ±2 echte dp innerhalb und außerhalb seiner Tippfläche — über dieselbe Kette wie am Gerät (`InputEventScreenTouch` + `emulate_mouse_from_touch`), die Funktionen selbst sind dabei abgeklemmt. Bericht je Profil: Zahl der Knöpfe, kleinste Tippfläche in echten Geräte-dp (Sollwert 48), Treffer innen/außen. Mit `--diag` zusätzlich eine Zeile je Knopf (Tippfläche und sichtbare Fläche). Erwartet: 0 Fehlschläge |
| `--test-layout` | **HUD und Dialoge in jeder Bildschirmgröße** gegen die sichere Fläche prüfen (`LAYOUT_MATRIX`: sieben Größen von 720×1600 @ 320 dpi bis 2560×1600 @ 320, Xperia hoch und quer dabei). Je Größe die Seiten `hud`, `pause`, `spieler` (die Spielerliste, docs/MULTIPLAYER.md §12), `optionen`, `ziele`, `help`, `info`; gemeldet wird, was aus der sicheren Fläche ragt (`LayoutCheck.violations`), was ein anderes ständiges HUD-Element überlappt (`overlap_violations`) und was auf der HUD-Seite in die Kartenfläche hineinragt (`map_violations`). Am Ende `Layout-Prüfung (Spiel) fertig — N Verstöße` (Sollwert 0). Dieselbe Matrix an `main_menu.tscn` prüft die Menüseiten (`Layout-Prüfung fertig — N Verstöße`). In **beiden** Sprachen laufen lassen (`--lang de` / `--lang en`) |
| `--test-superwaffen` | **Superwaffenleiste** (Toms Handtest 2026-09-09: erst „die sollen übereinander stehen", dann „Ja wann hat man mal 4 Superwaffen … wenn es mehr als 2 sind, dann soll er die anzeigen, die als nächstes fertig ist, und die anderen gruppieren darüber als Anzeige … Bei Klick klappt es sich horizontal auf"). Der Haken stellt acht Kraftwerke hin und baut dann **ein Superwaffengebäude nach dem anderen** (`iron`, `pdox`, `mslo`, `atek`), spult zwischendurch per direktem `sim.step()` vor und misst je Ausbaustufe — ab drei Superwaffen zusätzlich aufgefächert: Zahl der Kacheln (Soll 1 / 2 / 1+„+2" / 1+„+3"), die **senkrechte Flucht** (Musikknopf, Kacheln, Gruppenanzeige und Bau-Knopf müssen dieselbe rechte Kante und dieselbe Kantenlänge haben), dass die Kacheln ohne Überlappung übereinander stehen und die unterste über dem Bau-Knopf endet, die kleinste Tippfläche in echten Geräte-dp (Sollwert 48), Überlappungen mit anderen HUD-Elementen und Eingriffe in die Kartenfläche (je Sollwert 0). Dazu die Probe **Kachelwechsel**: laden bis der Eiserne Vorhang bereitsteht, ihn abfeuern — danach muss die Chronosphäre die Kachel übernehmen. Zum Schluss dieselbe Matrix wie `--test-layout`, einmal zugeklappt und einmal aufgefächert. Mit `--screenshot PFAD` fällt je Fall ein Bild `<pfad>_<fall>.png` ab (`…_stufe1-zu`, `…_stufe3-auf`, `…_kachelwechsel`, `…_2560x1096`, `…_2560x1096_auf` …). Am Ende `--test-superwaffen fertig — N Verstöße` (Sollwert 0). In **beiden** Sprachen laufen lassen. Beispiel: `--map keep-off-the-grass-2 --ai 0 --faction soviet --reveal --starting-units heavy --test-superwaffen` |
| `--test-toasts [--test-toasts-until N]` | **Jede Textüberlagerung mitschreiben** (Toms Rückmeldung 2026-09-05 „Unsinnige Popups im Spiel“): Der Haken spielt einen Spielerdurchlauf — Basis hinstellen, dauerhaft Infanterie und Fahrzeuge produzieren, immer wieder ein Kraftwerk bauen und platzieren, dazwischen Auswahlknöpfe, Verkaufsmodus, Kamerasprünge und Radialbefehle — und protokolliert jede Überlagerung mit Tick, Art (TOAST / MISSIONSMELDUNG / ZIELZEILE / HILFE-POPUP / BAULEISTEN-MENÜ / GESTENHILFE), Standzeit und Text. Am Ende: in wie vielen Bildern ein Textband stand, wie viele Zeilen hoch es im Mittel war, und eine Häufigkeitsliste. `--screenshot PFAD` legt drei Fotos `…_band4/9/14.png` an. Standardende Tick 6000. Beispiel: `--map keep-off-the-grass-2 --seed 1 --ai 1 --test-toasts` |
| `--test-menu pause\|save\|load\|help\|hilfe\|ziele\|radial\|hold\|halt\|win\|erweitern\|verkaufen\|reparieren\|modus-wechsel` | Dialog/Radial/Warteschlange für ein Foto öffnen; `hilfe` öffnet das Langdruck-Hilfe-Popup eines HUD-Knopfs (Verkauf); `erweitern`/`verkaufen`/`reparieren` drücken den Modusknopf und zeigen den farbigen Bildschirmrand (gelb/rot/grün); `modus-wechsel` spielt die Übergänge durch, die den Rand wieder löschen müssen (Knopf erneut tippen, Wechsel zu Verkaufen, „Auswahl aufheben") |
| `--test-eva` | **EVA-Sprachausgabe mitschreiben** (Toms Handtest 2026-09-06: „Building" fehlt beim ersten Bau, „Strom niedrig" kommt viel zu spät). Spielt Bauhof → erster Kraftwerksbau *mitten in die Startansage* → Kaserne → Strommangel durch drei Radarkuppeln direkt nach „Neue Bauoptionen" → leeres Konto, und protokolliert jede Anforderung mit Tick, Ergebnis (`ab` / `doppelt` / `wartet` / `nachgezogen` / `verworfen` / `sperre`) und Kanalbelegung. Sollwerte am Ende: „Building" im Tick des Baubefehls (+≤5 Ticks), „Neue Bauoptionen" nach der Fertigstellung, „Strom niedrig" ≤ 2 s nach dem Kippen der Bilanz. Beispiel: `--map keep-off-the-grass-2 --ai 0 --seed 1 --test-eva` |
| `--test-keys` | **Tastatur am Desktop** (Windows-Fassung, s. o.): schickt echte `InputEventKey` durch die reguläre Kette (`Input.parse_input_event` → Viewport → `_unhandled_input`), nicht durch direkten Funktionsaufruf. Escape muss das Pausenmenü öffnen und wieder schließen, `Strg`+`1` die Auswahl der Gruppe 1 zuweisen und `1` sie zurückholen, `F11` zweimal das Vollbild hin und zurück schalten (unter `--headless` übersprungen). Am Ende `--test-keys Ende: N Fehler` (Sollwert 0). Beispiel: `--map keep-off-the-grass-2 --ai 0 --starting-units light --test-keys` |
| `--test-desktop-scroll` | **Karte schieben am Desktop** (s. o.): Touchpad-Wisch, Mausrad in alle vier Richtungen, `Strg`+Rad und Aufziehen (Zoom um den Zeiger, gemessen wird der Weltpunkt darunter), Randscrollen an allen vier Kanten und beiden Ecken, Tempo, Fensterkante unter der Minimap, Pfeiltasten/WASD, Eingabezeile im Fokus, offenes Pausenmenü und die Kartengrenze. Der Mauszeiger lässt sich in einem Prüflauf nicht stellen — dafür setzt der Haken `Scroller.probe`. Am Ende `--test-desktop-scroll Ende: N Fehler` (Sollwert 0). Mit zusätzlichem `--screenshot PFAD` fallen `…_scroll_vorher.png` / `…_scroll_nachher.png` ab. Beispiel: `--map keep-off-the-grass-2 --ai 0 --starting-units light --test-desktop-scroll` |
| `--test-briefing` | Missionsbriefing offen lassen |
| `--test-mission [--test-force]` | Ziele, Missionstext und Spielende mitschreiben |
| `--test-sell`, `--test-defense`, `--test-buildings` | Regressionsläufe: Verkauf/Neubau, Abwehrgebäude, Gebäude-Overlays |
| `--test-tesla` | Tesla-Spule mit Strom, vier gegnerische Fußtruppen daneben: ein Foto mitten in der Ladeanimation (`<pfad>_laden.png`) und eins im Tick des Blitzes (`--ai 0 --reveal --starting-units heavy`) |
| `--test-ttnk` | Tesla-Panzer (TTNK): sowjetische Basis samt Tesla-Spule und Technikzentrum hinstellen (seine Voraussetzungen `tsla, stek, ~vehicles.russia`), melden, ob er im Fahrzeug-Reiter steht und baubar ist (Foto der Leiste unter `<pfad>_leiste.png`), dann einen hinsetzen und auf vier Fußtruppen und einen schweren Panzer schicken — Foto im Tick des Blitzes. `--ai 0 --faction soviet --reveal --screenshot-at 99999` |
| `--test-nuke` | Silo (`mslo`) mit Strom bauen, Ladung per direktem `sim.step()`-Vorlauf überspringen, abfeuern: ein Foto während des Flugs mit Beacon (HUD) und rotem Minimap-Ping (`<pfad>_flug.png`) und eins beim Einschlag (`<pfad>_einschlag.png`). Stellt zusätzlich Eisernen Vorhang (`iron`), Chronosphäre (`pdox`) und Technikzentrum (`atek`, Satellit) hin, damit alle vier Superwaffenknöpfe gleichzeitig im Bild sind (acht Kraftwerke, sonst reicht der Strom nicht). **Mit `--ai 0`** laufen lassen: der Vorlauf überspringt 13 500 Ticks (neun Spielminuten), in denen eine KI die Basis samt Silo abräumt — dann meldet der Haken „Silo nicht rechtzeitig geladen". Empfohlen: `--ai 0 --faction soviet --reveal --starting-units heavy --screenshot-at 99999` |
| `--test-heal` | Selbstheilung (OpenRA `ChangesHealth` ohne `RequiresCondition`): setzt 4tnk, harv und 3tnk (Gegenprobe ohne den Trait) mit 30 % Trefferpunkten in die Welt und schreibt den Verlauf mit. Erwartet: 4tnk und harv steigen auf genau 50 %, 3tnk bleibt bei 30 %. `--quit-after 40000` |
| `--test-iron` | Eiserner Vorhang: Vorhang-Gerät (`iron`) bauen, Ladung per direktem `sim.step()`-Vorlauf überspringen, auf einen Mammutpanzer auslösen. Zwei Fotos (`<pfad>_vorher.png` ohne, `<pfad>_vorhang.png` mit Wirkung) plus das Unverwundbarkeits-Bit aus `render_state`. `--faction soviet --reveal --screenshot-at 99999` (sonst schießt der allgemeine Screenshot-Haken dazwischen) |
| `--test-water` | Wasseranimation über die Palettenrotation (OpenRA `RotationPaletteEffect`): hält die Sim an, macht acht Aufnahmen im Abstand von je vier Ticks (ein Rotationsschritt) über einen vollen Umlauf von 28 Ticks und vergleicht die Pixel einer **Uferfläche** gegen eine Landfläche. Erwartet: sieben verschiedene Uferbilder, nach 28 Ticks wieder das erste, Land in jedem Bild gleich. Bilder `…_t0/_t4/_t8/_t28.png`. Karte mit Küste wählen: `--map tournament-island --ai 0 --reveal` |
| `--test-sprechfunk` | **Sprechfunk im Mehrspieler** (docs/MULTIPLAYER.md §10): baut den Mehrspieler-HUD ohne Vermittler auf und nimmt statt des Mikrofons einen Sinuston (am Mac fragt Godot sonst die Systemfreigabe ab, kopflos gibt es gar keinen Eingang). Prüft der Reihe nach: IMA-ADPCM hin und zurück (Rauschabstand ≥ 18 dB, Paketgröße unter der 16-KB-Grenze); dass Chat und Mikrofon **oben in der Kopfzeile rechts neben dem Menüknopf** sitzen (Menü → Chat → Mikrofon, gleiche Größe) und ihre Tippflächen ≥ 48 Geräte-dp sind; die drei Farbzustände (aus grau, Tipp → Team grün `#4DE073`, Langdruck → offener Kanal orange `#FF731A`); die Anzeige „spricht: <Name>" für zwei eingespielte Sprecher; das Stummschalten eines Platzes; den Aus-Schalter aus den Optionen; die **Erstinfo** in Deutsch und Englisch samt Merker (`[multiplayer] voice_intro` in `user://settings.cfg` — beim zweiten Start nicht mehr fällig); die Layoutmatrix (12 Größen × HUD/Optionen); und zum Schluss, dass die **untere Knopfleiste deckungsgleich mit dem Einzelspieler** ist (dieselbe Messung einmal mit und einmal ohne die beiden Knöpfe im HUD, Sollwert 10 von 10). Bilder über `--screenshot PFAD` als `…_aus/_team/_alle/_sprecher/_info_de/_info_en.png`. Endet mit `N Befund(e) (Sollwert 0)`. Beispiel: `--quit-after 30000 -- --map keep-off-the-grass-2 --ai 0 --seed 1 --reveal --starting-units light --test-sprechfunk --screenshot /tmp/funk.png` |
| `--test-spielerliste` | **Spielerliste im Pausenmenü** (docs/MULTIPLAYER.md §12, Toms Handtest 2026-09-09: „wo ich sehen kann, wer noch spielt, welche Farbe, welche Allianz, welches Team"). Zwei Teile ohne Vermittler: erst das laufende **Gefecht** gegen die KI (Farbklecks jeder Zeile gegen `world.player_colors`), dann eine echte **Mehrspieler-Aufstellung** — der Haken baut sie mit `NetHub.build_setup()` (zwei Menschen in Team 1, ein Mensch und eine KI in Team 2), hängt Sitzung und Aufstellung in den Autoload `Net` und lässt `ProtoWorld._apply_setup()` darüber laufen, also genau den Weg eines `start` vom Vermittler. Geprüft wird: alle Plätze stehen in der Liste; Name, Sitznummer und Team stimmen mit der Aufstellung überein; der Farbklecks ist derselbe wie der Lobby-Punkt (`ChatPanel.player_color`); „ich / verbündet / feindlich" stimmt mit `World::hostile` überein; ein Platz ohne Actors steht als **besiegt** und ein Platz nach `peer_left` als **Verbindung weg** da; die Stummschalter des Sprechfunks sitzen in den Zeilen der fremden menschlichen Plätze und wirken; dazu die Layoutmatrix (7 Größen × de/en) über die geöffnete Liste. Bilder über `--screenshot PFAD` als `…_gefecht_de/_gefecht_en/_mehrspieler_de/_mehrspieler_en.png`. Endet mit `N Befund(e) (Sollwert 0)`. Beispiel: `--quit-after 40000 -- --map keep-off-the-grass-2 --ai 2 --seed 1 --reveal --starting-units light --dpi 420 --test-spielerliste --screenshot /tmp/spieler.png` |
| `--test-mikrofon [SEKUNDEN]` | **Aufnahmekette mit dem echten Mikrofon** (docs/MULTIPLAYER.md §11.2/§11.3/§11.7). Gibt je Sekunde Eingabegerät, Frames (und wie viele Abtastwerte davon ≠ 0), rohen Effektivwert, Effektivwert nach dem Herunterrechnen auf 8 kHz, geschätztes Grundrauschen, Schleusenschwelle und -zustand sowie erzeugte und abgeschickte Pakete aus, dann einen Klartext-Befund: `kein Frame` (Aufnahme läuft nicht) / `durchgehend EXAKT 0` (kein Mikrofonsignal — Freigabe fehlt; macOS meldet das nicht von selbst) / `Schleuse hat nie geöffnet` / `Kette vollständig`. Danach spielt er einen Sinus in Sprechlautstärke auf den Aufnahmebus, sodass **echter** Ton durch dieselbe Strecke läuft, und prüft die Schleuse an acht eingespeisten Pegeln, den Nachlauf, alle **vier** Gründe der Notbremse (`no_input` / `no_permission` / `no_signal` / `too_quiet`), das Wiederöffnen des Eingangs und den Wächter bei durchgehend Null. Seit 2026-09-09 dazu die **Plattformweiche der Meldungen** (`VoiceChat.trouble_text_key()`): derselbe Grund, aber auf iOS ein anderer Handgriff — `no_signal` führt dort zuerst in „Einstellungen → PocketRA → Mikrofon" statt zum Neustart, weil iOS eine verweigerte Freigabe nicht meldet, sondern Stille liefert. Geprüft wird auch, dass zu jedem Schlüssel wirklich ein Text in `strings.csv` steht, und der Freigabezustand je Plattform (`VoiceChat.permission_state()` → `ja`/`nein`/**`unbekannt`**; nur Android kann es sagen). Am Ende steht die Diagnosezeile selbst im Protokoll — sie zeigt jetzt **zwei** Raten: `Quelle` (Mischrate, mit der wir auslesen) und `Eingang` (`AudioServer.get_input_mix_rate()`, mit der das Gerät wirklich aufnimmt). Auf Toms Xperia klaffen sie auseinander (44 100 gegen 48 000 — der Fehler aus docs/MULTIPLAYER.md §11.3), auf iOS müssen sie zusammenfallen. Vorweg läuft `AndroidPlugin.self_test()`: die Auswahllogik für das Android-Plugin gegen zwei Attrappen (`AttrappeJni` stellt `JNISingleton` nach — `has_method()` sagt Nein, `has_java_method()` sagt Ja; `AttrappeSkript` ist ein gewöhnliches Objekt), Zeilen `Attrappen …`, Sollwert `Fehlschläge: 0`. Endet mit `N Befund(e) (Sollwert 0)`. Beispiel: `--quit-after 60000 -- --map keep-off-the-grass-2 --ai 0 --seed 1 --starting-units light --test-mikrofon 5` |
| `--test-spy` | Enter-Aktivität und Verkleidung: Pionier repariert das eigene Kraftwerk und erobert die Tesla-Spule, Tanya sprengt die Kaserne, Spion und Dieb infiltrieren Radarkuppel, Raffinerie und Raketensilo (Superwaffen-Ladung zurücksetzen); Verkleidung als Fahrzeug muss abgelehnt werden (`--starting-units heavy --quit-after 20000`, mit `--screenshot` ein Foto der eroberten Spule). Reproduzierbar mit `--map keep-off-the-grass-2 --seed 1`: auf einer zufälligen Karte erreichen der zweite Spion (Raketensilo) und der zweite Pionier (Tesla-Spule) ihr Ziel nicht immer |
| `--test-bridge` | Pionier repariert eine beschädigte Brücke (`RepairsBridges` → `Bridge.Repair`): Brücken-Actor antippbar, `enter_kind` = 5, Kachel wechselt von `DamagedTemplate` zurück auf `Template`. Karte mit Brücken nötig (`--map a-path-beyond --seed 1 --reveal --starting-units heavy`). **Nicht** allies-03a/03b: dort nimmt die Karte dem Pionier `-RepairsBridges:`, weil die Brücken das Missionsziel sind |
| `--test-bridges` | **Jede** Brückenart der Karte auf Sprengbarkeit prüfen (Toms Handtest 2026-09-07 mit Fassung 0.13: „eine kleine Brücke ging nicht“). Listet erst alle Spannen mit Kachel-Template, Regel-Abdruck und der Zahl der Fahrbahnkacheln, auf denen der Langdruck die Spanne trifft — bei BR1/BR2 deckte das Rechteck aus den Regeln nur 6 von 9 bzw. 10 Kacheln, seit dem Fix ist die Trefferfläche der Kachelabdruck (`ProtoWorld._bridge_cell`, docs/ARCHITEKTUR.md §3a). Danach je Art: Tanya auf die Fahrbahn setzen, Langdruck auf die **erste** Kachel, `pick_bridge`/`enter_kind` (3 = sprengen), Radialmenü-Eintrag „Sprengen (C4)“, Einsturz und unpassierbare Fahrbahn. Karten mit unterschiedlichen Arten: `tandem` (sbridge1/sbridge2/bridge1/bridge2), `a-path-beyond` (br1/br2/br3/bridge2), `infiltration` (+ sbridge3), `hypothermia` (Schnee-Kachelsatz). `bridge3`/`bridge4` kommen nur im Wüsten-Kachelsatz vor, für den wir keinen Atlas bauen; `sbridge4` steht auf keiner mitgelieferten Karte. Aufruf: `--autostart --map tandem --ai 0 --seed 1 --reveal --starting-units none --game-speed 4 --test-bridges` |
| `--test-air` | **Zwei** Flugfelder samt Voraussetzungen bauen (jeder Flieger belegt seit der Landeplatz-Reservierung dauerhaft einen eigenen), zwei Flieger produzieren — der Haken meldet ihre getrennten Standplätze und dass ein dritter Flieger ohne freien Platz gesperrt ist —, angreifen lassen, Rotorframes zweier Fotos vergleichen und einen Fallschirmabwurf fliegen (`--screenshot` legt zusätzlich `…_a/_b/_para.png` an sowie `…_leiste.png` mit dem abgedunkelten Cameo und dem Toast „Kein freier Landeplatz"), danach der komplette Transporthubschrauber-Zyklus (`tran` landet von selbst, nimmt drei Mann auf, startet wieder, entlädt auf Befehl und hebt danach ab) |
| `--test-air-player` | Derselbe Weg wie am Gerät, **nur Spielerbefehle** (Bauleiste, Fingertipps): Flugfeld/Helipad samt Voraussetzungen bauen, den Flieger der eigenen Fraktion (Alliierte `heli`, Sowjets `yak`) in die Warteschlange stellen, ihn nach der Produktion antippen, ein gegnerisches Kraftwerk antippen und feuern lassen bis die Munition leer ist, Rückflug und Nachladen abwarten, einen zweiten Angriffsbefehl auf einen Panzer geben, per Tipp auf den eigenen Platz landen und zum Schluss die jeweils andere Angriffsart prüfen (`mig` im Vorbeiflug, `hind` im Schwebeflug). Meldet `FEHLER`, wenn ein Befehl nicht zum Schuss oder nicht zum Schaden führt. `--screenshot` legt `…_angriff.png` mitten im ersten Angriff an. **Mit `--ai 0`** laufen lassen — der Haken setzt die Feindschaft zu Spieler 1 selbst (`sim.set_enemy`) |
| `--test-crash` | Absturz nach `FallsToEarth`: ein Flugzeug (mig/yak — sinkt vorwärts, ohne zu trudeln) und ein Hubschrauber (hind/heli — trudelt drehend senkrecht) werden in der Luft abgeschossen. Erwartet: beide werden zu ihrem Luftwrack (`*.husk`, gleiches Bild), die Höhe sinkt jeden Tick, der Schatten wandert mit, beim Aufschlag zündet `UnitExplodePlane`/`UnitExplodeHeli` (Krater am Boden, Schaden am Panzer darunter). `--screenshot` legt `…_trudeln.png`, `…_fallen.png` und `…_aufschlag.png` an (`--ai 0 --reveal` empfohlen) |
| `--test-rotor` | Sitz der Rotorblätter (`WithIdleOverlay@ROTOR…`) und Zeichenreihenfolge auf dem Landeplatz — Toms Handtest 2026-09-06. Stellt heli, hind und tran in je vier Blickrichtungen (Nord/West/Süd/Ost) in die Luft, meldet je Rotor den Abstand zwischen Rumpf- und Rotormitte gegen den erwarteten Wert aus `BodyOrientation.LocalToWorld` und lässt danach jede Maschine auf einem eigenen `hpad` landen; mig und yak auf `afld` sind die Gegenprobe. Fotos `…_luft_heli/_hind/_tran.png`, `…_pad.png`, `…_afld.png`. `--map keep-off-the-grass-2 --ai 0 --reveal --faction allies --seed 7` |
| `--test-turret` | Sitz der Türme (`WithSpriteTurret`) je Blickrichtung — Toms Handtest 2026-09-07 („Beim Kreuzer sind die Kanonen nicht richtig platziert“). Sucht auf der Karte ein offenes Wasserfeld und stellt Kreuzer, Zerstörer und Kanonenboot (`ca`, `dd`, `pt`) in je vier Blickrichtungen (Nord/West/Süd/Ost) hin; findet er keins, nimmt er `1tnk`, `2tnk`, `jeep` als Gegenprobe. Misst im Zeichenpuffer den Abstand **Turmmitte − Rumpfmitte** und hält ihn gegen `BodyOrientation.LocalToWorld(Turreted.Offset.Rotate(QuantizeOrientation(Facing)))` (Sollwert 0,0 px Abweichung, Toleranz 1,5 px). Fotos `…_ca/_dd/_pt.png` bzw. `…_1tnk/_2tnk/_jeep.png`. `--map tournament-island --ai 0 --reveal --starting-units none` |
| `--test-make` | Bauanimation (`WithMakeAnimation`) — Toms Handtest 2026-09-07 an der sowjetischen Raketenabwehr („die Animation vom Bauen ist versetzt zu dem Objekt selbst“). Setzt **jedes** Gebäude mit eigener make-Datei (40 Stück) auf ein Raster, misst zuerst den fertigen Zustand und schickt sie dann in den Verkauf — der spielt in OpenRA wie in der Sim dieselbe Bauanimation rückwärts (`WithMakeAnimation.Reverse`, `production.cpp:634-635`), nur ohne Warteschlange, Voraussetzungen und Bauzeit. Geprüft wird je Gebäude, ob der Körper an `Mitte − halbe make-Größe + make-Offset` sitzt und ob während der Bauanimation **kein** Turm gezeichnet wird (`WithSpriteTurret: RequiresCondition: !build-incomplete`). Endet mit `N Befund(e) (Sollwert 0)`. Läuft **headless**, keine Bilder: `--headless --map keep-off-the-grass-2 --ai 0 --reveal --starting-units none --test-make` |
| `--test-cargo` | Transporter und fünf Infanteristen erzeugen: einsteigen, fahren, entladen; dazu Panzer-am-MTW abgewiesen (`Cargo.Types`) und Entladebefehl durch Fahrbefehl ersetzt |
| `--test-deploy` | Entfalten mit Sonderfunktion über die echten UI-Wege: Minenleger legt eine Mine (grünes Blinkzeichen im Bild `…_zeichen.png`, gelegte Mine in `…_mine.png`), MAD-Panzer entfaltet (Ladeanimation „piston" in `…_laden.png`, Erschütterungs-/Detonationsschaden, Fahrerauswurf, Selbstzerstörung), Sprengstoff-LKW zündet sofort, Chrono-Panzer springt und wird beim zweiten Versuch von der Abklingzeit abgewiesen (`…_chrono.png`); zum Schluss der **Weitsprung** quer über die Karte (`tools/balance.yaml` `chrono_unlimited`, docs/ARCHITEKTUR.md §3a): herausgezoomte Kamera, Bilder `…_chrono-fern-vorher.png` / `…_chrono-fern-nachher.png`, gemeldet werden zurückgelegte Zellen und der Abstand zur Zielzelle |
| `--test-crate` | Kiste einsammeln: ein eigener schwerer Panzer fährt über eine Kiste, drei weitere eigene Panzer stehen in ein, zwei und sechs Zellen Abstand. Gemeldet werden die Trefferpunkte aller vier vor und nach dem Einsammeln (Bilder `…_kiste-vorher.png` / `…_kiste-nachher.png`). Ohne weitere Angabe erzwingt der Haken über `--crate-type explode` die **Explosionskiste** (Toms Handtest 2026-09-07); erwartet wird dann Schaden am Sammler **und** an den eigenen Nachbarn (OpenRA `CrateExplosion`/`CrateNapalm` mit `AffectsParent: true`). `--ai 0 --reveal --starting-units heavy --screenshot-at 99999` empfohlen |
| `--crate-type NAME` | Kistenart erzwingen: nur diese eine `CrateAction` bleibt in der Liste des Actors `crate` (`proto_world.gd` `_crate_actions`). Namen: `cash`/`geld`, `levelup`/`rang`, `explode`/`explosion`, `hidemap`, `heal`, `revealmap`, `duplicate`, `unit`, `basebuilder`. Wirkt auch ohne `--test-crate`, z. B. zusammen mit `--crates 1` in einem gewöhnlichen Gefecht |
| `--test-forcefire` | Zwangsfeuer auf die eigene Seite (OpenRA `AttackBase` mit `forceAttack`, dort der Ctrl-Klick): setzt zwei eigene Panzer und ein eigenes Kraftwerk, prüft zuerst die Gegenprobe (ein Angriffsbefehl **ohne** Zwangsfeuer auf die eigene Einheit muss abgewiesen werden und darf keinen Schaden machen), geht dann den echten Bedienweg — Auswahl, Langdruck auf das eigene Ziel, Radialmenü-Eintrag „Zwangsangriff" — für Einheit und Gebäude. Bilder: `…_radial.png`, `…_treffer.png`, `…_radial_gebaeude.png`, `…_gebaeude.png`. `--ai 0 --reveal --starting-units none` empfohlen |
| `--test-defense-fire` | **Wehrtürme gegen Gebäude** (Toms Handtest 2026-09-09: „Verteidigungsanlagen wie Flammwerfer können nicht auf andere Gebäude schießen. Auch Verteidigungsanlagen brauchen Zwangsfeuer und sollten automatisch auch Gebäude angreifen“). Vier Fälle über die echten Bedienwege: (1) ein eigener Flammenturm (`ftur`) neben einer **feindlichen** Kaserne muss sie ohne jeden Befehl angreifen und zerstören (Sim: bewaffnete Gebäude tragen `Structure` in der AutoTarget-Liste, `docs/ARCHITEKTUR.md` §3a); (2) Turm anwählen, **Langdruck** auf das eigene Kraftwerk, „Zwangsangriff“ im Ring — der Befehl muss halten (`force_attacking` jeden Tick), bis das Ziel fällt; (3) mit gewähltem Turm muss der gewöhnliche **Fingertipp** auf ein feindliches Gebäude ein Angriffsbefehl sein (vorher landete er im Sammelpunkt-Zweig); (4) „Zwangsfeuer“ aus demselben Ring auf eine **Zelle** räumt die eigene Sandsackmauer. Gemeldet werden je Fall Tick des ersten Treffers, Ziel-ID, Trefferzahl und Endzustand; Bilder `…_auto.png`, `…_ring.png`, `…_zwangsfeuer.png`, `…_tipp.png`, `…_zelle.png`. Läuft headless. Beispiel: `--map keep-off-the-grass-2 --ai 0 --seed 1 --reveal --starting-units none --test-defense-fire` |
| `--test-c4` | Sprengladung von Tanya/Volkov (OpenRA `Demolition`, Order „C4“): Tanya, ein gegnerischer Panzer, ein gegnerisches Gebäude, ein eigener Panzer und ein eigenes MTW. Prüft der Reihe nach `sim.enter_kind_for` je Ziel (Gegnerpanzer und -gebäude 3 = sprengen, **eigenes** Fahrzeug 0 — es darf nie ein Einsteigebefehl daraus werden), die blassen Bombensymbole über allen gültigen Zielen, den Radialmenü-Eintrag „Sprengen (C4)“ beim Langdruck, den gewöhnlichen Tipp (Ziellinie `goal_kind` 4, kein Transporter), den ablaufenden Zünderring am Ziel, die Explosion nach `DetonationDelay` (45 Ticks), dass Tanya überlebt (`EnterBehaviour Exit`), danach denselben Weg noch einmal über den Radialmenü-Eintrag auf dem gegnerischen Gebäude und zum Schluss die Gegenprobe, dass der Tipp aufs eigene MTW weiterhin einsteigt. Bilder: `…_ziele.png`, `…_radial.png`, `…_timer.png`, `…_explosion.png`. Seit 2026-09-07 zusätzlich: **neutrale Zivilbauten** — Zivilhaus V01 und Ölpumpe V19 des Neutral-Spielers müssen `pickable()` bestehen, von `pick_unit()` getroffen werden und auf den Tipp hin hochgehen (Toms Befund „zeigt mir, dass sie die Ölfelder und Häuser sprengen könnte, aber sie tut es nicht“); die **Brücke** — der gewöhnliche Tipp darf sie *nicht* treffen, der Langdruck schon, danach ist die Fahrbahn Wasser/Fels; und durchgehend, wie lange Tanya am Stück unsichtbar ist (zwei Ticks sind normal, dauerhaft hieße „sie steigt ein“). Fahrzeuge sind sprengbar, weil `tools/balance.yaml` `rules.c4_vehicles` OpenRAs Kampagnenregel (`campaign-rules.yaml:73-74` `^Vehicle: Demolishable:`) auch im Gefecht gelten lässt, Brücken über `rules.c4_bridges` (docs/ARCHITEKTUR.md §3a). Für den Brückenteil eine Karte mit Brücken wählen, sonst wird er übersprungen: `--map a-path-beyond --ai 0 --seed 1 --reveal --starting-units none --test-c4` |
| `--test-wall` | **Mauern und Zäune** (Toms Handtest 2026-09-07: „Ich kann nicht auf Mauern und Zäune schießen. Egal ob neutral, eigen oder fremd“). Stellt alle sechs Mauerarten (`sbag`, `fenc`, `brik`, `cycl`, `barb`, `wood`) für vier Besitzer auf (eigen, verbündet, neutral, feindlich) und meldet je Kombination `pickable()`, ob `pick_unit()` sie unter dem Finger trifft und ob sie feindlich ist — Sollwert 24 von 24 antippbar. Danach vier echte Bedienwege: die **fremde** Mauer fällt auf den gewöhnlichen Fingertipp (`_on_tap` → Angriffsbefehl), die **eigene, verbündete und neutrale** nur über den Langdruck-Ring „Zwangsfeuer“ (wie OpenRA: `Armament.TargetRelationships: Enemy` gegen `ForceTargetRelationships`, `Armament.cs:72-73`). Zum Schluss zwei Gegenproben: ein Baum/Feld bleibt `pickable() == false`, und ein Tipp auf die **eigene** Mauer lässt die Truppenauswahl stehen (`^Wall` hat `Interactable`, aber kein `Selectable`). Läuft headless. Beispiel: `--map keep-off-the-grass-2 --ai 0 --seed 1 --reveal --starting-units none --test-wall` |
| `--test-bauradius` | **Baubereich** (Toms Handtest 2026-09-09: „Mauern und Zäune sollen frei im Bauhof-Umkreis platzierbar sein" und „Zählen Silos zur Basiserweiterung?"). Rechnet den Baubereich um den Bauhof nach und meldet drei Dinge: (1) welche Gebäude laut Regeln Baufläche geben — Sollwert ist die Liste aus mods/ra (`-GivesBuildableArea` bei jeder `^Defense`, `silo`, `kenn`, `spen`, `syrd`); (2) für eine Mauer (`sbag`) und ein gewöhnliches Gebäude (`silo`) die Zahl der erlaubten Zellen in einem 41×41-Fenster samt Karte zum Mitlesen (`+` erlaubt, `.` frei aber außerhalb, `#` belegt/falsches Terrain); (3) eine Probe mit Silo und eine Gegenprobe mit Kraftwerk — neben dem Silo bleibt das Bauen verboten, neben dem Kraftwerk ist es erlaubt. Endet mit `N Befund(e) (Sollwert 0)`. Vor der Änderung vom 2026-09-09: `sbag 195 von 572 freien Zellen erlaubt, größter Abstand zum Bauhof 8 Zellen`; danach `368 von 572 … 15 Zellen` (der ganze `BaseProvider`-Kreis). Läuft headless. Beispiel: `--headless --map keep-off-the-grass-2 --ai 0 --seed 1 --reveal --starting-units none --test-bauradius` |
| `--test-capture` | Eroberte Anlagen schalten die Technik der Gegenseite frei (Toms Wunsch 2026-09-07: „Wenn wir die Sowjets sind und mit dem Ingenieur einen Bauhof von den Alliierten übernehmen … dann sollte für mich auch die alliierte Technologie freigeschaltet sein.“). Setzt Spieler 0 auf `soviet` und Spieler 1 auf `allies`, stellt eine sowjetische Basis (fact/powr/proc/barr/weap/dome/fix) und daneben alliierte Anlagen des Gegners (tent/weap/fact/atek) hin und schickt je einen Pionier über den echten Fingertipp los. Gibt je Reiter aus, was **sichtbar** in der Bauleiste steht (`_all_types` minus `sim.hidden_items`) und was `sim.buildable` freigibt — vor der Eroberung, danach und nach der Zerstörung des eroberten Bauhofs. Pflichtprüfungen: nach der Eroberung Gebäude `tent, atek, hpad, syrd`, Abwehr `pbox, gun, agun`, Infanterie `medi, mech`, Fahrzeuge `1tnk, jeep, 2tnk, arty`; nach dem Verlust des Bauhofs sind die alliierten Gebäude und Abwehranlagen wieder weg, Sanitäter und Alliiertenpanzer bleiben, solange Kaserne und Fabrik unser sind. Grundlage: `ProvidesPrerequisite` merkt sich die Fraktion der Erzeugung (`FactionInit`) und behält sie beim Besitzerwechsel — `ResetOnOwnerChange` steht in `mods/ra/rules/*.yaml` überall auf `false`. Aufruf: `--autostart --map a-path-beyond --ai 0 --seed 1 --reveal --starting-units none --game-speed 4 --test-capture` |
| `--test-placement-cancel` | Toms Handtest: fertiges Wassergebäude (`spen`/`syrd`) ohne Wasser in Reichweite, „Abbrechen" als echter Fingertipp — der Platzierungsmodus muss enden und darf nicht zurückkommen, das Gebäude bleibt „Ready" in der Warteschlange, ein Tipp aufs Cameo nimmt es wieder auf |
| `--test-naval` | Werft (`syrd`/`spen` je Fraktion) auf Wasser bauen, Kanonenboot/Zerstörer bzw. U-Boot über die Queue „Schiffe" produzieren, ein gegnerisches U-Boot setzen und angreifen lassen; danach ein angeschlagenes Schiff an der Werft reparieren (ein Panzer muss dort abgewiesen werden, `RepairActors`) und einen Kreuzer `ca` mit seinen Zwillingstürmen ein Gebäude an Land beschießen lassen (Screenshot `*_kreuzer.png`). Meldet Wegsuche auf Wasser, Werft-Platzierungsregel (Wasser ja, Land nein), Tarnung/Aufdeckung des U-Boots. Karte mit viel Wasser wählen (z. B. `--map tournament-island`), `--reveal --starting-units heavy` empfohlen |
| `--test-msub` | Raketen-U-Boot: U-Boot-Bunker `spen` auf Wasser bauen, `msub` über die Queue Schiffe produzieren, prüfen dass es getaucht startet und ohne Befehl nicht feuert (`AutoTarget.InitialStance: HoldFire`), dann ein gegnerisches Gebäude an Land beschießen (`SubMissile`, 20 Zellen) und das Auftauchen prüfen. Screenshots `*_getaucht.png` / `*_aufgetaucht.png` — getaucht ist das eigene Boot ein halbdurchsichtiger schwarzer Schattenriss ohne Spielerfarbe (`Cloak.CloakStyle: Color`), aufgetaucht wieder normal. Karte mit viel Wasser wählen (z. B. `--map tournament-island`) |
| `--test-lst` | Landungsboot komplett über echte UI-Befehle (nicht die Sim-API direkt): Werft bauen, `lst` produzieren, Infanterie/Panzer wählen und das Boot antippen (Einsteigen über die Uferzelle), quer übers Wasser schicken, per „Entladen“ an einer anderen Uferstelle absetzen, wieder ablegen und zum Schluss ein beladenes Boot zerstören (Ladung stirbt mit). Karte mit viel Wasser wählen (z. B. `--map tournament-island`); zusätzlich wird der Entladebefehl auf offener See abgewiesen (`Cargo.CanUnload`). Mitgeschrieben wird außerdem die **Bugrampe** (`WithLandingCraftAnimation`): jede Zeile meldet ihren Zustand, am Schluss steht die beobachtete Folge (`T: Rampenfolge [0, 1, 2, 3, 0]` = zu → fährt auf → offen → fährt zu → zu). Fotos: `…_see.png` (draußen, Rampe zu), `…_rampe_offen.png` (am Ufer, Rampe ausgefahren, noch niemand ausgestiegen), `…_entladen.png` (Ladung an Land, Rampe weiter offen), `…_rampe_zu.png` (abgelegt, Rampe eingefahren) |
| `--test-motion` | Zucken messen: alle eigenen Einheiten fahren 30 Zellen (Befehl alle 20 Ticks erneuert wie beim Verfolgen), jeder Frame liest die interpolierte Position und zählt Rückwärtssprünge. Erwartet 0. `--starting-units heavy --quit-after 12000` |
| `--test-projectile` | Raketen in Flugrichtung: e3 (Dragon) und v2rl (SCUD) feuern in vier Richtungen, meldet die benutzten Facing-Frames; mit `--screenshot` ein Bild vom Flug (`--reveal --starting-units heavy`) |
| `--test-effects` | Treffer- und Todeseffekte je Kategorie (OpenRA `CreateEffectWarhead` + `WithDeathAnimation`): 18 Einzelfälle nacheinander an eigenen Zellen — Kugel (`piff`), Maschinenkanone (`piffs`, gestaffelt über die Delays 0/2/4/…), Granate und Rakete (`med_explosion`), Napalm, Flak in der Luft (`small_explosion_air`), Wassereinschlag klein/groß (`small_splash`/`large_splash`), Schiffstod (`building` **und** `large_splash` zugleich), Infanterietod je Schadensart (`die1`…`die6` inkl. brennend und Elektro-Skelett), Zermatschen (`die-crushed`), Fahrzeugtod (`large_explosion`) und Gebäudetod (eine von fünf Explosionen). Mit `--screenshot` je Fall ein dreifach vergrößerter Ausschnitt `<pfad>_<name>.png` um die Einschlagzelle, aufgenommen mitten in der Sequenz. Karte mit Küste wählen, sonst entfallen die Wasserfälle: `--map tournament-island --ai 0 --reveal --starting-units none` |
| `--test-barrels` | Fässer: Angriffsbefehl auf ein Fass, Kettenreaktion zum Nachbarfass, Schaden an der Infanterie daneben (mit `--starting-units none` laufen, sonst zählt der Haken die Begleitinfanterie mit) |
| `--test-barrels --mission SLUG` | Dasselbe auf einer Kampagnenkarte mit deren eigenen Fässern (die gehören dort einer Partei, nicht dem Neutralen): sucht das Fass mit den meisten Nachbarn, setzt einen eigenen Schützen daneben und meldet, wer danach tot bzw. beschädigt ist (`allies-01`, `soviet-07`, `allies-05a`) |
| `--test-autotarget` | Autofeuer (`AutoTarget`): der ersten eigenen Einheit mit Waffe — im Gefecht ein frisch gesetztes `e7`, in einer Mission die Tanya des Skripts — wird ein Gegner in Reichweite gesetzt; meldet Typ, Stance und ob sie ohne Befehl geschossen hat (erwartet: `e7` ja, `e7.noautotarget` nein) |
| `--test-retreat` | Rückzug unter Beschuss (OpenRA `AutoTarget.Damaged` mit `!self.IsIdle` und `AttackFollow` `OpportunityFire`): vier eigene `2tnk` stehen vor drei gegnerischen `3tnk` (Stance AttackAnything, sie verfolgen), bekommen einen Bewegungsbefehl 16 Zellen nach Westen und müssen ihn ohne Halt zu Ende fahren, während ihre **Türme** nach hinten drehen und mitfeuern. Meldet: wie viele am Ziel, längster Stillstand ohne Fahrbefehl (Sollwert 0, gemessen über `sim.has_move_order()`), Trefferpunkte vorher/nachher und den Schaden an den Verfolgern. `--screenshot` legt mitten im Rückzug ein Bild an (Wannen nach Westen, Türme nach Osten). `--ai 0 --reveal --starting-units none` empfohlen |
| `--test-armaments` | Mehrfachbewaffnung (OpenRA `AttackBase.Armaments` „primary, secondary"): acht Schütze/Ziel-Paarungen nacheinander — 4tnk MammothTusk gegen Infanterie (auch auf 6 Zellen, wo das 120mm nicht mehr reicht) und 120mm gegen Panzer, ftrk FLAK-23-AG/-AA, e3 Dragon/RedEye, 1tnk 25mm. Misst je 300 Ticks den Schaden am Ziel gegen den aus `weapons.yaml` erwarteten Mindestwert; mit `--screenshot` ein Bild des Mammuts zwischen beiden Zielen. `--ai 0 --reveal --starting-units none` empfohlen |
| `--test-husk` | Wracks und Brandflecken: vier Fahrzeuge mit verschiedenen Blickrichtungen setzen, zerstören und prüfen, dass jedes ein Wrack mit derselben Blickrichtung hinterlässt und der Todes-Sprengkopf (`^Explosion` `Warhead@Smu: LeaveSmudge`) Krater auf dem Boden zeichnet; nach 1200 weiteren Ticks sind die Wracks ausgebrannt, die Krater bleiben. `--screenshot` legt zusätzlich `…_wrack.png` an (`--reveal` empfohlen) — auf dem Foto muss das Wrack **verrußt** aussehen (`^Husk` trägt ein `WithColoredOverlay@IDISABLE` ohne Bedingung), nur die Flamme leuchtet hell |
| `--test-kaserne` | Kaserne (alliiert `tent`, sowjetisch `barr`): Bauhof und zwei Kraftwerke hinstellen, die Kaserne über die Bau-Warteschlange **platzieren** (nur so läuft die `make`-Animation), dann vier Bilder mit Bericht — `bau` (mitten in der Bauanimation), `hell` (fertig, Strom im Plus), `stromlos` (Kraftwerke gesprengt, Bilanz negativ), `wieder` (Strom zurück). Gemeldet werden Frame, Palettenzeile aus `render_buffer` und das Strom-Bit aus `render_state`. **Sollwert: immer Palettenzeile 0 (helle Spielerzeile) und Strom-Bit `false`** — die Kaserne trägt in mods/ra kein `^DisableOnLowPower` (das haben nur `mslo`, `gap`, `iron`, `pdox`, `tsla`, `agun`, `dome`, `sam`, `atek` und ihre vier Attrappen) und darf bei Strommangel deshalb nicht abdunkeln; der Haken vergleicht die ganze Liste gegen mods/ra und endet mit `N Befund(e) (Sollwert 0)`. Beispiel: `--map keep-off-the-grass-2 --ai 0 --faction allies --reveal --test-kaserne --screenshot /tmp/k.png` |
| `--test-gap` | Tarngenerator (`CreatesShroud`): ein Beobachter aus fünf `2tnk` sieht auf eine Stelle, dort wird der gegnerische `gap` gesetzt und danach sein Kraftwerk abgeschaltet. Gezählt werden schwarze, vernebelte und sichtbare Zellen im Umkreis — erwartet wenige → viele → wieder wenige, dazu vier Gegner, die unter der Tarnung verschwinden. **Ohne `--reveal`** laufen lassen (das schaltet den Shroud ab und der Haken misst nichts), `--ai 0` empfohlen |
| `--test-gps` | GPS-Satellit (`atek`, `GpsPower`) mit Nebel: eigene Basis (vier Kraftwerke, Radarkuppel, Tech-Center) und eine Gegnerbasis weit weg hinstellen, ein eigener `2tnk` sieht **genau ein** Gebäude davon und wird danach zerstört. Erwartet vor dem Start eingefrorene Gebäude > 0 und Punkte 0 (Foto `…_vorher.png`); nach dem Satellitenstart (Ladezeit per direktem `sim.step()`-Vorlauf übersprungen) unverändert wenige eingefrorene Gebäude, dafür `GpsDot`-Punkte für alles nie Gesehene (Foto `…_gps.png`: eingefrorene Gegnergebäude im Nebel plus rote Punkte); zum Schluss wird das eingefrorene Gebäude zerstört — die Momentaufnahme muss stehen bleiben (`…png`). **Ohne `--reveal`** laufen lassen, `--ai 0 --faction allies --starting-units heavy --screenshot-at 99999` empfohlen  **Immer mit `--ai 0` und einer Karte laufen lassen, auf der der Späher wirklich Sicht bekommt (`--map pool-party`)**: mit den KI-Gegnern aus `user://settings.cfg` reißen die Gegner die eigene Basis während des `sim.step()`-Vorlaufs ein und der Satellit startet nie. Der Haken setzt die Gegnerbasis relativ zur eigenen Startzelle — landet sie auf *pool-party* im See, scheitert die Platzierung still und `eingefroren` bleibt 0. Dann mit festem `--seed` wiederholen (`--seed 7` und `--seed 42` sind geprüft: eingefroren 4 bzw. 7). |
| `--test-nebel` | **Nebel des Krieges an einer gegnerischen Einheit** (Toms Handtest 2026-09-09: „Wenn der Fog of War aktiviert ist, bleiben Einheiten trotzdem unsichtbar vom Gegner"). Ein waffenloser eigener `mcv` steht still (RevealsShroud 4 Zellen), drei weitere erkunden einmal den Fahrweg und verschwinden; dann fährt ein gegnerischer `mcv` in die Sichtweite und wieder heraus, ein zweiter steht die ganze Zeit in **nie erkundetem** Gebiet (Gegenprobe). Gedruckt wird je Schritt die **Sichtstufe der Gegnerzelle** (0 schwarz, 1 Nebel, 2 sichtbar) neben dem Render-Merker `visible` — laufen die beiden auseinander, sitzt der Fehler in der Darstellung, laufen sie zusammen, in der Sichtkarte der Sim. Erwartet mit `--fog an`: draußen unsichtbar → drinnen sichtbar → draußen wieder unsichtbar; mit `--fog aus`: durchgehend sichtbar, solange der Gegner in erkundetem Gebiet steht, die Gegenprobe in beiden Fällen unsichtbar. Endet mit `--test-nebel Ende: N Fehler (Sollwert 0)`. **Ohne `--reveal`** laufen lassen. Aufruf: `--headless --autostart --map keep-off-the-grass-2 --ai 0 --seed 1 --starting-units none --test-nebel` (und derselbe Lauf mit `--fog aus`); mit `--screenshot PFAD` entstehen `…_sichtbar.png` und `….png` |
| `--test-jammer` | Radar-Störsender (`mrj`): eigene Radarkuppel mit Strom hinstellen (Foto der ruhigen Minimap in `…_radar.png`), dann einen gegnerischen `mrj` in Reichweite und daneben einen eigenen `mgg` setzen — beide mit der drehenden Schüssel (`WithIdleOverlay@SPINNER`). Erwartet `Radar=true gestört=false` → `Radar=false gestört=true`, auf dem zweiten Foto zeigt die Minimap animiertes Rauschen statt der Karte. `--ai 0 --reveal` empfohlen |
| `--test-mech` | Mechaniker (`mech`) und Wracks: zwei Wracks setzen (eines fremd, eines eigen) und je einen Mechaniker hinschicken. Erwartet: beide Wracks verschwinden, an ihrer Stelle stehen zwei **eigene** Fahrzeuge mit 15 % Trefferpunkten (`TransformOnCapture`/`InfiltrateForTransform`, `ForceHealthPercentage: 15`), die Mechaniker gehen dabei auf. `--ai 0 --reveal` empfohlen |
| `--test-defeat` / `--test-victory` | eigene bzw. gegnerische Actors entfernen und das Spielende abwarten (EVA misnlst1/misnwon1 und Musik map/score prüfen; mit `--diag` steht jede EVA-Meldung im Log) |
| `--test-save` | Spielstand: 1500 Ticks spielen, sichern, 500 Ticks weiter (Hash A), im selben Prozess laden, dieselben 500 Ticks (Hash B). A == B erwartet; schreibt zusätzlich Slot 5 (`--quit-after 12000`) |
| `--test-speed [--game-speed 0..4]` | Ticks/s über 10 s messen — Stufen (80/50/40/30/20 ms): 12,5/20/25/33,3/50 Ticks/s (`--quit-after` ≥ 3000) |
| `--test-speed-switch N` | Nach 5 s per `GameSpeed.set_index(N)` live umschalten (wie ein Regler-Griff, nicht die `--game-speed`-Vorbelegung) und weitere 5 s messen — prüft den Tick-Mechanismus direkt |
| `--test-speed-ui` | Wie `--test-speed-switch`, aber über den echten UI-Weg: synthetischer Fingertipp (`InputEventScreenTouch`) zweimal auf die „+"-Taste der Pausenmenü-Geschwindigkeitszeile, misst davor/danach je 5 s — prüft Knopf/Callback statt `GameSpeed.set_index()` direkt aufzurufen |
| `--load SLOT` | (an `main_menu.tscn`) einen Spielstand über den Menüweg starten — `1`…`5` oder `a1`…`a3` |
| `--test-lobby` | (an `main_menu.tscn`) Gefecht-Lobby: KI-Zahl hoch/runter (Platzzeilen müssen folgen, Fraktion/Team der wieder eingeblendeten KI bleiben), Kartenüberlagerung fotografieren, dann Team 1 = Spieler + KI 2 starten und den Tipp-Pfad prüfen — Verbündeten antippen = Bewegen, Feind antippen = Angriff. Braucht eine Karte mit mindestens vier Startplätzen (z. B. `--map pool-party`) und `--reveal`: unter dem Nebel ist der feindliche Actor nicht antippbar, die Gegenprobe meldet sonst „kein Angriff auf Feind". Im Fenster laufen lassen (Screenshot) |
| `--test-maps-unlock` | (an `main_menu.tscn`) stellt die Verteil-APK beim Erststart nach: zählt die Gefechtskarten, benennt `user://content/atlas.off` in `atlas` um (der Moment, in dem die Seite „Spielinhalte einrichten" fertig meldet), löst denselben Pfad wie deren `unlocked`-Signal aus und zählt erneut — `T: Karten — vorher 0, nachher N (OK)`. Vorbereitung: `game/assets/atlas` wegräumen, Inhalte per `--test-content` bauen, dann `mv "$U/content/atlas" "$U/content/atlas.off"`. Im Fenster laufen lassen (Screenshot über `--menu-screenshot`) |
| `--test-cycle` | Menü → Gefecht → Menü → Mission → Menü in einem Lauf |
| `--update-url URL` | (an `main_menu.tscn`) Versionsdatei der Aktualisierung überschreiben (Standard: `UpdateConfig.DEFAULT_URL`); erzwingt die Prüfung auch bei ausgeschaltetem Schalter |
| `--test-update` | einen Prüflauf abwarten und melden: `T: Update — Ergebnis ready\|uptodate\|need_app\|blocked\|error\|pack_off, eigenes Paket N, Extension X, gesperrt ja/nein` und eine zweite Zeile `T: Update — neue App gemeldet: 0.7, Fenster offen: true, gemerkt: 0.7` (Hinweisfenster „Neue Version … verfügbar"; beim zweiten Lauf gegen dieselbe Version steht dort `Fenster offen: false`). Hebt zugleich den Entwicklerlauf auf, hängt also auch `current.pck` ein. **Im Fenster laufen lassen, nicht `--headless`** — dort kam die HTTP-Antwort im Test nicht an. Seit 2026-09-09 zusätzlich eine Zeile `T: Update — Plattform X, Paket erlaubt: …, Knopf '…', Sperrtext '…'` und die **Plattformweichen-Matrix**: gegen dieselbe erfundene `version.json` wird jede Plattform durchgespielt (iOS ohne und mit `ios_version`/`ios_url`, Android, Windows, macOS) und geprüft, welche URL, welche Fernversion und welcher Paketzustand herauskommen — `T: Update — Plattformweichen: 0 Fehlschläge (Sollwert 0)`. Das ist der Teil, der ohne Gerät belegbar ist |
| `--force-platform NAME` | **die Plattform vorgeben** (`iOS`, `Android`, `Windows`, `macOS` …), statt `OS.get_name()` zu glauben. Damit lassen sich am Mac genau die Weichen prüfen, die sonst nur auf dem Gerät greifen: der Hinweis auf eine neue App-Fassung, die Sperrseite, das Aktualisierungspaket und die Mikrofonmeldungen. Ausgewertet in `AndroidPlugin.platform()` (eine Stelle für alle drei Nutzer) und, eigens dupliziert, in `UpdateBoot._pack_enabled()` — sonst ließe sich das **Einhängen** eines Pakets nicht nachstellen. Beispiel: `-- --force-platform iOS --update-url http://127.0.0.1:8123/version.json --test-update` |
| `--update-pack on\|off` | das Aktualisierungspaket für diesen Lauf ein- oder ausschalten (schlägt `user://settings.cfg` `[update] pack` und die Vorgabe „auf iOS aus", s. `docs/IOS-PAKET.md`). Wirkt auf **beides**: das Laden (`UpdateConfig.pack_enabled()`) und das Einhängen (`UpdateBoot`) |
| `--test-content-ui` / `-cancel` / `-badsum` / `-error` | (an `main_menu.tscn`) Seite „Spielinhalte einrichten": Freeware-Download → Prüfsumme → Entpacken → Atlanten/Sounds gegen einen lokalen Server (`--content-url URL`, optional `--content-sha1`), Abbruch mitten im Download, erkannte Prüfsummenabweichung, bzw. Netzfehler mit rotem Klartext-Kasten und weiter bedienbaren Knöpfen. **Im Fenster laufen lassen.** `--force-content-locked` tut so, als sei dies eine Verteil-APK ohne Inhalte |
| `--test-content-ui-queue` | (an `main_menu.tscn`) **Warteschlange**: Freeware-Paket und Alliierten-Abbild direkt hintereinander antippen. Erwartet: der zweite Tipp verpufft nicht, die Kopfzeile zeigt „Auftrag 1 von 2", die übrigen Knöpfe bleiben bedienbar, beide Aufträge laufen nacheinander durch, und das heruntergeladene Abbild ist danach gelöscht. Braucht `--content-url`/`--content-sha1` **und** `--content-cd-url` (s. `tools/make_test_content.py`) |
| `--test-content-disclaimer` | (an `main_menu.tscn`) **Haftungsausschluss**: vor dem ersten Download muss das Hinweisfenster kommen, „Abbrechen" darf nichts starten, „Ich habe verstanden und stimme zu" wird gemerkt und reicht den Auftrag durch, beim nächsten Mal erscheint das Fenster nicht mehr. Braucht `--content-url`/`--content-sha1` (der durchgereichte Auftrag wird sofort abgebrochen) |
| `--test-music` | (an `main_menu.tscn`) **Original-Musik der CD**: richtet die Attrappen-CD des lokalen Servers ein (`--content-cd-url`, s. `tools/make_test_content.py` — ihr MAIN.MIX enthält ein echtes Mini-`scores.mix` mit zwei kurzen AUDs unter den Namen `hell226m`/`bigf226m`) und prüft, dass danach **ohne Neustart** die Original-Musik mit den Namen aus `music.yaml` läuft, dass sich ein Titel als Stream öffnen lässt, dass der Schalter „Musik: Eigene/Original" beide Wege geht und dass nach dem Löschen der CD wieder die eigenen Stücke übrig bleiben |
| `--test-touch-scroll` | (an `main_menu.tscn`) **Rollen mit dem Finger** auf „Spielinhalte einrichten", den Optionen und der Protokolltafel: schickt synthetische `InputEventScreenTouch`/`-Drag` über einem Text, einer Karte und einem Knopf und misst den Rollstand; dazu Tipp auf einen Knopf (muss auslösen), Zug über dem Knopf (darf nicht auslösen) und Zug über dem Lautstärkeregler (darf die Seite nicht rollen). Am Mac schaltet der Haken `Input.set_emulate_touch_from_mouse(true)` ein — sonst meldet `DisplayServer.is_touchscreen_available()` falsch und Godots ScrollContainer wertet Fingerzüge gar nicht aus |
| `--test-benachrichtigungen` | (an `main_menu.tscn`) **Benachrichtigungs-Schalter der Optionen** (docs/MULTIPLAYER.md §10.4): Speichern und Wiederlesen von `[notify]` in `user://settings.cfg`; dass der Hauptschalter über den drei Anlässen steht; das JSON `events_flags()`, das der Vordergrunddienst mitbekommt; dass ein abgeschalteter Anlass in `net_hub._local_notify()` (Chat über den echten `_on_chat`-Weg) wirklich still bleibt; dass der Hauptschalter den Dienst gar nicht erst startet und ein Umlegen bei offenem Raum sofort wirkt (`refresh_watch`); dass der Abschnitt am Schreibtisch gar nicht erst in den Optionen steht; und die Tippflächen der neuen Knöpfe gegen den Bestand derselben Seite. Die vorgefundenen Einstellungen werden am Ende wiederhergestellt. Endet mit `T: --test-benachrichtigungen fertig — N Befund(e)` (Sollwert 0) |
| `--notify-demo` | (an `main_menu.tscn`) den Benachrichtigungs-Abschnitt der Optionen auch am Schreibtisch zeigen (er gehört sonst nur auf Android) und die Freigabe als „fehlt" behandeln, damit der **größte** Aufbau im Bild steht; rollt vor dem Foto ans Seitenende. `--test-layout` schaltet ihn selbst ein |
| `--test-content-delete` | (an `main_menu.tscn`) Optionen → „Spielinhalte löschen": Manifest setzen, `ContentManager.delete_all()`, prüfen, dass `user://content` weg ist und die Erststart-Sperre wieder greift |
| `--content-cd-url URL` | Adresse aller drei CD-Abbilder überschreiben (Attrappen-ISO vom lokalen Testserver) |
| `--content-shots DIR` | dazu: alle 40 Bilder ein Foto ablegen (Fortschritt in jeder Phase) plus `final.png` |
| `--test-content-lang [--content-de PFAD] [--keep]` | (an `intro.tscn`, dem Startlader) **deutsche Sprachausgabe von der CD** (Toms Gerätetest 2026-09-09: „Deutsche Iso installiert, aber keine deutschen Einheitenstimmen“). Prüft der Reihe nach: liegt jeder Name aus `ContentPage.KEEP_FILES["german"]` wirklich in der deutschen `MAIN.MIX` (und `speech.mix` gerade **nicht** — das steckt in `INSTALL/REDALERT.MIX`); baut aus `content/ra_de` einen Gerätezustand nach `user://content/cd/german` samt englischer Grundfassungen in `user://content/sfx`; ruft `ContentManager.build_language_sounds("de")` — denselben Aufruf wie die Einrichtungsseite — und erwartet rund 277 Clips; prüft zuletzt, dass `ContentPaths.sfx()` für Proben aus allen vier Quellen (allies/russian/sounds/speech) die Datei unter `sfx/de/` wählt und für die auf der CD leeren Hüllen (`girlokay`, `guyyeah1`) die englische Grundfassung. Räumt hinterher auf, `--keep` lässt alles stehen. Am Mac (M4 Pro) 50 ms. Ende: `T: --test-content-lang OK — 0 Fehler` |
| `--test-content-fit [--content-shots DIR]` | (an `main_menu.tscn`) **Lesbarkeit** der Seite „Spielinhalte einrichten": baut sie in sechs Profilen (Xperia, iPhone, iPad — je quer und hoch) und beiden Sprachen auf und misst jedes Label und jeden Knopf: abgeschnittener Text, Text unter dem Kartenrahmen, etwas außerhalb der sicheren Fläche, Schrift unter 10 echten Geräte-dp, Tippfläche unter 48 dp. Jeder Verstoß als `FEHLER: …`, geprüft wird zweimal je Profil (Seitenanfang und ans Ende gerollt); mit `--content-shots` je ein Foto `fit-<profil>-oben/unten.png` |
| `--force-no-file-dialog` | tut so, als gäbe es keine native Dateiauswahl — zeigt am Mac den iOS-Weg der Seite („ISO in den Ordner `original/` legen" + „Ordner prüfen") |
| `--fake-update-line` | zeigt die Statuszeile „Aktualisierung geladen — Neustart nötig", ohne dass wirklich ein Paket geladen wurde (Foto-/Layoutprüfung: sie darf über keinem Knopf liegen) |
| `--no-update-check` | keine Versionsabfrage in diesem Lauf |
| `--no-update-pack` | `user://update/current.pck` nicht einhängen (die Fassung aus der APK starten) |
| `--diag` | zusätzlich: EVA-Meldungen und alle 40 Aktualisierungen ein Shroud-Histogramm (auch am Gerät über `adb logcat`) |

Menü-Screenshots: `$G --path game res://scenes/main_menu.tscn --quit-after 200 -- --menu-screenshot /tmp/m.png --page main|skirmish|missions|options|controls|content|log [--select SLUG] [--lang de|en]`.
Der Benachrichtigungs-Abschnitt der Optionen braucht dabei `--notify-demo` (sonst steht er am Schreibtisch nicht im Bild):
`$G --path game res://scenes/main_menu.tscn --quit-after 30000 -- --menu-screenshot /tmp/optionen.png --page options --notify-demo --lang de`.

#### Prüfdaten für die Inhalte-Haken

`gdext/tests/` hat keine Test-ISO, und eine echte CD-ISO ist 650 MB groß. `tools/make_test_content.py`
baut deshalb beides selbst nach `build/testcontent/`: `freeware.zip` (die MIX-Archive aus `content/ra`,
also echte Daten für Atlasbau und Sound-Wandlung) und `allied.iso` — ein winziges ISO-9660-Abbild mit
einer einzigen Datei `MAIN.MIX`, die wiederum ein echtes MIX im C&C-Format mit `movies1.mix` und
`scores.mix` ist. Damit durchläuft der Haken denselben Weg wie am Gerät (`iso_extract` → `extract` →
Abbild löschen). Das `scores.mix` darin ist **echt**: ein Mini-Archiv mit zwei kurzen AUDs aus
`content/ra`, abgelegt unter den Titelnamen `hell226m.aud`/`bigf226m.aud` — damit prüft
`--test-music` am Mac, dass nach dem Einrichten einer CD wirklich die Original-Musik spielt.

```bash
python3 tools/make_test_content.py          # nennt die SHA-1 der Zip
(cd build/testcontent && python3 -m http.server 8124 --bind 127.0.0.1 &)
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --path game --resolution 2560x1096 res://scenes/main_menu.tscn --quit-after 20000 -- \
   --test-content-ui-queue --content-url http://127.0.0.1:8124/freeware.zip --content-sha1 <sha1> \
   --content-cd-url http://127.0.0.1:8124/allied.iso --force-content-locked --dpi 420

# Original-Musik der CD (Toms Handtest 2026-09-06, Punkt 2)
$G --path game res://scenes/main_menu.tscn -- --test-music \
   --content-cd-url http://127.0.0.1:8124/allied.iso

# Haftungsausschluss (Punkt 3)
$G --path game res://scenes/main_menu.tscn -- --test-content-disclaimer \
   --content-url http://127.0.0.1:8124/freeware.zip --content-sha1 <sha1>

# Rollen mit dem Finger (Punkt 1) — braucht keinen Server
$G --path game res://scenes/main_menu.tscn -- --test-touch-scroll --force-content-locked
```

Die Haken `--test-content-ui-cancel` und `-badsum` erwarten einen **leeren** `user://content`-Ordner
(sie prüfen, dass danach nichts installiert ist) — davor also einmal `--test-content-delete` laufen
lassen. `--test-content-ui-error` braucht **keine** `--content-url`: es soll ja gerade eine
unerreichbare Adresse sein.

### App-Protokoll

Das Autoload `AppLog` (`game/scripts/app_log.gd`, in `project.godot` direkt hinter `UpdateBoot`)
schreibt jede Meldung mit Zeitstempel in einen Ringpuffer (400 Zeilen) **und** nach
`user://logs/app.log` (bei 256 KB Rotation nach `app.1.log`). Am Gerät:
`/sdcard/Android/data/…/files/logs/app.log`, am Mac
`~/Library/Application Support/Godot/app_userdata/pocketra/logs/app.log`.

In der App: aufklappbar unten auf der Seite **„Spielinhalte einrichten" → „Protokoll anzeigen"**
(letzte 200 Zeilen, Knopf „Protokoll kopieren" legt sie in die Zwischenablage) — damit ein Fehler
ohne Rechner am Kabel verschickt werden kann. In den Optionen steht seit 2026-09-05 **kein**
Protokoll-Knopf mehr (Toms Wunsch): das Protokoll gehört dorthin, wo die Fehler entstehen. Die
bildschirmfüllende Seite bleibt als Unterseite bestehen und ist für Bilder über
`--menu-screenshot --page log` erreichbar. `AppLog.warn()`/`.error()` rufen zusätzlich
`push_warning()`/`push_error()`, die Zeile steht also weiterhin auch im `adb logcat`.

### Sprachen (Deutsch/Englisch)

Godots `TranslationServer` mit CSV-Tabellen unter `game/i18n/`: `strings.csv` (UI-Texte, Import als
Translation-Ressourcen `strings.de/en.translation`), `actor_names_de.csv` (Einheiten-/Gebäudenamen
wie im deutschen Original „Alarmstufe Rot", Schlüssel = Actor-Kürzel aus `rules.json`; Englisch kommt
direkt aus `rules.json` `display_name` — OpenRAs Originalnamen), `missions_de.csv` (Missionsziele,
Schlüssel = Fluent-Schlüssel aus `mods/ra/fluent/lua.ftl`, Rückfall Englisch). Startsprache aus
`OS.get_locale_language()`, umschaltbar in Optionen → „Sprache: Deutsch/English" (sofort wirksam,
gespeichert in `user://settings.cfg` `[general] language=de|en`), für Prüfläufe per `--lang de|en`.

Die Missionsfilme (`movies1.mix`/`movies2.mix`) liegen auf CD1/CD2 sowohl englisch (`content/ra/`) als
auch deutsch synchronisiert vor (`content/ra_de/`, gitignored, Toms eigene „Alarmstufe Rot"-Ausgabe).
EVA/Einheitenstimmen sind in der deutschen Fassung byteidentisch zur englischen — keine deutsche
Sprachausgabe, deshalb bleibt `speech.mix`/`sounds.mix` bei der englischen Quelle (die deutschen
`sounds.mix` sind außerdem zensiert, Todesschreie ersetzt). Deutsche Filme wandeln:

```bash
python3 tools/vqa2ogv.py --missions --content content/ra_de --out game/assets/video/de
python3 tools/vqa2ogv.py --start 119 --as-name intro --content content/ra_de --out game/assets/video/de prolog
```

`scripts/movie.gd` (`Movie.path(name)`) wählt zur Laufzeit zuerst `game/assets/video/<lang>/<name>.ogv`,
sonst den sprachunabhängigen Originalpfad — genutzt von `intro.gd`, `missions.gd` (`Missions.video`) und
`mission_api.gd` (Movie/Briefing/Win/Loss). Kostet zusätzlich ca. 132 MB im Export (beide Sprachen bleiben
im APK, keine Filterung nach Sprache).

#### Tutorial-Sprachdateien (geklonte EVA-Stimme)

Die Tutorial-Kampagne (`game/scripts/missions/tutorial.gd`) spricht jeden Schritttext beim Anzeigen
mit der geklonten EVA-Stimme (Chatterbox Multilingual, lokal auf MPS — dieselbe Stimme wie die
deutschen EVA-Clips oben, kein Cloud-Dienst). Dateien liegen unter
`game/data/sfx/tutorial/<lang>/<key>.ogg` (`<key>` = derselbe Schlüssel wie in `_build_steps()` und
`game/i18n/missions_tutorial_de.csv`). Sie sind Eigenarbeit ohne EA-Inhalt und liegen deshalb — anders
als alles unter `game/assets/` — **im Git** und im Export beider Presets (`include_filter` enthält
`data/**`); die Verteil-APK ohne EA-Inhalte schließt `assets/sfx/**` aus, `data/**` nicht. Fehlt eine
Datei, bleibt der Schritt lautlos, kein Fehler.

Erzeugung, einmalig Referenz-WAVs (falls `build/voice_ref/de.wav`/`en.wav` fehlen):

```bash
python3 tools/tts_ref.py --lang de build/voice_ref/de.wav
python3 tools/tts_ref.py --lang en build/voice_ref/en.wav
```

Sprech-CSVs aus den Anzeigetexten bauen (Zahlen als Wörter, keine Abkürzungen, Klammerinhalte weg —
Bildschirmtexte bleiben unverändert):

```bash
python3 tools/tts_tutorial_texts.py   # → build/voice_ref/tutorial_de.csv, tutorial_en.csv
```

Sprachdateien erzeugen (`build/.venv_tts`, s. `tools/tts_clone.py`-Kopf für die einmalige
Umgebungseinrichtung; ca. 30–120 s je Satz auf der GPU). **Immer nur EIN Lauf gleichzeitig** — erst
Deutsch komplett, dann Englisch, und ohne parallelen `scons`/Godot-Export (sonst RAM-Absturz):

```bash
build/.venv_tts/bin/python tools/tts_clone.py --lang de --ref build/voice_ref/de.wav \
    --out build/voice_clips/de --csv build/voice_ref/tutorial_de.csv --verify --skip-existing
build/.venv_tts/bin/python tools/tts_clone.py --lang en --ref build/voice_ref/en.wav \
    --out build/voice_clips/en --csv build/voice_ref/tutorial_en.csv --verify --skip-existing
```

Die WAVs bleiben als Arbeitsstand in `build/voice_clips/` (nicht im Git); ins Spiel kommt die
Vorbis-Fassung (mono, `-q:a 4`, `loudnorm` wie die übrigen Stimmen — Homebrews Standard-ffmpeg hat
kein libvorbis, deshalb `ffmpeg-full`). Das `aresample` danach ist kein Beiwerk: `loudnorm` rechnet
intern mit 192 kHz und gibt ohne diesen Schritt auch 192 kHz statt der 24 kHz der Quelle aus (die
Dateien werden dadurch rund die Hälfte größer, ohne mehr zu enthalten):

```bash
for l in de en; do mkdir -p game/data/sfx/tutorial/$l
  for f in build/voice_clips/$l/*.wav; do
    /opt/homebrew/opt/ffmpeg-full/bin/ffmpeg -v error -y -i "$f" \
        -af loudnorm=I=-16:TP=-1.5,aresample=24000 -ac 1 -c:a libvorbis -q:a 4 \
        "game/data/sfx/tutorial/$l/$(basename "${f%.wav}").ogg"
  done
done
```

Bei einer Textänderung in `build/voice_ref/tutorial_*.csv` einzelnen Schlüssel ohne `--skip-existing`
neu erzeugen: `--only SCHLÜSSEL` (danach die eine Datei neu nach `.ogg` wandeln). Läuft ein
Protokolleintrag über 15 % Wortfehlerrate (`SOLL:`/`IST:` im Log), mit einem anderen Seed wiederholen
(`--only SCHLÜSSEL --seed N`) oder den Text in der CSV kürzen/vereinfachen.

### Android bauen und installieren

APKs entstehen **über `tools/apk_build.sh`** (Toms Regel): das Skript baut in einem eigenen
Arbeitsbaum aus einem sauberen Commit, spiegelt die erzeugten Daten, baut die Extension, importiert,
exportiert und prüft die fertige APK.

```bash
tools/apk_build.sh                                   # aus master, Preset „Android" (Vollfassung, bleibt bei Tom)
tools/apk_build.sh --dist                            # Verteil-APK ohne EA-Inhalte — DIESE wird verteilt
tools/apk_build.sh --ref feature/xyz --wt apk-xyz    # aus einem Zweig, eigener Arbeitsbaum
tools/apk_build.sh --no-gradle                       # Notausgang, s. unten
tools/apk_build.sh --install                         # dazu: adb install + starten
```

**Weitergegeben wird ausschließlich die Verteil-APK** (Toms Regel 2026-09-09: „Wir verteilen auch
keine Vollfassung mehr, nur noch die `-dist`-Variante, um uns nicht angreifbar zu machen"). Grund:
die Vollfassung trägt die EA-Inhalte in der APK, und die liefern wir niemandem aus. Das Preset
„Android" und der Lauf **ohne** `--dist` bleiben trotzdem bestehen — er erzeugt
`build/pocketra-full.apk` für Toms eigenen Gebrauch, für den Größenvergleich in der Tabelle unten
und für Prüfläufe. Auf den Server (`tools/update_pack.sh --upload`) geht nur
`build/pocketra-dist.apk`, dort unter dem Namen `pocketra.apk`.

**Seit 2026-09-09 läuft der Export über den Gradle-Bau** (`gradle_build/use_gradle_build=true` in
den Presets „Android" und „Android Verteilung"; die Update-Paket-Presets bleiben unberührt). Grund:
nur so kommt das Benachrichtigungs-Plugin `pocketra_plugin` (Android-Plugin-Format v2) in die APK.
Godot setzt die APK dann aus der Bauvorlage `game/android/build/` selbst zusammen, statt eine
vorgefertigte Vorlage zu befüllen. `tools/apk_build.sh` erledigt dafür zwei Dinge von selbst: es baut
mit `tools/plugin_build.sh` die Plugin-AAR (die liegt **nicht** im Git und fehlte im
Arbeitsbaum sonst) und installiert die Bauvorlage, wenn sie fehlt.

Was das dauerhaft ändert:

| | vorher | jetzt |
|---|---|---|
| `minSdkVersion` der APK | 24 | **29** (Godot setzt das beim Gradle-Bau selbst; Android 10 aufwärts) |
| APK-Größe (gleicher Commit) | 206,7 MB | **264,8 MB** — gleicher Inhalt, nur liegen die nativen Bibliotheken jetzt unkomprimiert darin (schnellerer Start, weniger belegter Speicher auf dem Gerät) |
| Dauer | ~2 min | erster Lauf mehrere Minuten (Gradle lädt), danach ~3–4 min |
| Voraussetzung | Export-Templates | zusätzlich JDK 17, Android SDK, beim ersten Lauf Netz |

Klemmt der Gradle-Bau, baut `tools/apk_build.sh --no-gradle` weiter wie früher — dann fehlen nur die
Benachrichtigungen. Die Ursachen und ihre Abhilfe stehen in `docs/MULTIPLAYER.md` §10.5.

Voraussetzungen (einmalig, bereits erledigt): Godot-Export-Templates 4.7.2 unter
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`, in den Godot-Editor-Einstellungen
`export/android/java_sdk_path` auf JDK 17, `export/android/android_sdk_path` auf
`~/Library/Android/sdk` und `debug_keystore` auf `~/.android/debug.keystore`.

Für den **Emulator** muss die App mit `--rendering-driver opengl3` laufen (in `export_presets.cfg` unter
`command_line/extra_args`); sein Software-Vulkan liefert nur einen schwarzen Bildschirm. Für echte Geräte
bleibt das Preset auf Vulkan/Mobile.

### iOS/iPadOS bauen und aufspielen

```bash
tools/ipa_build.sh             # Extension + Export + Signierung, Ergebnis build/ios/pocketra.ipa
tools/ipa_build.sh --install   # zusätzlich aufs angeschlossene iPad spielen und starten
tools/ipa_build.sh --release   # Release-Bau (Extension ebenfalls target=template_release)
tools/ipa_build.sh --unsigned  # nur Bauprüfung (ohne Signierung, läuft auf keinem Gerät)
```

Was das Skript nacheinander macht (einzeln von Hand):

```bash
cd gdext && scons platform=ios arch=arm64 target=template_debug -j10   # → game/bin/librasim.ios.xcframework
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --export-debug iOS ../build/ios/pocketra.ipa                      # → build/ios/pocketra.xcodeproj + pocketra.pck
xcodebuild -project build/ios/pocketra.xcodeproj -scheme pocketra \
    -configuration Debug -destination 'generic/platform=iOS' \
    -archivePath build/ios/pocketra.xcarchive -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=9HW65ZP3L9 archive
xcodebuild -exportArchive -archivePath build/ios/pocketra.xcarchive \
    -exportOptionsPlist build/ios/pocketra/export_options.plist -exportPath build/ios
```

Das exportierte Projekt ist bereits auf automatische Signierung eingestellt
(`CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 9HW65ZP3L9`, `PRODUCT_BUNDLE_IDENTIFIER =
dev.tom.pocketra`). Statt der xcodebuild-Zeilen geht deshalb auch: `open build/ios/pocketra.xcodeproj`,
oben das angesteckte iPad als Ziel wählen und ⌘R — Xcode fragt dabei nach der Apple-ID und trägt das
Gerät selbst ins Profil ein.

Aufspielen und starten (Gerät per Kabel, einmal „Diesem Computer vertrauen"):

```bash
xcrun devicectl list devices                       # Kennung des iPads ablesen
xcrun devicectl device install app --device <KENNUNG> \
    build/ios/pocketra.xcarchive/Products/Applications/pocketra.app
xcrun devicectl device process launch --device <KENNUNG> dev.tom.pocketra
```

### iOS: TestFlight

Das Gegenstück zu `tools/update_pack.sh --upload` auf der Android-Seite ist derselbe Skriptaufruf mit
einer anderen Fahne — der ganze Weg vom Quelltext bis in App Store Connect läuft in einem Kommando:

```bash
tools/ipa_build.sh --store       # Release + App-Store-Signierung, Ergebnis build/ios/pocketra.ipa
tools/ipa_build.sh --validate    # dasselbe, danach von Apple vorprüfen lassen (kein Upload)
tools/ipa_build.sh --upload      # dasselbe, vorprüfen UND zu TestFlight hochladen
tools/ipa_build.sh --upload-only # nur die vorhandene .ipa erneut hochladen (nach Netzabbruch)
```

Unterschiede zum Gerätebau: `--store` baut in der Konfiguration `Release` (die Extension dabei mit
`target=template_release`), schreibt ein eigenes `build/ios/store_options.plist` mit
`method = app-store-connect` statt Godots `development`-Fassung und zählt vorher die Buildnummer
hoch. Der Store verlangt ein Zertifikat **„Apple Distribution"** und ein **App-Store**-Profil statt
der Entwicklungspapiere; beides legt `xcodebuild -allowProvisioningUpdates` selbst an, sobald es sich
anmelden kann.

**Buildnummer.** TestFlight nimmt jede `CFBundleVersion` nur ein einziges Mal an. Der Store-Modus
erhöht darum `application/version` im Preset „iOS" vor jedem Bau um eins (mit `--no-bump`
abschaltbar) und gibt die neue Zahl aus — die Änderung an `game/export_presets.cfg` gehört in den
Commit. Die sichtbare Fassung `application/short_version` (z. B. `0.13`) bleibt unberührt und wird
wie bisher von Hand gepflegt.

**Einmalige Einrichtung** (verlangt Apples Weboberfläche, lässt sich nicht automatisieren):

1. **App anlegen.** App Store Connect → Apps → „+“ → neue App mit genau der Bundle-ID aus dem Preset.
   Die Bundle-ID muss vorher unter *Certificates, Identifiers & Profiles* als Identifier eingetragen
   sein.
2. **API-Schlüssel erzeugen.** App Store Connect → Benutzer und Zugriff → Integrationen → App Store
   Connect API → Schlüssel mit der Rolle „App Manager". Die `.p8`-Datei gibt es **genau einmal** zum
   Herunterladen. Ablegen unter `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` (`chmod 600`) —
   dort sucht `altool` von selbst.
3. **Zugang eintragen** in `build/ios-upload.conf` (gitignored, `build/` liegt ganz außerhalb von
   Git):

   ```
   ASC_KEY_ID=ABCD123456
   ASC_ISSUER_ID=11111111-2222-3333-4444-555555555555
   # ASC_KEY_PATH=…   optional, sonst der Standardpfad oben
   ```

Ohne diesen Schlüssel laufen `--validate`/`--upload` gar nicht erst los; `--store` baut auch ohne ihn
eine .ipa, die man von Hand über Transporter.app hochladen kann.

**Prüfung durch Apple.** Interne Tester (bis 100 Mitglieder des eigenen Teams) bekommen den Build
ohne Beta App Review, meist wenige Minuten nach dem Upload. Externe Tester und der öffentliche
TestFlight-Link durchlaufen eine Prüfung durch Apple. Dafür gilt dieselbe Linie wie für die Website:
keine fremden Inhalte mitliefern. Das Preset „iOS" packt derzeit `assets/**` vollständig ein, also
auch Musik, Filme und Sprachdateien aus dem Original — für den Weg über Apple braucht es zuerst ein
schlankes Preset analog „Android Verteilung".

Besonderheiten gegenüber Android:

- **Statische Bibliothek statt `.so`.** Godots Export-Plugin bindet eine GDExtension auf Apple-Geräten
  nur ein, wenn der Pfad in `game/bin/rasim.gdextension` auf `.a` oder `.xcframework` endet (Godot,
  `editor/export/gdextension_export_plugin.h`) — ein `.dylib` würde nur mitkopiert und nie geladen.
  `gdext/SConstruct` baut für `platform=ios` deshalb eine statische Bibliothek, verschmilzt sie per
  `libtool` mit `libgodot-cpp.ios.*.a` und packt beides mit `xcodebuild -create-xcframework` nach
  `game/bin/librasim.ios.xcframework`.
- **Signierung** läuft automatisch über Xcode mit der Identität „Apple Development: tom@attomic.de
  (HF45S99Z5G)" aus dem Schlüsselbund. **Die Klammer im Zertifikatsnamen ist nicht die Team-ID** — die
  steht im Zertifikat als `OU=9HW65ZP3L9` (Tom Göckeritz). Mit `HF45S99Z5G` als `DEVELOPMENT_TEAM`
  bricht `xcodebuild` mit „No Account for Team" ab; mit `9HW65ZP3L9` greift das vorhandene Sammelprofil
  „iOS Team Provisioning Profile: *" (`9HW65ZP3L9.*`), das `dev.tom.pocketra` mit abdeckt.
  `tools/ipa_build.sh --unsigned` baut zur reinen Bauprüfung auch ohne Signierung durch.
- **Gerät registrieren:** ein Entwicklungsprofil gilt nur für die darin eingetragenen Geräte
  (`security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision`
  zeigt sie). Steht das iPad nicht drin, muss es Xcode aufnehmen — dafür die Apple-ID in
  **Xcode → Settings → Accounts** anmelden, das iPad anstecken, „Diesem Computer vertrauen" und
  `tools/ipa_build.sh --install` (bzw. einmal ⌘R aus Xcode) laufen lassen.
- **Name auf dem Startbildschirm:** kommt aus `project.godot` — `application/config/name` =
  „PocketRA". Seit der Umbenennung am 2026-09-09 ist der Name sprachneutral, `config/name_localized`
  ist entfallen; Godots iOS-Export schreibt daraus `INFOPLIST_KEY_CFBundleDisplayName="PocketRA"` ins
  Xcode-Projekt. `tools/ipa_build.sh` setzt den Namen weiterhin **nicht** selbst — eine feste
  `INFOPLIST_KEY_CFBundleDisplayName`-Zeile auf der xcodebuild-Zeile würde den Wert aus dem Projekt
  überschreiben.
- **Nutzerordner:** `config/use_custom_user_dir=true` mit `custom_user_dir_name` =
  `Godot/app_userdata/pocketra` (bis zur Umbenennung `…/redalert`). Auf **Mac, Windows und Linux**
  schiebt `UpdateBoot._migrate_user_dir()` den Inhalt des alten Ordners beim ersten Start der neuen
  Fassung einmalig hinüber, sonst wären Einstellungen, Protokolle und die ausgelesenen Originaldaten
  unter `user://original/` scheinbar verschwunden. Auf **iOS** greift weder die Einstellung noch die
  Übernahme: Godots Apple-Embedded-Fassung von `OS::get_user_data_dir()` liefert immer das
  Dokumente-Verzeichnis der App im Sandkasten. Weil die Bundle-ID mitgewechselt hat
  (`dev.tom.redalert` → `dev.tom.pocketra`), ist das aber ein **anderer** Sandkasten: die Fassung mit
  dem neuen Namen startet auf dem iPad ohne Spielstände und ohne `original/`, die alte App bleibt
  daneben stehen. Beim ersten Handtest einplanen, die Originaldateien erneut über die Dateien-App
  hineinzulegen.
- **Originaldateien** (Freeware-ISO, MIX-Archive) legt man über die Dateien-App in
  „Auf meinem iPad → PocketRA → original/" — das Preset setzt
  `user_data/accessible_from_files_app` und `accessible_from_itunes_sharing`; Godot schreibt daraus
  `LSSupportsOpeningDocumentsInPlace` und `UIFileSharingEnabled` ins `Info.plist` (in der gebauten
  `pocketra.app` mit `plutil -p .../Info.plist` nachprüfbar). Ohne diese beiden Schlüssel taucht der
  Ordner in der Dateien-App gar nicht erst auf.
- **Freeware-Inhalte auf iOS — der Weg trägt, hat aber offene Stellen** (geprüft 2026-09-09, am
  Gerät ungeprüft). Der Kern ist plattformneutral und in Ordnung: `HTTPRequest` lädt über **https**
  nach `user://` (ATS spielt keine Rolle, Godot geht über eigene Sockets mit mbedTLS), `ZIPReader`
  entpackt ohne Unterprozess, ISO und MIX liest die Extension mit `fopen`/`fread` gestreamt, und im
  ganzen `game/` gibt es genau **einen** `OS.execute`-Aufruf (`df -k`), der schon auf Desktop
  eingegrenzt ist. Behoben in derselben Runde: die **Speicherplatzprüfung** stieg auf iOS mit einem
  frühen `return -1` aus, begründet mit „iOS erlaubt keine Unterprozesse" — das stimmt, traf aber die
  falsche Zeile und schnitt den einzigen Weg ab, der dort funktioniert (`RaContent::free_space()` ist
  reines POSIX `statvfs`). Folge war: „Speicherplatz lässt sich hier nicht prüfen" und jeder
  650-MB-Download lief auch auf ein volles Gerät. Was **noch offen** ist, in der Reihenfolge, in der
  es weh tut:

  1. **Die eigene ISO wird nach dem Import gelöscht.** `ContentManager.is_own_file()` erkennt „von
     uns angelegt" daran, dass der Pfad unter `OS.get_user_data_dir()` liegt — auf iOS liegt dort
     zwangsläufig *jede* Datei, auch die, die der Nutzer per Dateien-App hineinkopiert hat. Der
     Kartentext verspricht das Gegenteil („Deine eigene Datei bleibt unverändert liegen").
  2. **Den Ordner `original/` legt niemand an**, es gibt nur Existenzprüfungen. In der Dateien-App
     ist er deshalb gar nicht zu sehen, der Nutzer muss ihn selbst anlegen.
  3. **Der Hinweistext nennt den Ort nicht.** Angezeigt wird nur `original/`, nicht „Dateien-App →
     Auf meinem iPhone → PocketRA → original/"; dass auch der Wurzelordner durchsucht wird, steht
     nirgends.
  4. **Jede lokale Datei gilt als „allied".** Wer die deutsche CD hineinlegt, bekommt weder die
     Sprachdateien noch `REDALERT.MIX`.
  5. **Das Freeware-ZIP lässt sich lokal nicht einlesen** — der Ordner-Scan nimmt nur `iso`/`mix`.
     Ohne Netz gibt es auf iOS also gar keinen Weg.
  6. **Kein `screen_set_keep_on()` während des Downloads.** `HTTPRequest.download_file` kann nicht
     fortsetzen; auf iOS friert der Sperrbildschirm die Threads ein, und die 650 MB fangen bei 0 an.
  7. **`user://` wird auf iOS in iCloud gesichert.** Für den Store gehören nachladbare Inhalte dort
     nicht hin (`NSURLIsExcludedFromBackupKey`); Godot bietet dafür nichts, es wäre ein kleiner
     Zusatz in der Extension.

- **Inhalte-Seite ohne Dateiauswahl.** `DisplayServer.file_dialog_show` ist auf iOS nicht
  implementiert, `DisplayServer.FEATURE_NATIVE_DIALOG_FILE` meldet dort aber trotzdem nichts
  Verlässliches — `content_page.gd::_native_dialog_available()` schaltet deshalb bei
  `OS.get_name() == "iOS"` fest ab. Statt „Datei wählen" zeigt die Karte den Ordnerweg `original/`
  und den Knopf „Ordner prüfen", der `pick_folders()` (auf iOS `OS.get_user_data_dir()`, also der
  Dokumente-Ordner der App) nach ISO-/MIX-Dateien durchsucht. Am Mac lässt sich derselbe Weg mit
  `--force-no-file-dialog` ansehen.
- **Mehrspieler über WebSocket** braucht auf iOS keinen Eintrag in der `Info.plist`. Der Standardserver
  steht in `game/scripts/net/net_client.gd` als `wss://redalert.attomic.de/mp` — TLS, und Apples App
  Transport Security erlaubt TLS-Verbindungen ohne Ausnahme (geblockt wäre nur Klartext, also `ws://`
  oder `http://`). Godots `WebSocketPeer` geht ohnehin über eigene Sockets mit mbedTLS und nicht über
  `NSURLSession`, für die ATS überhaupt gilt. In der gebauten `pocketra.app` steht deshalb — geprüft mit
  `plutil -p …/Info.plist` — **kein** `NSAppTransportSecurity`-Block, und es fehlt auch nichts: es gibt
  keine Netz-Berechtigung, die eine iOS-App vorher anfordern müsste (anders als der macOS-Sandkasten).
  Nur wer zum Prüfen einen eigenen Server ohne TLS einträgt (`--mp-url ws://…` oder
  `user://settings.cfg [multiplayer] url`), braucht dafür eine ATS-Ausnahme.
- **Mikrofon/Sprechfunk auf iOS** braucht zwei Einträge, die **nicht** im Code stehen und sich per
  Aktualisierungspaket auch nicht nachtragen lassen (docs/MULTIPLAYER.md §11.3a):
  `audio/general/ios/session_category=2` in `game/project.godot` — Godots Vorgabe ist „Ambient", und
  damit erlaubt die AVAudioSession gar keine Aufnahme; sowie
  `privacy/microphone_usage_description` (**englisch**, landet in `Info.plist` und
  `en.lproj/InfoPlist.strings`) plus `privacy/microphone_usage_description_localized` (Wörterbuch
  Sprache → Text, hier steht **Deutsch**) im Preset „iOS". Ohne `NSMicrophoneUsageDescription`
  **beendet iOS die App** beim ersten Zugriff auf den Eingang — ohne Dialog, ohne Fehlerzeile.
  Beides ist eingetragen, aber **am Gerät ungeprüft**.
  Der Android-Fehler mit den fest verdrahteten 44 100 Hz gilt auf iOS **nicht**: Godots Apple-Treiber
  nimmt die Geräterate (`capture_mix_rate = [AVAudioSession sharedInstance].sampleRate`,
  `drivers/coreaudio/audio_driver_coreaudio.mm`). Das eigene Aufnahme-Plugin gibt es dort nicht und
  wird auch nicht gebraucht — auf iOS gilt der Engine-Weg. Eine **verweigerte** Freigabe meldet iOS
  nicht, es liefert Stille; abfragen lässt sie sich aus GDScript nicht
  (`OS.request_permission()` ist Android-only). Die Diagnosezeile sagt deshalb dort „Freigabe
  unbekannt" statt wie früher „Freigabe ja", und die Meldung bei durchgehend Null schickt auf iOS
  zuerst in „Einstellungen → PocketRA → Mikrofon".

- Das Preset „iOS" ist die **Entwicklerfassung** (alle Inhalte im Paket, wie „Android"); eine schlanke
  Verteilfassung analog „Android Verteilung" gibt es noch nicht. **Nebenwirkung, die beim Prüfen
  stört:** weil `assets/**` mit im Paket liegt, hält `ContentManager.dev_bundled()` jede iOS-Fassung
  für die Vollfassung — der Knopf „Freeware-Inhalte einrichten" ist auf dem Gerät deshalb gar nicht
  sichtbar und der ganze Einrichtungsweg nur mit `--force-content-locked` erreichbar.

- **Signaturkonflikt beim ersten Bau** („pocketra has conflicting provisioning settings … automatically
  signed for development, but a conflicting code signing identity Apple Distribution has been manually
  specified"). Das passiert jedem beim ersten `tools/ipa_build.sh --release`/`--store`, und die
  Xcode-Meldung führt in die Irre: sie rät, es im Build-Settings-Editor umzustellen — bei einem
  Projekt, das Godot bei **jedem** Export neu erzeugt, ist das die falsche Stelle, die Änderung wäre
  beim nächsten Lauf wieder weg. Ursache am Godot-Quelltext
  (`editor/export/editor_export_platform_apple_embedded.h`, `struct CodeSigningDetails`):

  ```cpp
  release_signing_identity = p_preset->get("application/code_sign_identity_release")
          .operator String().is_empty() ? "Apple Distribution" : p_preset->get(…);
  release_manual_signing = !release_provisioning_profile_uuid.is_empty()
          || (release_signing_identity != "Apple Development" && release_signing_identity != "Apple Distribution");
  ```

  Ist das Preset-Feld **leer** (unser Fall = automatische Signierung), setzt Godot wörtlich
  `CODE_SIGN_IDENTITY = "Apple Distribution"` in die Release-Konfiguration, lässt
  `CODE_SIGN_STYLE` aber auf `Automatic` — und genau diese Mischung weist Xcode ab.
  Abgestellt an **zwei** Stellen, beide gewollt:
  1. `application/code_sign_identity_release="Apple Development"` im Preset. Die Abfrage oben lässt
     genau diesen Wert zu, **ohne** auf `Manual` umzuschalten — das erzeugte Projekt ist damit von
     sich aus stimmig, und `open build/ios/pocketra.xcodeproj` + ⌘R bzw. Product → Archive aus Xcode
     heraus geht wieder. Das ist die eigentliche Reparatur.
  2. `CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"` auf der xcodebuild-Zeile in
     `tools/ipa_build.sh` — greift auch dann, wenn jemand das Preset in Godots Export-Fenster wieder
     leer speichert.

  **Mit Entwicklungsidentität archivieren ist richtig, nicht ein Notbehelf:** erst der Export
  (`-exportArchive` mit `method: app-store-connect` und `signingStyle: automatic`, den schreibt das
  Skript im `--store`-Zweig ohnehin selbst) signiert auf das Verteilzertifikat um. Der Zweig
  `--unsigned` ist unberührt: er baut Debug und setzt `CODE_SIGNING_ALLOWED=NO`, das schlägt beides.
- **Aktualisierung über den Server (seit 2026-09-09 plattformabhängig).** Der Server liefert
  `pocketra.apk` (Android), `pocketra-windows-setup.exe` (NSIS-Installer) und `pocketra-macos.dmg`
  (Ziehen-in-Programme-Fenster), aber **keine `.ipa`** — eine neue iOS-Fassung geht nur über Xcode
  oder TestFlight. Bis dahin bekam auch das iPad „Neue App-Version" gemeldet und einen Knopf, der
  den Browser auf eine **APK** schickte; greift `min_supported`, war genau dieser Knopf der einzige
  angebotene Ausweg (Toms Befund: „Die Info mit der neuen Android Version kommt auch bei IOS. Das
  ist natürlich Quark."). Jetzt entscheidet `UpdateConfig.app_choice()` zuerst nach der Plattform:

  | Plattform | verglichen wird gegen | Knopf führt auf |
  |---|---|---|
  | Android | `apk_version` | `apk_url` (Voll-/Verteilfassung wie bisher über `apk_choice()`) |
  | Windows | `apk_version` | `windows_url` — das Feld schreibt `tools/update_pack.sh` längst, gelesen wurde es bis dahin nie |
  | macOS | `apk_version` | `mac_url` — dieselbe Lücke wie bei Windows, seit 2026-09-09 mit der DMG geschlossen |
  | iOS | `ios_version` | `ios_url` (TestFlight/App Store) |
  | Linux | `apk_version` | `apk_url` (kein eigener Build, Rückfall wie bisher) |

  `ios_version`/`ios_url` schickt der Server heute **nicht** — dann bleibt die iOS-App still: kein
  Fenster, keine Statuszeile, kein Knopf. Das ist die richtige Antwort, weil es für dieses Gerät
  nichts zu holen gibt. Sobald Tom eine TestFlight-Einladung hat, trägt er die beiden Felder von
  Hand in `version.json` ein und derselbe Weg meldet sie, **ohne** neue IPA. Die **Sperrseite**
  (`min_supported`, `disabled`) wirkt auf iOS unverändert — nur ohne APK-Knopf, mit dem Text
  „Auf iPhone und iPad kommt die neue Fassung über TestFlight oder Xcode" (`update.blocked_ios`)
  und ohne „Beenden" (wie im Hauptmenü auf Android/iOS).

- **Das Inhaltspaket ist auf iOS abgeschaltet** (Vorgabe, umschaltbar). Apples App Review Guideline
  **2.5.2** verbietet nachgeladenen Code, der Funktionen einführt oder ändert — ein `update.pck`
  besteht fast nur aus GDScript. Abwägung, Wortlaut, Quellen und die drei möglichen Wege stehen in
  **`docs/IOS-PAKET.md`**; die Kurzfassung: auf einem einzigen iPad neben dem Mac, der die IPA baut,
  bringt das Paket keinen Nutzen, das Risiko schlägt aber erst bei der Store-Einreichung zu.
  Der Schalter greift an **zwei** Stellen (Laden und Einhängen):

  ```ini
  # user://settings.cfg   →  ~/Library/Application Support/Godot/app_userdata/pocketra/settings.cfg
  [update]                #     bzw. auf dem Gerät im Dokumente-Ordner der App
  pack=true
  ```

  Dazu `-- --update-pack on|off` für Prüfläufe. **Nicht** abgeschaltet ist die Abfrage selbst: der
  Notschalter `disabled`, die Sperre und der Hinweis auf eine neue Fassung wirken auf dem iPad
  weiter, nur das Nachladen unterbleibt (`UpdateService._handle_version()`, Schritt 2a).
  Neustart bietet die App auf iOS ohnehin nicht an (`UpdateConfig.restart_supported()`).

### Windows bauen (vom Mac aus)

Toms Wunsch (2026-09-06): „Eine Windows-Version brauchen wir auch." Ein Aufruf macht alles —
Extension kreuzübersetzen, exportieren, verpacken:

```bash
brew install mingw-w64        # einmalig
brew install makensis         # einmalig, nur für --dist (NSIS-Installer)
tools/win_build.sh            # Vollfassung (Toms Entwicklerstand), oder --no-ext, wenn die DLL steht
tools/win_build.sh --dist     # Verteilfassung ohne EA-Inhalte — DIESE geht nach GitHub/Server
```

Ohne `--dist` Ergebnis `build/pocketra-windows.zip` mit genau drei Dateien: `pocketra.exe`,
`pocketra.pck` und `librasim.windows.x86_64.dll` — alle drei müssen **im selben Ordner** liegen;
entpacken und die EXE starten, mehr ist nicht nötig (Toms eigener Rechner, kein Installationsvorgang
nötig). Windows 10 oder neuer, x86-64.

Mit `--dist` Ergebnis stattdessen `build/pocketra-windows-dist.exe`, ein **richtiger NSIS-Installer**
(Toms Wunsch 2026-09-09: „eine exe Datei als Download statt zip", Vorlage
`tools/win_installer.nsi.tmpl`, cross-kompiliert per `makensis` — kein Windows/Wine nötig): Zielordner
wählen, Startmenü-Eintrag, Deinstallation über Windows' „Apps"-Liste.

Ohne `--dist` ist es die **Vollfassung** (Export-Preset „Windows", derselbe Umfang wie das Preset
„Android"): Atlanten, Sound- und Stimmeffekte, beide Sprachfassungen der Missionsfilme und die Musik
stecken mit im Paket. Sie ist Toms **Entwicklerstand** zum Spielen und Prüfen am PC und geht nicht an
Fremde. Mit `--dist` (Preset „Windows Verteilung") gilt dieselbe Auflage „Verteilung ohne EA-Inhalte"
(project-docs, Decisions) wie für die Verteil-APK — Atlanten/Sound/Filme fehlen, die App lädt sie zur
Laufzeit über „Spielinhalte einrichten" nach.

### macOS bauen (Verteilfassung)

Es gibt keine Mac-Vollfassung — Tom entwickelt/prüft direkt aus dem Quellbaum (s. o. „Spiel am Mac
starten und prüfen"). `tools/mac_build.sh` baut ausschließlich die **Verteilfassung** (Preset
„macOS", ohne EA-Inhalte wie Android/Windows), signiert sie mit dem Developer-ID-Zertifikat und
reicht sie bei Apple zur Notarisierung ein — ohne Notarisierung blockt Gatekeeper die App auf jedem
anderen Mac als diesem:

```bash
brew install create-dmg           # einmalig — baut das Ziehen-in-Programme-Fenster
tools/mac_build.sh                # Extension + Export + signieren + notarisieren + DMG
tools/mac_build.sh --no-ext       # nur Export + signieren (Extension bleibt, wie sie ist)
tools/mac_build.sh --no-notarize  # nur Bauprüfung, läuft NUR auf diesem Mac
```

Ergebnis `build/pocketra-macos.dmg`: `PocketRA.app` plus eine Verknüpfung auf `/Applications` im
klassischen „Standardfenster" zum Reinziehen (Toms Wunsch 2026-09-09, per `create-dmg`) — sowohl die
App als auch die DMG selbst sind notarisiert und gestapelt. Einmalige Einrichtung (Zertifikat ist
schon vorhanden) und alle Einzelheiten stehen im Kopf des Skripts — u. a. das Notarisierungs-Profil
im Schlüsselbund (`xcrun notarytool store-credentials`, braucht ein App-spezifisches Passwort, das
niemand außer Tom selbst eintragen kann). `create-dmg` steuert den Finder per AppleScript und braucht
darum eine angemeldete grafische Sitzung. Bekannte Lücke: die App läuft nur auf Apple-Silicon-Macs
(die eigene GDExtension ist arm64-only), ein Intel-Mac bricht beim Laden der Erweiterung ab.

**Bedienung mit Maus und Tastatur.** Das Spiel ist für Finger gebaut; Godot erzeugt aus jedem
Mausklick einen echten Fingertipp (`project.godot`: `input_devices/pointing/emulate_touch_from_mouse`),
also funktionieren Auswahl, Ziehen und Langdruck (Maustaste gedrückt halten) ohne Zusatzcode. Was
die Emulation **nicht** liefert, ist alles jenseits der einen Maustaste: ein Touchpad-Wisch erzeugt
gar keine Berührung, ein Mausrad auch nicht. Diese Lücke und die Tasten, für die es am Handy keine
Entsprechung gibt, stecken in `game/scripts/desktop.gd` (`--test-keys`, `--test-desktop-scroll`):

| Eingabe | Wirkung |
|---|---|
| Touchpad, zwei Finger | Karte verschieben (`InputEventPanGesture`). Richtung wie die Systemeinstellung: der Inhalt folgt den Fingern |
| Mausrad, Rad-Kippen | Karte senkrecht bzw. waagerecht verschieben (60 dp je Rasterstufe; Präzisionsräder skalieren über `factor`) |
| `Strg`/`Cmd` + Mausrad, Aufziehen | Zoom **um den Mauszeiger** — der Weltpunkt darunter bleibt stehen |
| Zeiger am Fensterrand | Randscrollen: 12 dp Randstreifen, eine Bildschirmbreite in 1,5 s, Ecken diagonal. Nur mit Fensterfokus und nur, solange der Zeiger im Fenster steht |
| Pfeiltasten, `W` `A` `S` `D` | dasselbe Scrollen über die Tastatur (physische Tastenlage, also auf jeder Belegung dieselben vier Tasten) |
| `Esc` | eine Stufe zurück — offenen Zustand schließen, sonst Pausenmenü (dieselbe Kette wie die Android-Zurücktaste) |
| `F11`, `Alt`+`Enter` | Vollbild; steht auch als Schalter „Vollbild" in den Optionen (nur am Desktop) und wird in `user://settings.cfg` gemerkt |
| `1` – `5` | Kontrollgruppe wählen, `Strg`+Zahl zuweisen, zweimal dieselbe Zahl = Kamera zur Gruppe (am Handy die Spalte links) |

Vorbild für Rand-, Rad- und Tastenscrollen ist OpenRAs `ViewportControllerWidget`
(`OpenRA.Mods.Common/Widgets/ViewportControllerWidget.cs`: `CheckForDirections`, `HandleMouseInput`,
`ScrollUp/Down/Left/RightKey`). Es gibt bewusst **keinen** neuen Schalter dafür. Nicht gescrollt
wird, solange das Pausenmenü, ein Dialog, die Chatzeile oder ein Film oben liegt; Rand- und
Tastenscrollen ruhen zusätzlich während eines Auswahlrahmens (der bringt seinen eigenen Randlauf
mit), einer Bauvorschau und eines offenen Radialmenüs, und eine Eingabezeile im Fokus schluckt
W-A-S-D. Über einem HUD-Element hält das Randscrollen an — in den letzten 2 dp an der echten
Fensterkante läuft es trotzdem, damit es wie in OpenRA am **ganzen** Fensterrand gilt. Die
Kartengrenzen klemmen genau wie beim Fingerziehen (`ProtoWorld._clamp_camera`). Am Handy ist der
ganze Knoten abgeschaltet — dort schwenken weiterhin zwei Finger.

Im Hauptmenü gibt es zusätzlich den Eintrag „Beenden", der auf Android/iOS fehlt.

**Maßstab am Desktop: die kurze Fensterseite ist 520 dp.** Ein Handy hat eine feste Bildschirmgröße,
dort ist die Pixeldichte das richtige Maß. Ein Fenster am PC ändert seine Größe, der Bildschirm
bleibt derselbe — wer aus einem 1280 × 720-Fenster ins Vollbild geht, erwartet dasselbe Bild, nur
größer. `game/scripts/dp.gd` rechnet deshalb auf Windows/macOS/Linux `px/dp = kurze Fensterseite /
520` (Grenzen 0,75 und 4,5); bei 1280 × 720 kommt genau derselbe Wert heraus wie mit der alten
Handy-Rechnung, größere Fenster wachsen proportional mit. Android, iOS und jeder Lauf mit
vorgegebener Pixeldichte (`--dpi`, Prüfmatrix) rechnen unverändert nach der Pixeldichte.

Ändert sich die Fenstergröße (F11, Optionen → Vollbild, Ziehen am Rahmen), sammelt
`Desktop.Resizer` die `size_changed`-Ereignisse ein, wartet 0,15 s auf Ruhe und baut dann neu auf:
das **Hauptmenü** komplett (`_rebuild_ui`), das **Spielfeld-HUD** über `HudTheme.rescale_tree()` —
das zieht Schriftgrößen, Rahmenstärken, Eckenradien und Mindestgrößen im Verhältnis alt zu neu nach,
weil sie beim Aufbau einmal aus `Dp.px()` gerechnet und in Theme-Overrides gelegt werden. Zum Prüfen
am Mac:

```bash
$G --path game --resolution 1280x720 res://scenes/main_menu.tscn --quit-after 600 -- \
   --resize 2560x1440 --menu-screenshot /tmp/m.png --page main
$G --path game --resolution 1280x720 res://scenes/gesture_proto.tscn --quit-after 3000 -- \
   --map keep-off-the-grass-2 --ai 1 --resize 2560x1440 --screenshot /tmp/f.png --screenshot-at 200
```

| Haken | Wirkung |
|---|---|
| `--resize BREITExHÖHE` | Fenstergröße **mitten im Lauf** ändern, nachdem die Seite gebaut ist — der Weg, den Vollbildwechsel nachzustellen |
| `--fullscreen` | dasselbe über den echten Vollbildmodus (ohne die Einstellung in `settings.cfg` zu merken). Ein Lauf **ohne Fensterfokus** meldet am Mac zwar `WINDOW_MODE_FULLSCREEN`, macOS zieht das Fenster aber nicht auf — für automatische Prüfungen deshalb `--resize` nehmen |

**Was am Mac geprüft werden kann und was nicht.** Ohne Windows-Rechner gibt es **keine
Laufzeitprüfung** — weder Start noch Spielverlauf sind belegt. Nachweisbar ist am Mac nur, dass die
DLL nichts vom Zielrechner erwartet, was dort nicht ohnehin liegt:

```bash
x86_64-w64-mingw32-objdump -p game/bin/librasim.windows.x86_64.dll | grep 'DLL Name'
```

Erlaubt sind `KERNEL32.dll` und die `api-ms-win-crt-*.dll` (Universal CRT, ab Windows 10 im System).
Taucht `libgcc_s_seh-1.dll`, `libstdc++-6.dll` oder `libwinpthread-1.dll` auf, wurde ohne
`use_static_cpp` gelinkt und die DLL läuft auf einem fremden PC nicht — `tools/win_build.sh` bricht
in dem Fall selbst ab. Ein Probelauf unter Wine ist derzeit nicht möglich: Homebrews `wine-stable`
ist seit 2026-09-01 deaktiviert (Gatekeeper).

Symbol und Produktname schreibt Godot ab 4.4 selbst in die EXE, ohne `rcedit`/Wine
(`application/modify_resources`); `game/icons/icon.ico` ist aus `design/app/icon_soviet.png` gebacken
(sieben Größen, 16–256 px). Ein Konsolenfenster legt der Export bewusst nicht an
(`debug/export_console_wrapper=0`) — Meldungen stehen im App-Protokoll (`user://logs/app.log`).

`tools/update_pack.sh --upload` lädt den Installer als `pocketra-windows-setup.exe` mit auf Toms
Server und schreibt `windows_url`/`windows_size` in `version.json` — dieselben Felder, die
`UpdateConfig.app_choice()` für den Aktualisierungsknopf auf einem Windows-Rechner liest (s. o.).

---

## Setup

Einmalig installiert (Homebrew):

```bash
brew install --cask godot      # 4.7.2, Standard-Build (nicht die .NET-Variante)
brew install openjdk@17        # Godots Gradle-Build empfiehlt 17
```

Vorhanden und ausreichend: Android SDK (Platform 35, Build-Tools 35.0.0, Platform-Tools 37.0.1),
NDK 28.2, CMake 3.22.1, `adb`.

Spielinhalte (nicht im Repository):

```bash
mkdir -p content && cd content
curl -O https://openra.ppmsite.com/ra-quickinstall.zip
shasum -a 1 ra-quickinstall.zip
# erwartet: 44241f68e69db9511db82cf83c174737ccda300b
```

---

### Musik

Das Freeware-Paket enthält bewusst keine Spielmusik (`scores.mix`) — EAs Modding-Richtlinien verbieten
das Beilegen von C&C-Musik (Recherche 01, §8). Enthalten sind nur das Intro- und das Karten-Thema
(`intro.aud`, `map.aud` in `local.mix`). Die Festplatten-Installation von RA95 (`REDALERT.MIX`) enthält
ebenfalls keine Musik — sie wurde von der CD gestreamt. Wer die CD (oder ein Image davon, Steam
„Ultimate Collection", „Remastered Collection") hat, kopiert `MAIN.MIX` von der Allied- oder Soviet-CD
nach `content/ra/` — die Pipeline liest verschachtelte Archive (`MAIN.MIX` → `scores.mix`) selbst — und
konvertiert die Titel nach `mods/ra/audio/music.yaml` (z. B. `hell226m.aud` = Hell March):

```bash
python3 tools/audconvert.py --music hell226m.aud bigf226m.aud crus226m.aud fac1226m.aud run1226m.aud smsh226m.aud -o game/assets/music
```

Der Musikspieler nimmt alle `.mp3` unter `game/assets/music/` in die Zufallswiedergabe — außer den in
`mods/ra/audio/music.yaml` als `Hidden` markierten (`intro`, `map`, `score`): „Intro" läuft im Menü,
„Militant Force" (`score`) beim Sieg, „Map" bei der Niederlage (`mods/ra/rules/world.yaml`).

#### Woher die Musik auf dem Gerät kommt

Auf dem Handy gibt es drei Quellen, in dieser Reihenfolge:

1. **`scores.mix` des Nutzers** — die Original-Musik der CD, direkt aus dem Archiv gespielt
   (`RaContent`/`AudStream`, keine Wandlung nötig). Sobald über „Spielinhalte einrichten" eine CD
   ausgelesen wurde, ist das der Normalfall.
2. der Ordner `original/music` des Nutzers (s. „Original-Inhalte"),
3. sonst die zwölf eigenen Stücke aus `res://assets/music`.

`ContentPaths.archives()` durchsucht dafür `user://content/mix` **und** `user://content/cd/<allied|
soviet|german>` — dort legt die Einrichtungsseite die aus dem CD-Abbild behaltenen Archive ab
(`scores.mix`, `movies1.mix`/`movies2.mix`, bei der deutschen CD zusätzlich `speech.mix`/`sounds.mix`).
Die Titelliste wird beim Start **und nach jeder Änderung an den Spielinhalten** neu gebaut
(`Music.rebuild()`), eine frisch eingerichtete CD spielt also ohne Neustart der App.

In den Optionen steht der Schalter **„Musik: Original (CD)" / „Musik: Eigene Stücke"** (gemerkt in
`user://settings.cfg`, `[audio] music_source`). Er erscheint nur, wenn es überhaupt Original-Musik
gibt; Voreinstellung ist Original. Darunter steht der laufende Titel („Läuft: Hell March"), im
Pausenmenü ebenso. Die Anzeigenamen stammen aus `mods/ra/audio/music.yaml` und stehen seit
2026-09-06 in `assets/rules.json` unter `music.title` (`tools/rules2json.py`; `RULES_FORMAT` ist
dabei unverändert geblieben, `mapconvert.py` muss also **nicht** neu laufen).

### Videos

Die Kampagnenfilme liegen auf den beiden CDs: `MAIN.MIX` von Disc 1 nach `content/ra/cd1/`,
von Disc 2 nach `content/ra/cd2/` kopieren (die Pipeline liest `movies1.mix`/`movies2.mix` selbst).
`python3 tools/vqa2ogv.py --missions` wandelt alle in `MissionData` der Kampagnenkarten genannten
Filme nach Ogg Theora. Fehlt ein Film, überspringt das Spiel ihn still.

## Veröffentlichen

`tools/publish.py` erzeugt aus dem Arbeitsbaum eine kommentarfreie Kopie (Standardziel
`build/public/`): Kommentare und Docstrings werden per echtem Tokenizer/Zustandsautomat je
Sprache entfernt (Python `tokenize`+`ast`, GDScript/C++/gdshader eigene Automaten mit
String-/Zeichenliteral-Erkennung — kein Regex-Gerate auf Zeilenebene), Ausschlüsse folgen
`.gitignore` plus `project-docs/` und `docs/research/` (interne Doku). `README.md` bekommt dabei
einen kurzen Lizenz-/Herkunftshinweis vorangestellt; `LICENSE` (GPLv3) wird unverändert
übernommen.

```bash
python3 tools/publish.py                          # → build/public/
python3 tools/publish.py --out /tmp/ra-public      # anderes Zielverzeichnis
python3 tools/publish.py --git git@example.com:me/pocketra-public.git
                                                    # legt in --out zusätzlich ein Git-Repo mit
                                                    # orphan-Branch „public" an und zeigt den
                                                    # Push-Befehl an — pusht NICHT von selbst
```

Selbsttest der Kopie:

```bash
python3 -m py_compile $(find build/public -name '*.py')
$G --headless --path build/public/game --import
$G --path build/public/game --quit-after 200        # Skriptfehler sichtbar machen
cd build/public/gdext && scons platform=macos arch=arm64 target=template_debug -j10
python3 tools/test_publish.py                        # Stichproben: keine Kommentare mehr,
                                                       # Strings mit '#'/'//' unversehrt
```

Für den Godot-/scons-Selbsttest brauchen `build/public/game/assets`, `build/public/game/bin` und
`build/public/gdext/godot-cpp` echten Inhalt — per Symlink aus dem Arbeitsbaum (nur für den Test,
nicht Teil der Veröffentlichung):

```bash
ln -s "$PWD/game/assets" build/public/game/assets
cp game/bin/librasim.macos.arm64.dylib build/public/game/bin/
ln -s "$PWD/gdext/godot-cpp" build/public/gdext/godot-cpp
```

## Aktualisierung (Spielinhalt ohne neue APK)

Toms Wunsch (2026-09-04): Freunde sollen nicht ständig eine neue APK bekommen. Beim Start lädt die
App den neuesten Spielinhalt als **Godot-Ressourcenpaket** (`update.pck`) nach und hängt es beim
nächsten Start ein. Nur wenn sich die native Extension ändert, muss wirklich eine neue APK her.

### Was auf dem Server liegen muss

Toms eigener Webserver, nur statische Dateien über **HTTPS**, kein Serverskript, kein PHP:

```
<BASE>/version.json         die Datei, die die App abfragt
<BASE>/update.pck           das Paket
<BASE>/pocketra.apk                 Verteilfassung ohne EA-Inhalte (~130 MB) — DIE Adresse, die Tom weitergibt
<BASE>/pocketra-windows-setup.exe   NSIS-Installer, Windows-Verteilfassung (tools/win_build.sh --dist)
<BASE>/pocketra-macos.dmg           DMG mit Ziehen-in-Programme-Fenster, signiert+notarisiert (tools/mac_build.sh)
```

Eine **Vollfassung liegt seit dem 09.09.2026 nicht mehr auf dem Server** (Toms Regel: nur noch
`-dist`-Varianten ohne EA-Inhalte, damit wir keine Fremdinhalte ausliefern) — gilt seither auch für
Windows und macOS, nicht nur für Android. `tools/update_pack.sh` lädt nur diese drei plus das Paket
hoch und schreibt kein `apk_url_full` mehr in die `version.json`; das frühere `pocketra-full.apk` ist
gelöscht und liefert 404. **Alle Plattformen auf einmal veröffentlichen** (Android+Windows+macOS auf
GitHub und Server, iOS zu TestFlight, Quellcode auf GitHub): `tools/release_all.sh` — s. CLAUDE.md
„Veröffentlichung" und den Kopf des Skripts.

`<BASE>` ist die Adresse ohne Dateinamen. Sie steht als `DEFAULT_URL` in
`game/scripts/update/update_config.gd` und zeigt auf Toms Server
`https://pocketra.net/version.json`; zur Laufzeit lässt sie sich über
`user://settings.cfg` `[update] url=…` oder für Prüfläufe per `--update-url` überschreiben.

Die alte Adresse `redalert.attomic.de` bleibt als **Brücke** bestehen und liefert nur noch eine
`version.json`, die vorhandene Installationen der Fassungen bis 0.15 sperrt und auf
`https://pocketra.net/pocketra.apk` schickt (die Paket-Kennung hat gewechselt, ein Update an Ort
und Stelle ist unmöglich). Die genauen Feldwerte und die Grenzen der Brücke stehen in
[docs/UMBENENNUNG-POCKETRA.md](docs/UMBENENNUNG-POCKETRA.md).

### Paket bauen und hochladen

```bash
tools/update_pack.sh                      # volles Paket + version.json → build/update/
tools/update_pack.sh --slim               # kleines Paket (~45 statt ~116 MB), s. u.
tools/update_pack.sh --notes "Neue Tutorial-Schritte"
tools/update_pack.sh --upload             # zusätzlich per rsync auf den Server
```

Upload-Ziel: Umgebungsvariable `POCKETRA_UPDATE_TARGET` oder die Datei `build/update/upload.conf`
(liegt in `build/`, also außerhalb von Git):

```sh
TARGET=pocketra-upload:/var/www/pocketra/
BASE_URL=https://pocketra.net
RSYNC_OPTS=-avz --chmod=F644
```

Das Skript lädt bewusst **erst** `update.pck`/`pocketra.apk` und **danach** `version.json` hoch —
sonst zeigt die Versionsdatei kurz auf ein Paket, das noch nicht vollständig auf dem Server liegt.
`pack_version` ist eine laufende Nummer und zählt bei jedem Lauf um eins hoch (aus der alten
`build/update/version.json` gelesen); `pack_label` ist Datum + Commit-Kürzel und dient nur der Anzeige.

Erzeugte `version.json`:

```json
{
  "pack_version": 11,
  "pack_label": "2026-09-06-fbc22c1",
  "pack_url": "https://pocketra.net/update.pck",
  "pack_sha256": "472a3817…",
  "pack_size": 44655780,
  "min_extension": "0.10.0",
  "apk_version": "0.11",
  "apk_url": "https://pocketra.net/pocketra.apk",
  "apk_size": 122334455,
  "windows_url": "https://pocketra.net/pocketra-windows-setup.exe",
  "windows_size": 210443188,
  "mac_url": "https://pocketra.net/pocketra-macos.dmg",
  "mac_size": 190000000,
  "notes": "",
  "disabled": false
}
```

`apk_size` ist die Größe von `build/pocketra-dist.apk` (nur Anzeige: „Verteilfassung (122 MB)").
Liegt die Datei beim Lauf nicht in `build/`, behält das Skript den Wert aus der alten
`version.json` — ein reiner `--version-only`-Lauf verliert die Angabe also nicht. Die Felder
`apk_url_full`/`apk_size_full` schreibt das Skript **nicht mehr** (s. o.); die App kommt ohne sie
aus (s. Punkt 4 unten).

### Was im Paket steckt

Zwei Presets in `game/export_presets.cfg`, beide nur für `--export-pack` (nie als APK):

| Preset | Inhalt | Größe |
|---|---|---|
| `Update-Paket` | dieselbe Menge wie „Android Verteilung" (scripts, scenes, i18n, icons, `data/**`, `assets/rules.json`, `assets/maps/**`, `assets/ui/**`, `assets/music/**`, `assets/intro/**`) minus `bin/**` | ~116 MB |
| `Update-Paket schlank` | dasselbe ohne `assets/music`, `assets/ui`, `assets/intro` — die ändern sich praktisch nie | ~45 MB |

Nie im Paket: die EA-Inhalte (`assets/atlas`, `assets/sfx`, `assets/video` — die baut das Gerät sich
über die Seite „Spielinhalte einrichten" selbst) und `bin/**` (die native Extension steckt in der APK).
Das schlanke Paket ist gefahrlos, weil `load_resource_pack(path, true)` nur die enthaltenen Dateien
ersetzt; alles andere kommt weiter aus der APK. Ändert sich Musik, Menübild oder Intro, einmal das
volle Preset benutzen (oder gleich eine neue APK verteilen).

### Ablauf in der App

1. **Beim Start** hängt der Autoload `UpdateBoot` (`game/scripts/update/update_boot.gd`, steht ganz
   oben in `project.godot`) `user://update/current.pck` ein — vor allen anderen Autoloads und vor der
   Hauptszene. Log: `Update: Paket 7 geladen (2026-09-04-6f1bfd6)`.
2. **Im Hauptmenü** holt `UpdateService` nicht blockierend `version.json`. Ist `pack_version` größer
   als die eigene, lädt es `update.pck` nach `user://update/next.pck`, prüft SHA-256 und benennt es
   zu `current.pck` um. Fortschritt und Ergebnis stehen in einer kleinen Zeile unten
   („Aktualisierung wird geladen … 42 %", dann „Aktualisierung geladen — Neustart nötig" mit Knopf
   „Jetzt neu starten"). Auf Android gibt es keinen Prozessneustart aus der App heraus — dort steht
   dort nur „Beim nächsten Start der App aktiv."
3. Ist `min_extension` größer als die eigene Extension (`RaSim.version()`), wird gar nichts geladen:
   die Zeile meldet „Neue App-Version nötig" mit einem Knopf, der die passende APK (s. Punkt 4) im
   Browser öffnet.
4. **Welche Fassung?** Zum Herunterladen gibt es nur noch **eine** APK: die **Verteilfassung**
   (lokal `pocketra-dist.apk`, auf dem Server `pocketra.apk`; Preset „Android Verteilung" — die
   Inhalte holt sich das Gerät über die Seite „Spielinhalte einrichten"). Die **Vollfassung**
   (`build/pocketra-full.apk`, Preset „Android" — die EA-Inhalte liegen in der APK) baut Tom nur
   noch für sich; seit dem 09.09.2026 wird sie nicht mehr veröffentlicht, damit wir keine
   Fremdinhalte ausliefern.

   Die Wahlmechanik bleibt trotzdem im Code, sie fällt nur immer gleich aus. Hintergrund ist Toms
   Befund 2026-09-06: sein Gerät hatte die Vollfassung, der Hinweis „Neue App-Version" schickte ihn
   aber auf die Verteilfassung; nach der Installation wären alle Inhalte weg gewesen. Die App
   erkennt ihre eigene Fassung deshalb am selben Merkmal, an dem auch die Inhalte-Seite hängt —
   liegt `res://assets/atlas/atlas_temperat.json` in der APK (`ContentManager.dev_bundled()`), ist
   es die Vollfassung — und bietet über `UpdateConfig.apk_choice()` `apk_url_full` an, wenn die
   Versionsdatei das Feld trägt. Da der Server es **nicht mehr schickt**, greift für jedes Gerät
   der Rückfall auf `apk_url`, und die Anzeige sagt dann ehrlich „Verteilfassung" — lieber das als
   ein Knopf auf eine 404. Der Rückfall bleibt bewusst stehen: ältere, von Hand geschriebene
   Versionsdateien können das Feld noch tragen.

   Sichtbar wird die Fassung an drei Stellen: im Hinweisfenster („Für Deine Fassung: Verteilfassung
   (122 MB)"), in der Statuszeile („App 0.16 verfügbar — Verteilfassung (130 MB)") und auf der
   Sperrseite. In den **Optionen** steht die **installierte** Fassung in der Versionszeile: „App
   0.16 · Spielinhalt 11 (…) · Verteilfassung" — auf Toms eigenem Vollfassungs-Gerät entsprechend
   „Vollfassung".
5. **Neue App-Version im Angebot** (Toms Vorgabe 2026-09-05): ist `apk_version` höher als die eigene
   `application/config/version` (Vergleich Zahl für Zahl je Punktabschnitt), erscheint beim Start
   **einmal je neuer Version** ein Fenster im Rahmenstil — „Neue Version 0.11 verfügbar", darunter der
   Text aus `notes`, Knöpfe „Herunterladen" (öffnet `apk_url` im Browser) und „Später". Es blockiert
   nichts: Paket-Aktualisierungen laufen daneben still weiter. Gemerkt wird die zuletzt gezeigte
   Version als `apk_seen` in `user://update/state.json` (dieselbe Datei wie die Sperre, `apk_seen`
   überlebt Sperren und Entsperren). Die Statuszeile trägt zusätzlich „App 0.11 verfügbar" — auch
   nach dem Wegdrücken, damit der Hinweis nicht verloren geht.
6. Ohne Netz oder bei jedem Fehler passiert nichts Sichtbares — die Meldung steht nur im Log.
7. In den **Optionen**: Schalter „Aktualisierungen beim Start prüfen" (Standard an), „Jetzt nach
   Aktualisierungen suchen" und die Zeile „App 0.16 · Spielinhalt 11 (2026-09-09-33a902f) ·
   Verteilfassung" (die installierte Fassung, bei Toms eigenem Bau „Vollfassung").

### Eine verteilte Fassung stilllegen

Zwei optionale Felder in `version.json`:

```bash
tools/update_pack.sh --version-only --min-supported 0.7 --notes "Bitte die neue App laden."
tools/update_pack.sh --version-only --disable --notes "Wegen eines Fehlers vorübergehend gesperrt."
```

* `min_supported` — jede App-Version darunter (`ProjectSettings application/config/version`, dieselbe
  Zahl wie `version/name` in `export_presets.cfg`) wird gesperrt. `min_supported_pack` macht dasselbe
  über die Paketnummer.
* `disabled: true` — Notschalter für **alle** Fassungen.

Die App zeigt dann die nicht wegdrückbare Seite „Diese Fassung wird nicht mehr unterstützt" mit dem
Text aus `notes`, einem Knopf zur neuen APK (wenn `apk_url` gesetzt ist), „Erneut prüfen" und
„Beenden"; Gefecht, Missionen und Tutorial sind gesperrt. Der Zustand liegt in
`user://update/state.json` und gilt deshalb auch beim nächsten Start **ohne Netz**. Meldet der Server
wieder `disabled: false` und kein passendes `min_supported`, wird die Sperre aufgehoben.

**Grenze:** eine Kopie, die den Server **nie** erreicht hat, lässt sich nicht stilllegen — sie hat nie
gefragt. Und ohne erreichbaren Server läuft jede App normal weiter (Absicht: ein Serverausfall darf
niemandem das Spiel wegnehmen).

### Grenzen des Paket-Verfahrens

* `update_boot.gd` selbst kommt immer aus der APK — beim Einhängen ist es schon geladen. Ein Fehler
  im Bootstrap braucht eine neue APK. Alles andere (`update_config.gd`, `update_service.gd`,
  `update_page.gd`, das ganze Menü, alle Spielskripte) kommt aus dem Paket und ist nachträglich
  reparierbar.
* `project.godot` steckt in der APK-PCK und wird **nicht** ersetzt: neue Autoloads, ein neuer Eintrag
  in `locale/translations`, eine andere Hauptszene oder eine geänderte App-Version brauchen eine APK.
  Der **Inhalt** der schon gelisteten Übersetzungen kommt seit 2026-09-05 aber sehr wohl aus dem
  Paket: Godot lädt die `.translation`-Dateien vor den Autoloads, also vor `load_resource_pack()` —
  der `TranslationServer` hielt danach die alten Tabellen aus der APK und jeder neue `tr()`-Schlüssel
  stand roh auf dem Knopf (Toms Befund auf 0.5: „menu.options.log"). `update_boot.gd` meldet die
  gelisteten Übersetzungen nach dem Einhängen deshalb ab (`TranslationServer.remove_translation`) und
  lädt sie mit `ResourceLoader.CACHE_MODE_IGNORE` aus `res://` — jetzt aus dem Paket — neu. Neue
  **Sprachen** brauchen weiter eine APK, neue **Schlüssel** nicht mehr.
* **Neue globale Namen brechen ältere Apps.** Godot löst sowohl Autoload-Bezeichner (`AppLog`) als
  auch `class_name`-Klassen beim *Übersetzen* auf. Beide Verzeichnisse — `project.godot` und
  `.godot/global_script_class_cache.cfg` — liegen nur in der APK; `--export-pack` legt weder
  `project.binary` noch den Klassencache ins Paket. Eine ältere App, die ein Paket mit einem neuen
  Autoload- oder Klassennamen einhängt, meldet beim Start `Parse Error: Identifier "…" not declared
  in the current scope` und lädt die betroffene Datei — womöglich das halbe Menü — gar nicht mehr.
  Deshalb: **im Paket nie einen neuen globalen Namen benutzen.** Ein neues Skript wird über seinen
  Pfad geladen (`const LogView := preload("res://scripts/ui/log_view.gd")`), ein neues Autoload über
  eine Fassade, die es zur Laufzeit sucht und sonst zurückfällt
  (`game/scripts/app_logger.gd` → `/root/AppLog`, sonst `print`/`push_warning`). Dann läuft dasselbe
  Paket auf alter und neuer App, und `min_supported` bleibt für echte Notfälle frei.
* Die native Extension (`bin/`) wechselt nur mit der APK. Deshalb trägt jedes Paket `min_extension`.
* Der Neustart nach dem Download ist auf Android ein Hinweis, kein Knopf.

### Entwicklerlauf am Mac: kein Paket, keine Prüfung

Toms Befund 2026-09-05: das Server-Paket hatte im Worktree die eigenen Skripte überlagert —
`load_resource_pack(path, true)` ersetzt `res://`-Dateien, und dann prüft man die veröffentlichte
Fassung statt der eigenen Änderung. Deshalb tut ein Lauf aus dem Projektordner (Editor-Binary,
`--path game`, also `OS.has_feature("editor")` bzw. **kein** `template`) beides nicht:

* `UpdateService.start()` bricht sofort ab („Update: Prüfung übersprungen — Entwicklerlauf"), auch
  bei „Jetzt nach Aktualisierungen suchen" in den Optionen,
* `update_boot.gd` hängt `current.pck` gar nicht erst ein.

`--test-update` oder `--update-url URL` heben beides auf — nur so lässt sich die Aktualisierung am
Mac überhaupt prüfen. Auf dem Gerät (exportierte APK) ändert sich nichts.

### Prüfen am Mac

```bash
tools/update_pack.sh --slim
(cd build/update && python3 -m http.server 8123 --bind 127.0.0.1 &)
# pack_url/apk_url in build/update/version.json auf http://127.0.0.1:8123/... setzen
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --path game --resolution 2560x1096 res://scenes/main_menu.tscn --quit-after 3000 -- \
   --menu-screenshot /tmp/m.png --page main --lang de --dpi 420 \
   --update-url http://127.0.0.1:8123/version.json --test-update
$G --path game --quit-after 60 -- --no-intro --update-url http://127.0.0.1:8123/version.json
#   erwartet: „Update: Paket N geladen" und „Update: 2 Übersetzung(en) aus dem Paket neu geladen"
```

Die **Fassungswahl** (Punkt 4 oben) prüft man mit zwei Läufen — das Mac-Projekt hat `game/assets`,
gilt also als Vollfassung, und `--force-content-locked` stellt eine Verteil-APK nach. Mit der
`version.json`, die `tools/update_pack.sh` heute erzeugt (nur `apk_url`, kein `apk_url_full`), muss
**beides** auf `pocketra.apk` zeigen:

```bash
$G --path game res://scenes/main_menu.tscn --quit-after 3000 -- --page main --lang de \
   --update-url http://127.0.0.1:8123/version.json --test-update
#   erwartet: „eigene Fassung Vollfassung — angeboten wird Verteilfassung (122 MB) (…/pocketra.apk)"
$G --path game res://scenes/main_menu.tscn --quit-after 3000 -- --page main --lang de \
   --force-content-locked --update-url http://127.0.0.1:8123/version.json --test-update
#   erwartet: „… Verteilfassung (122 MB) (…/pocketra.apk)"
```

Der andere Zweig von `apk_choice()` (Vollfassung bekommt `apk_url_full`) lässt sich nur noch mit
einer **von Hand** um `apk_url_full` ergänzten `version.json` auslösen — kein Server schickt das
Feld mehr. Der Code kann es weiterhin, damit alte Versionsdateien nicht ins Leere zeigen.

Ohne `--test-update`/`--update-url` hängt der Mac-Lauf kein Paket ein (s. „Entwicklerlauf am Mac").
**Nach dem Prüflauf `user://update` leeren** (`~/Library/Application Support/Godot/app_userdata/pocketra/update`),
sonst startet jeder andere Worktree mit dem Paket dieses Laufs.

## Mehrspieler-Vermittler

Der Mehrspieler läuft im **Gleichschritt**: übertragen werden Befehle, kein Zustand, jeder Client
rechnet dieselbe Sim. Auf Toms Server sitzt dafür ein kleiner Weiterleiter — keine Sim, keine
Datenbank, nichts auf Platte. Entwurf und Protokoll stehen in `docs/MULTIPLAYER.md`, Betrieb und
Fehlersuche ausführlich in `server/README.md`.

```
App  ──wss://pocketra.net/mp──►  nginx (443)  ──►  127.0.0.1:8787  mp_server.py
```

| Datei | Zweck |
|---|---|
| `server/mp_server.py` | der Vermittler (Python 3, `asyncio` + `websockets`, eine Datei) |
| `server/mp_smoke.py` | Prüfclients ohne Godot — Lobby, Kartenwechsel, Raumliste, Teams/Startpunkte, 200 Rahmen, Desync, Abbruch, Rate-Limit, Wiederverbinden, Sprechfunk |
| `server/pocketra-mp.service` | systemd-Unit (Benutzer `pocketra-mp`, `MemoryMax=256M`, gehärtet) |
| `server/nginx-mp.conf` | der `location /mp`-Block für die Site |
| `tools/mp_deploy.sh` | rollt alles aus und prüft den Handschlag von außen |

### Am Mac

```bash
python3 -m venv build/.venv_mp && build/.venv_mp/bin/pip install websockets
build/.venv_mp/bin/python server/mp_server.py --host 127.0.0.1 --port 8787
build/.venv_mp/bin/python server/mp_smoke.py            # startet selbst einen, ~49 s, 132 Prüfungen
```

### Ausrollen und prüfen

```bash
tools/mp_deploy.sh          # rsync → /opt/pocketra-mp, venv, systemd, nginx, Neustart, Handschlag
tools/mp_deploy.sh --check  # nur nachsehen, nichts anfassen
build/.venv_mp/bin/python server/mp_smoke.py --url wss://pocketra.net/mp
```

Das Skript ist idempotent: den Systembenutzer, das venv und den `location /mp`-Block legt es nur
an, wenn sie fehlen (danach `nginx -t && systemctl reload nginx`); jeder weitere Lauf tauscht bloß
`mp_server.py` aus und startet den Dienst neu. Zum Schluss erwartet es
`HTTP/1.1 101 Switching Protocols` von `https://pocketra.net/mp` — `curl` braucht dafür
`--http1.1`, über HTTP/2 fällt `Connection: Upgrade` weg und die Antwort ist `426`.

Logs: `ssh pocketra-upload journalctl -u pocketra-mp -f` — eine Zeile je Ereignis
(`create`, `join`, `start`, `desync`, `peer_left`, `ratelimit_*`, `room_closed`). Chattexte
protokolliert der Vermittler nicht, nur Platz, Umfang und Länge. Neustart ist harmlos: es liegt
kein Zustand auf Platte, nur laufende Partien brechen ab.

## Mehrspieler-App

Im Hauptmenü steht **Mehrspieler** neben **Gefecht**. Einer legt einen Raum an und liest den
sechsstelligen **Spielcode** vor, die anderen tippen ihn unter *Beitreten* ein — oder sie tippen den
Raum in der Liste der **öffentlichen Räume** an, die unter der Codeeingabe steht.

Beim Anlegen sieht die Seite aus wie das Gefecht: Kartenliste mit Name, Größe und Plätzen, daneben
das **Vorschaubild mit nummerierten Startpunkten** (ein Tipp zeigt die Karte bildschirmfüllend) und
die Einstellungen Startgeld, Starteinheiten, Kisten, Karte erkundet, Nebel und KI-Stärke. **Die
Startplätze der Karte sind die Plätze des Raums.**

**Öffentlich oder privat** (Toms Wunsch 2026-09-07): unter den Einstellungen steht „Sichtbarkeit:
Öffentlich / Privat", Vorgabe ist **privat** — eine Runde unter Freunden landet also nicht
ungewollt in der Liste. Ein öffentlicher Raum steht bei *Beitreten* unter der Codeeingabe: je Zeile
die Kartenvorschau als Miniatur, Kartenname und Gastgeber, belegte/gesamte Plätze, Zustand
(Lobby / läuft) und der Spielcode; **ein Tipp auf die Zeile tritt bei**, laufende Partien sind
ausgegraut. Die Liste wird alle drei Sekunden neu geholt, solange die Seite offen ist; steht keine
da, sagt sie „Gerade keine öffentlichen Räume". Der Gastgeber kann in der Lobby jederzeit zwischen
„Öffentlicher Raum" und „Privater Raum" umschalten (Knopf unter dem Spielcode). Ein privater Raum
taucht in keiner Liste auf und geht weiter nur über den Code.

In der Lobby steht je Platz eine Zeile (Name, Fraktion, Farbe, Team, Startpunkt, Bereit, Ping),
darüber die Kartenvorschau und daneben das Chatfenster; der Gastgeber fügt KI-Plätze hinzu, wirft
raus, **wechselt die Karte** und startet, sobald alle bereit sind. Die eigene Zeile ist bedienbar,
**fremde Zeilen zeigen Fraktion, Team und Startpunkt als helle Beschriftung** — ein gesetztes Team
in Gold (Toms Befund 2026-09-09: „Ich konnte nicht sehen, welches Team er hat"). Der Gastgeber
stellt zusätzlich Fraktion und Team der KI-Zeilen ein. Ein Tipp auf die Vorschau (oder
auf „Karte groß") zeigt die Karte bildschirmfüllend: belegte Startpunkte tragen die Farbe ihres
Platzes und sind gesperrt, **ein Tipp auf eine freie Nummer wählt den eigenen Startpunkt** — für den
Gastgeber wie für die Gäste; ein zweiter Tipp auf den eigenen Punkt stellt wieder „zufällig" ein.
Wechselt der Gastgeber die Karte, deckelt der Vermittler die Plätze neu und setzt Startpunkte und
Bereitschaft zurück. Der Spielername steht in den Optionen, Vorgabe ist der Gerätename.

**Teams** (seit 2026-09-09): gleiche Teamzahl > 0 heißt verbündet — kein gegenseitiger Beschuss,
kein Zielen aufeinander, der Siegtest überspringt Verbündete. „–" heißt „kein Team", also jeder
gegen jeden. Jede Änderung geht über den Vermittler und erscheint sofort bei **allen**; der
Vermittler stempelt beim Start das gültige Team in die Aufstellung, damit eine späte Änderung nicht
mehr verlorengeht. **Startpunkte** teilt der Vermittler ebenso: ein belegter Punkt ist in der großen
Karte gesperrt und wird auch dann abgewiesen, wenn ihn zwei gleichzeitig antippen („Startpunkt ist
schon belegt").

Fassung 1 trägt **höchstens sechs Plätze** (Sim-Spieler 0, 1, 4, 5, 6, 7 — 2 und 3 sind Neutral und
Creeps). Bietet die Karte mehr Startpunkte, sagt es die Lobby an und die übrigen bleiben leer.

**Hintergrund und Wiederverbinden** (Toms Befund 2026-09-09): Wechselt man aus der Lobby nach
WhatsApp, hält Android die App an — Godot pollt den Socket nicht mehr und der Vermittler trennt nach
rund 40 s. Der Raum verschwindet deswegen nicht mehr: der Vermittler **reserviert** den Platz drei
Minuten lang (`--resume-s`), der Raum bleibt in der Raumliste, die Lobby der anderen zeigt den
Spieler blass mit „⟳ … weg". Kommt die App zurück, verbindet sie sofort neu und holt mit
`resume{code, token}` denselben Platz samt Gastgeberrolle zurück; solange das läuft, steht in der
Lobby „Verbinde neu …". „Raum verlassen" gibt den Platz dagegen sofort frei. Einzelheiten und der
Weg zu den **Benachrichtigungen ohne FCM** (Android-Plugin, Vordergrunddienst): `docs/MULTIPLAYER.md`
§10.

Im Spiel: Sprechblasenknopf in der Knopfleiste öffnet die Chatzeile (sechs Kurzrufe für den Daumen,
Umschalter „an alle / an Team"); die letzten vier Zeilen stehen oben links in Spielerfarbe und
blenden nach zwölf Sekunden aus, der Verlauf liegt im Pausenmenü. Neben dem Chatknopf stehen Ping
und Rahmenrückstand. Fehlt ein Paket, steht das Bild und die Fläche „Warte auf … " zählt die
Sekunden; bricht die Verbindung ab, endet die Partie mit einer Endkarte über alle Plätze.
„Aufgeben" im Pausenmenü ist ein Befehl an alle (op 50), die Spielgeschwindigkeit ist fest.

**Sprechfunk** (Toms Wunsch 2026-09-08, docs/MULTIPLAYER.md §10): **oben in der Kopfzeile, rechts
neben dem Menüknopf**, stehen im Mehrspieler der Chat- und der Mikrofonknopf (Menü → Chat →
Mikrofon). Unten bleibt die Knopfleiste dadurch Knopf für Knopf dieselbe wie im Einzelspieler.
Ein **Tipp** auf das Mikrofon schaltet das Mikrofon an das **eigene Team** — das Symbol wird grün
und daneben steht „Team". Ein **langer Druck** öffnet den **offenen Kanal an alle**, auch an die
Gegner — das Symbol wird orange, daneben steht „An alle". Nochmal tippen bzw. lang drücken
schaltet wieder aus, und jeder Wechsel sagt im Klartext an, wer mithört. Gesendet wird nur, solange
wirklich geredet wird (Sprachschleuse); wer gerade funkt, steht oben links als „spricht: <Name>"
in seiner Spielerfarbe. Einzelne Mitspieler lassen sich im Pausenmenü unter „Spieler" stumm
schalten, Lautstärke („Sprechfunk", eigener Audio-Bus) und ein Aus-Schalter stehen in den Optionen.
Übertragen werden 8 kHz mono in 60-ms-Paketen als IMA-ADPCM — rund 50 kbit/s je aktivem Sprecher,
über eine eigene Nachrichtenart des Vermittlers, die den Gleichschritt nicht berührt. Auf Android
fragt die App beim ersten Einschalten die Mikrofonfreigabe (`RECORD_AUDIO`) ab; **dafür braucht es
eine neue APK**, ein Aktualisierungspaket reicht nicht. Beim **ersten** Mehrspielerstart erklärt
eine kleine Tafel einmalig Tippen und Langdruck mit den beiden Mikrofonfarben; ein Tipp schließt
sie, sie hält nichts an, und der Merker steht in `user://settings.cfg` (`[multiplayer]
voice_intro`). Wieder aufschlagen: „Sprechfunk erklären" im Pausenmenü unter „Spieler".

**Spielerliste** (Toms Handtest 2026-09-09, docs/MULTIPLAYER.md §12): Im Pausenmenü steht der
Eintrag **„Spieler"**. Je Platz eine Zeile mit **Farbklecks** (dieselbe Farbe wie in der Lobby und
auf dem Feld), **Name** (KI als „KI 1 (Schwer)"), **Team** („Team 2" in Gold, „–" für kein Team),
dem **Verhältnis zu mir** — „ich" gold, „verbündet" grün, „feindlich" rot — und dem **Zustand**:
„im Spiel (16)" (die Zahl sind die verbliebenen Einheiten und Gebäude), „besiegt",
„Verbindung weg" nach `peer_left` oder „keine Antwort", solange ein Paket fehlt. Sortiert wird nach
Team, „kein Team" hinten. Im Mehrspieler tragen die Zeilen der Mitspieler zusätzlich den
Stummschalter des Sprechfunks, darunter stehen Chatverlauf und „Sprechfunk erklären" — der Eintrag
„Chatverlauf" ist darin aufgegangen, das Pausenmenü bleibt gleich lang. Im **Gefecht gegen die KI**
gibt es dieselbe Liste (ohne Chat und Stummschalter), in **Missionen** nicht. Die Liste ist reine
Anzeige: sie schickt nichts, hält nichts an und ändert den `state_hash` nicht.

**Wenn nichts ankommt** (Toms Handtest 2026-09-09): Der Sprechfunk scheiterte still — Mikrofon
an, kein Ton, keine Rückmeldung. Jetzt gibt es zweierlei. In den Optionen steht eine
**Mikrofonprobe**: ein Knopf, ein Live-Pegelbalken mit der Schleusenschwelle als goldene Marke und
eine Klartextzeile („Sendet · Pegel 0.0300 · Schwelle 0.0047" bzw. „Zu leise zum Senden"); sie
nimmt auf und sendet nichts. Und im Spiel meldet sich der Sprechfunk selbst, wenn das Mikrofon an
ist und vier Sekunden lang **kein einziges** Paket rausgeht — mit unterschiedlichem Text je nach
Ursache: keine Aufnahme, fehlende Freigabe, **Freigabe steht und der Eingang bleibt trotzdem
stumm** oder zu leise. Der dritte Fall war Toms Befund vom Xperia 5 V: Godots Android-Treiber
fordert den Aufnahmeeingang **fest** mit 44 100 Hz an, das Gerät fährt 48 000 Hz — Android nimmt
nachweislich auf (9,2 s laut `appops`), die Engine mischt trotzdem nur Nullen auf den Bus, und
`audio/driver/mix_rate` hilft nicht, weil der Treiber die Einstellung gar nicht liest. Seit App
**0.15** nimmt die App auf Android deshalb **selbst** auf: `AudioRecord` im Kotlin-Plugin
(`android/pocketra_plugin/…/VoiceInput.kt`) mit `VOICE_COMMUNICATION` — native Geräterate,
Echounterdrückung und Rauschfilter vom System. Auf Mac und Windows bleibt es beim Engine-Weg;
beide münden in dieselbe Kette (docs/MULTIPLAYER.md §11.3). Die Mikrofonprobe sagt, welcher Weg
läuft: `Freigabe ja · Quelle: Plugin 48000 Hz · … · ≠0 96% · roh 0.0110 · Neu 0`, darunter eine
Zeile über das Plugin (`Plugin: nicht geladen` / `Plugin: geladen (JNI) · kann: micStart, … ·
micStart=48000 · AudioRecord …`) und die Geräteliste. Die Plugin-Zeile zählt auf, **welche**
Methoden benutzbar sind, und behauptet keine Ursache mehr: bis 0.16 sagte sie „ohne micStart (alte
AAR)", weil wir mit `Object.has_method()` geprüft haben — das ist auf einem Android-Plugin-Singleton
kein gültiger Test (docs/MULTIPLAYER.md §11.3). Springt das Plugin
nicht an, sagt `adb logcat -s GodotPluginRegistry:V`, woran es liegt (docs/MULTIPLAYER.md §11.3). Die Sprachschleuse stellt sich außerdem selbst auf das
Grundrauschen ein, statt an einer festen Zahl zu hängen.

**Regel ohne Ausnahme:** die Oberfläche ruft nie `sim.order_*`, sondern `world.issue(cmd)`
(`game/scripts/net/net_orders.gd` hält die Befehlstabelle). Im Einzelspieler führt `issue()` sofort
aus — dort ändert sich nichts.

### Prüflauf am Mac

```bash
build/.venv_mp/bin/python server/mp_server.py --host 127.0.0.1 --port 8787 &
SPIELER=2 RAHMEN=400 sh tools/mp_local_test.sh build/mp-test     # mit sh, nicht mit zsh!
# Raumliste statt Spielcode: Gastgeber legt öffentlich an, die anderen tippen die Zeile an
SPIELER=2 RAHMEN=120 OEFFENTLICH=1 sh tools/mp_local_test.sh build/mp-test
# Sprechfunk mitlaufen lassen (Sinuston statt Mikrofon): beide Seiten schreiben `MP-FUNK seat N an`
SPIELER=2 RAHMEN=250 FUNK=team sh tools/mp_local_test.sh build/mp-test
python3 tools/mp_diff.py build/mp-test/p1.log build/mp-test/p2.log

# Teams und Startpunkte (Toms Befund 2026-09-09): je Instanz eine Teamzahl bzw. ein Startpunkt
TEAMS="1 1" SPIELER=2 RAHMEN=200 sh tools/mp_local_test.sh build/mp-ally
TEAMS="1 2" STARTPUNKTE="0 3" SPIELER=2 RAHMEN=200 sh tools/mp_local_test.sh build/mp-foe
grep -a 'Mehrspieler-Teams\|mp-bündnis' build/mp-ally/p*.log   # Gegnerliste muss leer sein
```

`tools/mp_local_test.sh` startet bis zu sechs Godot-Fenster gegen den lokalen Vermittler, spielt auf
allen Seiten dasselbe Befehlsskript (`--mp-autoplay N`), schickt alle 15 Rahmen eine Chatzeile
(`--mp-chat-every`) und legt Bildschirmfotos ab (`--mp-shot DIR`). Jede Instanz schreibt je zehnten
Rahmen `MP-FRAME <rahmen> tick <tick> hash <hex>`; `tools/mp_diff.py` nennt den ersten abweichenden
Rahmen oder meldet „desync-frei".

| Schalter | Zweck |
|---|---|
| `--mp URL` / `--mp-url URL` | Vermittler statt `wss://pocketra.net/mp` |
| `--mp-create` / `--mp-join CODE` | Raum anlegen (schreibt `MP-CODE: …`) bzw. betreten |
| `--mp-public` | dazu: den Raum **öffentlich** anlegen (`create.public`) |
| `--mp-join-list` | Beitreten-Seite öffnen, auf die Raumliste warten und den ersten Eintrag antippen (schreibt `MP-LISTE:` und `MP-LISTE-TIPP:`) |
| `--mp-name NAME` | Spielername für diesen Lauf |
| `--mp-players N` | der Gastgeber startet, sobald N Menschen bereit sind |
| `--mp-team N` | vor dem Bereitmelden `slot{team: N}` schicken (0 = kein Team); `TEAMS="1 1"` in `mp_local_test.sh` |
| `--mp-spawn N` | vor dem Bereitmelden `slot{spawn: N}` schicken (−1 = zufällig); `STARTPUNKTE="0 3"` |
| `--mp-autoplay N` | festes Befehlsskript, nach N Netzrahmen Protokollzeile und Ende |
| `--mp-chat-every N` | alle N Rahmen eine Chatzeile (prüft: Chat ändert den Sync-Hash nicht) |
| `--mp-shot DIR` | Bildschirmfotos (Lobby, Spiel, Chat, Warten, Verbindungsverlust) |
| `--mp-voice team\|all` | Sprechfunk im Prüflauf einschalten — Sinuston statt Mikrofon; jede Instanz schreibt `MP-FUNK seat N an/aus`, sobald sie einen anderen Platz hört |
| `--mp-chat-lobby TEXT` | eine Zeile in die Lobby schicken (Bild des Chatfensters) |
| `--mp-log` | jede Netznachricht auf stdout |
| `--mp-demo-lobby` | (an `main_menu.tscn`) Lobby ohne Vermittler mit Beispieldaten füllen — für `--test-layout` und Bildschirmfotos |
| `--mp-demo-zoom` | dazu: die bildschirmfüllende Karte vor dem Foto aufschlagen |
| `--mp-demo-create` | (an `main_menu.tscn`) die Kartenwahl der Seite „Raum erstellen" aufschlagen |
| `--mp-demo-join` | (an `main_menu.tscn`) die Beitreten-Seite mit vier Beispielräumen in der Raumliste — für `--test-layout` und Bildschirmfotos, fragt den Vermittler **nicht** ab |

### Hintergrundwechsel prüfen

```bash
sh tools/mp_bg_test.sh build/mp-bg-test      # ~2,5 min, startet den Vermittler selbst
```

Zwei Godot-Fenster in einer Lobby; der Gastgeber bekommt `SIGSTOP` — genau das macht Android beim
Wechsel nach WhatsApp: die Hauptschleife steht, der Socket wird nicht mehr gepollt. Nach `SIGCONT`
muss der Raum noch stehen (`seat_absent` statt `room_closed` im Protokoll des Vermittlers) und
`resume` denselben Platz zurückholen. Umgebung: `PAUSE` (Sekunden im Hintergrund, Vorgabe 60 —
darunter merkt der Vermittler nichts, seine Pings brauchen bis zu 40 s), `RESUME`, `PORT`, `KARTE`.

### Benachrichtigungs-Plugin (Android, ohne FCM)

```bash
sh tools/plugin_build.sh              # baut android/pocketra_plugin → addons/…/bin/*.aar
```

Kotlin-Plugin mit Vordergrunddienst: es hält im Hintergrund eine eigene Verbindung zum Vermittler
(`watch{code, token}`) und meldet „X ist beigetreten", Chatzeilen und den Spielstart als lokale
Benachrichtigung. **Seit 2026-09-09 in der APK** — der Android-Export läuft dafür über den
Gradle-Bau (s. „Android bauen und installieren" und `docs/MULTIPLAYER.md` §10.5); `tools/apk_build.sh`
baut die AAR selbst mit. Fehlt sie oder ist das Addon aus, läuft alles wie bisher, nur ohne
Benachrichtigungen.

## Original-Inhalte (Intro und Musik der CD)

Das Spiel bringt ein eigenes Intro (`design/intro/`) und eigene Musik (zwölf Songs) mit. Wer die
Original-CD besitzt, kann Intro, Musik und Missionsfilme der CD einspielen — dann läuft beim Start das
komplette Original-Intro (Vorgeschichte, Westwood-Logo, Helikopter, Titelkarte) und im Spiel die
Original-Musik aus `scores.mix`.

1. `MAIN.MIX` der CD nach `content/ra/` (oder einen Unterordner) kopieren.
2. Packen: `python3 tools/original_pack.py` → `build/original/music/*.mp3` und `build/original/video/*.ogv`
   (deutsche Filme zusätzlich mit `--content content/ra_de --lang de`).
3. Den Ordner `original/` auf das Gerät legen:

| Gerät | Zielordner |
|---|---|
| Android | `/sdcard/Android/data/net.pocketra.app/files/original/` — z. B. `adb push build/original /sdcard/Android/data/net.pocketra.app/files/original` |
| macOS | `~/Library/Application Support/Godot/app_userdata/pocketra/original/` |
| iOS | Ordner `original/` im Dokumente-Ordner der App (Dateien-App oder Finder-Freigabe) |
| Windows | `%APPDATA%\Godot\app_userdata\pocketra\original\` |
| Linux | `~/.local/share/godot/app_userdata/pocketra/original/` |

Erwartete Struktur: `original/music/<name>.mp3` (oder `.ogg`) und `original/video/<name>.ogv`, optional
`original/video/de/<name>.ogv` für die deutsche Fassung. Beim Start meldet das Log
`Original-Inhalte: <Pfad>`; fehlt der Ordner, bleibt es bei den mitgelieferten Fassungen. Für das
Intro werden `prolog.ogv` und `redintro.ogv` gebraucht, die Musik nimmt alle Dateien im Ordner
(`intro`, `map`, `score` gelten wie in OpenRA als versteckte Sonderstücke für Menü, Sieg und Niederlage).

## Rechtliches

Privates Projekt, keine Weitergabe. Die Spielinhalte gehören Electronic Arts und liegen dem
Repository nicht bei — `content/` und `game/assets/` sind bewusst aus der Versionskontrolle
ausgeschlossen. Das Repository enthält ausschließlich eigenen Code und die Pipeline, die die Assets
zur Laufzeit erzeugt.

Details zur Lizenzlage von OpenRA-Code, OpenRA-Regeldaten, dem EA-Freeware-Release von 2008, den
EA-Source-Releases und den C&C Franchise Modding Guidelines in
[Recherche 01, §8](docs/research/01-openra-assets-und-daten.md).

*This project is not endorsed by or affiliated with Electronic Arts.*
