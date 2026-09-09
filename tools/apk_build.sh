#!/bin/sh
# Saubere APK aus dem letzten master-Commit bauen — unabhängig von uncommitteten Änderungen im Hauptbaum.
# Ablauf: Worktree build/wt/apk auf master setzen, erzeugte Daten (rules.json, Karten) frisch aus dem
# Hauptbaum spiegeln, Android-Extension bauen, importieren, exportieren. Optional: --install (adb, Handy).
#   tools/apk_build.sh [--dist] [--install] [--ref REF] [--wt NAME] [--no-gradle]
# --ref baut aus einem anderen Commit/Zweig als master (Prueflauf eines Zweiges, z. B.
# `--ref feature/mp-hintergrund`), --wt nimmt einen anderen Arbeitsbaum als build/wt/apk (damit
# zwei Laeufe sich nicht in die Quere kommen).
#
# GRADLE-BAU (seit 2026-09-09, docs/MULTIPLAYER.md §10.5): die beiden APK-Presets stehen auf
# `gradle_build/use_gradle_build=true`, weil das Benachrichtigungs-Plugin (Android-Plugin-Format v2)
# nur so in die APK kommt. Das Skript kuemmert sich um beides:
#   * `tools/plugin_build.sh` baut die AAR (sie liegt nicht im Git),
#   * fehlt `game/android/build/`, installiert es die Android-Bauvorlage aus android_source.zip.
# Voraussetzungen: JDK 17 (Godots Editor-Einstellung `export/android/java_sdk_path`), Android SDK,
# und beim ersten Lauf Netz — Gradle laedt seine Abhaengigkeiten. Der erste Gradle-Lauf dauert
# mehrere Minuten, spaetere rund eine Minute.
# --no-gradle schaltet im Arbeitsbaum (nicht im Git!) auf die vorgefertigten Vorlagen zurueck: der
# Notausgang, wenn der Gradle-Bau klemmt, und der Weg fuer einen Groessenvergleich. Die so gebaute
# APK hat **kein** Benachrichtigungs-Plugin und minSdk 24 statt 29.
# --dist baut mit dem Preset „Android Verteilung" statt „Android": ohne EA-Inhalte (Atlanten, Sound-/
# Stimmeffekte, Missionsfilme — export_filter in game/export_presets.cfg schließt sie aus, Toms eigenes
# Intro liegt bewusst außerhalb von assets/video/ unter assets/intro/ und bleibt drin). Nur zum
# Größenmessen gedacht — eine so gebaute APK startet ohne user://content/ auf der Seite „Spielinhalte
# einrichten" (ContentPage) und lässt sich vor dem ersten Freeware-Download nicht spielen; --install
# installiert sie trotzdem probeweise, wenn ausdrücklich verlangt.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=/Applications/Godot.app/Contents/MacOS/Godot
DIST=""
INSTALL=""
REF=master
NAME=apk
NOGRADLE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dist) DIST=1 ;;
        --install) INSTALL=1 ;;
        --ref) REF=$2; shift ;;
        --wt) NAME=$2; shift ;;
        --no-gradle) NOGRADLE=1 ;;
        *) echo "unbekannter Schalter: $1"; exit 1 ;;
    esac
    shift
done
WT="$ROOT/build/wt/$NAME"
if [ -n "$DIST" ]; then
    PRESET="Android Verteilung"
    OUT="$ROOT/build/pocketra-dist.apk"
else
    # Vollfassung (EA-Inhalte in der APK). Sie bleibt fuer Toms eigenen Gebrauch, den
    # Groessenvergleich und Prueflaeufe — veroeffentlicht wird sie seit Toms Regel 2026-09-09
    # NICHT mehr; tools/update_pack.sh laedt nur build/pocketra-dist.apk hoch.
    PRESET="Android"
    OUT="$ROOT/build/pocketra-full.apk"
