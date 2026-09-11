<p align="center">
  <img src="https://pocketra.net/img/mission-soviet-01.png" alt="PocketRA gameplay: a Soviet mission with a radar dome and defenses in the snow" width="640">
</p>

<h1 align="center">PocketRA</h1>
<p align="center"><em>Command &amp; Conquer: Red Alert, rebuilt for touch, with multiplayer by game code and game logic that follows OpenRA.</em></p>

<p align="center">
  <a href="https://pocketra.net"><img alt="Website" src="https://img.shields.io/badge/website-pocketra.net-ffd140?style=flat-square"></a>
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--or--later-4c6ef5?style=flat-square">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS-8c7540?style=flat-square">
</p>

**EA has not endorsed and does not support this product.** *Command & Conquer* and *Red Alert* are
trademarks of Electronic Arts Inc. PocketRA is a free, non-commercial fan project with no
affiliation to EA or Westwood Studios, and this repository contains no EA game data. See
[Legal](#legal) below for the details.

## What it is

PocketRA rebuilds *Command & Conquer: Red Alert* from scratch for the phone in your pocket.
Interface and touch controls run in Godot 4, and the game simulation itself runs in C++
(GDExtension), deterministic and integer-only, at 25 ticks per second like the original. Damage,
armour, ranges, build times, pathfinding, superweapons and AI follow the open rule files of
[OpenRA](https://www.openra.net); deviations are marked as such in the code.

## Downloads

| Platform | Get it |
|---|---|
| Android | [Download the APK](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-dist.apk). Not on the Play Store, so allow installs from this source once. |
| iOS | [Join the TestFlight beta](https://testflight.apple.com/join/vE3V2vBf). No App Store review yet. |
| Windows | [Download the installer](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-windows-setup.exe). Built for touch, meant for trying out. |
| macOS | [Download the disk image](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-macos.dmg). Built for touch, meant for trying out. |

All release notes and install steps: **[pocketra.net](https://pocketra.net)**. Source code and
issues live here, and every release is also attached to this repository's
[Releases page](https://github.com/tomgoeck/pocketra/releases).

## What's inside

- **Skirmish** against up to five AI opponents at three strengths, with 142 maps from OpenRA in
  temperate and snow, all units, superweapons, ships and aircraft, and save/load.
- **Multiplayer by game code.** Open a room and share a six-character code with friends: no
  account, no sign-up. Lockstep like OpenRA, so only orders are transmitted and every device
  simulates the same match, with text chat and hold-to-talk voice. Your seat is kept if a
  notification drops you out.
- **Tutorial** mission that walks through base building, the build bar, command bar, radial menu
  and gestures step by step, narrated in German and English.
- German and English throughout, with German voice lines pulled from your own CD.
- Self-updating: the app fetches new content on start, so no reinstall is needed for content
  updates.
- Note: campaign missions are imported but not reliably playable yet. Some run, many break or
  can't be won, so the menu marks them as "in testing". Skirmish and multiplayer are the finished
  part of the game.
- No map editor, no mods yet.

## Screenshots

<p align="center">
  <img src="https://pocketra.net/img/menu.png" width="45%">
  <img src="https://pocketra.net/img/lobby.png" width="45%">
  <br>
  <img src="https://pocketra.net/img/create.png" width="45%">
  <img src="https://pocketra.net/img/mission-soviet-01.png" width="45%">
</p>

### Gameplay

<p align="center"><img src="https://pocketra.net/img/battle.gif" width="70%"></p>

## Layout

| Folder | Contents |
|---|---|
| `game/` | Godot project (GDScript, scenes, translations, icons) |
| `gdext/` | GDExtension bridge to the simulation, `godot-cpp` as a submodule |
| `sim/` | C++ simulation (deterministic, integer-only) and tests |
| `tools/` | Pipeline: MIX/SHP/AUD/VQA from the original game files to atlases, sounds, maps and rules |

## Building

Requirements: Godot 4.7, Python 3.11+, SCons, ffmpeg, Android SDK/NDK for the APK.

1. Get the game data (not in this repository): unpack `ra-quickinstall.zip` from an OpenRA mirror
   (list: https://www.openra.net/packages/ra-quickinstall-mirrors.txt) into `content/ra/`, or copy
   `MAIN.MIX`/`REDALERT.MIX` from your own CD there.
2. OpenRA reference for rules and maps: `git clone --depth 1 https://github.com/OpenRA/OpenRA reference/OpenRA`
3. Pipeline (creates `game/assets/`):
   ```bash
   python3 tools/rules2json.py
   python3 tools/tileset2atlas.py temperat && python3 tools/tileset2atlas.py snow && python3 tools/tileset2atlas.py interior
   python3 tools/mapconvert.py
   python3 tools/audconvert.py $(cat tools/sounds.txt) -o game/assets/sfx
   ```
4. Simulation and bridge:
   ```bash
   sim/tests/run.sh
   git submodule update --init
   cd gdext && scons platform=macos arch=arm64 target=template_debug
   cd gdext && scons platform=android arch=arm64 target=template_debug
   ```
5. Godot: `Godot --headless --path game --import`, then `Godot --path game` to run, or
   `Godot --headless --path game --export-debug Android ../build/pocketra.apk`.

## Legal

PocketRA is a free, non-commercial fan project. It is not endorsed by Electronic Arts and not
affiliated with Electronic Arts or Westwood Studios. *Command & Conquer* and *Red Alert* are
trademarks of Electronic Arts Inc.

The original game files are used, as in OpenRA, under the licence granted by Electronic Arts'
C&C Franchise Modding Guidelines: free of charge, non-commercial and without any music files from
C&C games. Neither this repository nor the app contains or distributes those files; the app
downloads the freely available base files from the same mirrors OpenRA uses, or reads them from
your own copy of the game.

PocketRA's own source code is licensed under the GNU General Public License, version 3 or later
(`LICENSE`, GPL-3.0-or-later). The game rules are derived from the rule files of
[OpenRA](https://www.openra.net), which are also GPLv3. PocketRA is an independent project and not
part of OpenRA; origin notes for third-party code and assets are in `NOTICE`.

This is an automatically generated, comment-free publication copy (`tools/publish.py`).
