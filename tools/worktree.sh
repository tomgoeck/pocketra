#!/bin/sh
# Git-Worktree für parallele Feature-Arbeit anlegen: build/wt/NAME auf Branch feature/NAME (ab master).
# Nicht eingecheckte, aber nötige Verzeichnisse werden per APFS-Klon (cp -c, sofort, platzsparend)
# bzw. Symlink mitgegeben, damit Tests, scons und Godot-Import im Worktree unabhängig laufen.
#   tools/worktree.sh NAME        # anlegen
#   tools/worktree.sh -d NAME     # entfernen (Branch bleibt)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "$1" = "-d" ]; then
    git -C "$ROOT" worktree remove --force "build/wt/$2"
    exit 0
fi
NAME=$1
WT="$ROOT/build/wt/$NAME"
mkdir -p "$ROOT/build/wt"
git -C "$ROOT" worktree add -b "feature/$NAME" "$WT" master
rm -rf "$WT/gdext/godot-cpp"
cp -cR "$ROOT/gdext/godot-cpp" "$WT/gdext/godot-cpp"     # eigener Bindings-Baum je Worktree (scons schreibt hinein)
# Submodul-Verweis (.git-Datei) zeigt relativ auf das Hauptrepo und ist aus dem Worktree nicht auflösbar → absolut
if [ -f "$WT/gdext/godot-cpp/.git" ]; then
    echo "gitdir: $ROOT/.git/modules/gdext/godot-cpp" > "$WT/gdext/godot-cpp/.git"
fi
cp -cR "$ROOT/game/assets" "$WT/game/assets"
[ -d "$ROOT/game/.godot" ] && cp -cR "$ROOT/game/.godot" "$WT/game/.godot"
for f in "$ROOT"/game/bin/librasim.*; do cp -c "$f" "$WT/game/bin/"; done
ln -s "$ROOT/content" "$WT/content"
ln -s "$ROOT/reference" "$WT/reference"
echo "Worktree: $WT (Branch feature/$NAME)"
