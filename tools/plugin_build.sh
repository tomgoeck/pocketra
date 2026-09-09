#!/bin/sh
# Das Android-Plugin "PocketRaPlugin" bauen (docs/MULTIPLAYER.md §10 und §11.3).
#
# Zwei Aufgaben in einer AAR: lokale Benachrichtigungen samt Vordergrunddienst (§10) und die
# eigene AudioRecord-Quelle fuer den Sprechfunk (§11.3) — Godots Android-Eingang ist fest auf
# 44 100 Hz verdrahtet und bleibt auf 48-kHz-Geraeten stumm.
#
#   sh tools/plugin_build.sh              # debug + release
#   sh tools/plugin_build.sh debug
#
# Ergebnis: game/addons/pocketra_plugin/bin/pocketra_plugin-{debug,release}.aar
# Die AAR liegt nicht im Git (siehe .gitignore) — sie wird gebaut wie die Extension unter gdext/.
#
# Voraussetzungen (einmalig):
#   * Android SDK unter ~/Library/Android/sdk (steht schon in Godots Editor-Einstellungen)
#   * JDK 17 — Godot benutzt /opt/homebrew/opt/openjdk@17; ein neueres JDK verweigert Gradle 8.
#   * Netz: Gradle-Wrapper und die Abhaengigkeiten (org.godotengine:godot, okhttp) kommen aus
#     Maven Central bzw. Google Maven.
#
# Ohne diesen Bau fehlt die AAR: `addons/pocketra_plugin/export_plugin.gd` warnt beim Export und
# haengt nichts ein, `net_notify.gd` und `voice_chat.gd` finden den Singleton nicht — das Spiel
# laeuft unveraendert, nur ohne Benachrichtigungen im Hintergrund und mit Godots eigenem
# Mikrofoneingang (der auf manchen Android-Geraeten stumm bleibt, s. §11.3).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/android/pocketra_plugin"
OUT="$ROOT/game/addons/pocketra_plugin/bin"
WHAT=${1:-alle}
JDK=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
[ -d "$JDK" ] || { echo "JDK 17 fehlt: $JDK (brew install openjdk@17)"; exit 1; }
[ -d "$SDK" ] || { echo "Android SDK fehlt: $SDK"; exit 1; }
mkdir -p "$OUT"
echo "sdk.dir=$SDK" > "$SRC/local.properties"

# Gradle: der Wrapper des Godot-Bauverzeichnisses, sonst ein Gradle aus dem PATH
GRADLE=""
if [ -n "$GRADLE_BIN" ] && [ -x "$GRADLE_BIN" ]; then
    GRADLE="$GRADLE_BIN"
elif [ -x "$ROOT/game/android/build/gradlew" ]; then
    GRADLE="$ROOT/game/android/build/gradlew"
elif [ -x "$SRC/gradlew" ]; then
    GRADLE="$SRC/gradlew"
elif command -v gradle > /dev/null 2>&1; then
    GRADLE=$(command -v gradle)
else
    # Godot legt seine Gradle-Verteilungen unter ~/.gradle/wrapper/dists ab — eine davon reicht.
    # AGP 8.7 braucht mindestens Gradle 8.9; die juengste passende nehmen.
    GRADLE=$(ls -1 "$HOME"/.gradle/wrapper/dists/gradle-*/*/gradle-*/bin/gradle 2>/dev/null | sort | tail -1)
fi
if [ -z "$GRADLE" ]; then
    echo "Kein Gradle gefunden."
    echo "  a) Android-Bauvorlage installieren (bringt gradlew mit):"
    echo "     Godot --headless --path game --install-android-build-template --export-debug Android /tmp/x.apk"
    echo "  b) oder: brew install gradle"
    echo "  c) oder: GRADLE_BIN=/pfad/zu/gradle sh tools/plugin_build.sh"
    exit 1
fi
echo "Gradle: $GRADLE"

cd "$SRC"
export JAVA_HOME="$JDK"
export ANDROID_HOME="$SDK"
case "$WHAT" in
    debug)   TASKS="assembleDebug" ;;
    release) TASKS="assembleRelease" ;;
    *)       TASKS="assembleDebug assembleRelease" ;;
esac
"$GRADLE" --project-dir "$SRC" $TASKS

for t in debug release; do
    A="$SRC/build/outputs/aar/pocketra_plugin-$t.aar"
    [ -f "$A" ] && cp "$A" "$OUT/pocketra_plugin-$t.aar" && echo "→ $OUT/pocketra_plugin-$t.aar"
done
echo "Fertig. Danach im Export-Preset 'Use Gradle Build' einschalten und das Addon aktivieren"
echo "(project.godot [editor_plugins] enabled → res://addons/pocketra_plugin/plugin.cfg)."
