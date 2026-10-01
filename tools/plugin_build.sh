#!/bin/sh
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