fi
# Arbeitsbaum anlegen (losgeloest, ohne eigenen Zweig) und mit dem noetigen Nicht-Git-Zubehoer
# ausstatten — wie tools/worktree.sh, aber ohne `feature/<name>` anzulegen.
if [ ! -d "$WT" ]; then
    mkdir -p "$ROOT/build/wt"
    git -C "$ROOT" worktree add -q --detach "$WT" "$REF"
    rm -rf "$WT/gdext/godot-cpp"
    cp -cR "$ROOT/gdext/godot-cpp" "$WT/gdext/godot-cpp"
    if [ -f "$WT/gdext/godot-cpp/.git" ]; then
        echo "gitdir: $(git -C "$ROOT" rev-parse --git-common-dir)/modules/gdext/godot-cpp" \
            > "$WT/gdext/godot-cpp/.git"
    fi
    [ -d "$ROOT/game/.godot" ] && cp -cR "$ROOT/game/.godot" "$WT/game/.godot"
    for f in "$ROOT"/game/bin/librasim.*; do cp -c "$f" "$WT/game/bin/"; done
    [ -e "$WT/content" ] || ln -s "$ROOT/content" "$WT/content"
    [ -e "$WT/reference" ] || ln -s "$ROOT/reference" "$WT/reference"
    echo "Arbeitsbaum angelegt: $WT"
fi
git -C "$WT" reset -q --hard && git -C "$WT" clean -qfd -- tools && git -C "$WT" checkout -q --detach "$REF"
echo "Baue aus $REF ($(git -C "$WT" log --format=%h -1)) in $WT"
# rules.json und Karten gehören zusammen (rules_format-Stempel) — beide im Hauptbaum erzeugen, dann spiegeln
(cd "$ROOT" && python3 tools/rules2json.py >/dev/null && python3 tools/mapconvert.py >/dev/null)
mkdir -p "$WT/game/assets"
rsync -a --delete "$ROOT/game/assets/" "$WT/game/assets/"
(cd "$WT/gdext" && scons platform=android arch=arm64 target=template_debug -j10 \
    ANDROID_HOME="$HOME/Library/Android/sdk" ndk_version=28.2.13676358 | tail -1)
if [ -n "$NOGRADLE" ]; then
    # Nur im Arbeitsbaum zuruecksetzen — das Repository bleibt beim Gradle-Bau
    sed -i '' 's|gradle_build/use_gradle_build=true|gradle_build/use_gradle_build=false|' \
        "$WT/game/export_presets.cfg"
    echo "Gradle-Bau abgeschaltet (nur fuer diesen Lauf): vorgefertigte Vorlagen, kein Plugin"
fi
# Gradle-Bau: Benachrichtigungs-Plugin (AAR liegt nicht im Git) und Android-Bauvorlage
if grep -q 'gradle_build/use_gradle_build=true' "$WT/game/export_presets.cfg"; then
    [ -x "$WT/tools/plugin_build.sh" ] && sh "$WT/tools/plugin_build.sh" | tail -3
    if [ ! -f "$WT/game/android/build/build.gradle" ]; then
        echo "Android-Bauvorlage fehlt — wird installiert …"
        "$G" --headless --path "$WT/game" --install-android-build-template \
            --export-debug "$PRESET" "$OUT" 2>&1 | tail -20 || true
    fi
fi
"$G" --headless --path "$WT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' | sed 's/^/Skriptfehler beim Import: /'
"$G" --headless --path "$WT/game" --export-debug "$PRESET" "$OUT" 2>&1 | grep -E 'DONE.*export|^ERROR' | head -2
ls -la "$OUT" | awk '{print "APK (" p "): " $5/1e6 " MB"}' p="$PRESET"
# Kurze Sichtprobe ohne Geraet: liegt das Plugin drin, steht der Dienst im Manifest?
AAPT=$(ls -1 "$HOME"/Library/Android/sdk/build-tools/*/aapt2 2>/dev/null | sort | tail -1)
if [ -n "$AAPT" ]; then
    "$AAPT" dump badging "$OUT" 2>/dev/null | grep -E "^package:|^minSdkVersion|^targetSdkVersion" \
        | sed 's/^/  /'
    "$AAPT" dump permissions "$OUT" 2>/dev/null | sed -n "s/^uses-permission: name='\(.*\)'/  Berechtigung: \1/p"
    if "$AAPT" dump xmltree --file AndroidManifest.xml "$OUT" 2>/dev/null \
            | grep -q "net.pocketra.app.plugin.WatchService"; then
        echo "  Benachrichtigungs-Plugin: Dienst steht im Manifest"
    else
        echo "  Benachrichtigungs-Plugin: NICHT in der APK"
    fi
fi
if [ -n "$INSTALL" ]; then
    adb devices | grep -q 'device$' || { echo "kein Gerät"; exit 1; }
    adb install -r "$OUT" | tail -1
    adb shell am start -n net.pocketra.app/com.godot.game.GodotAppLauncher | tail -1
fi
