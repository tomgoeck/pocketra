#!/bin/sh
# Ausgeliefertes Start-Intro (game/assets/intro/intro.ogv) aus Toms eigenem Schnitt bauen:
# Aufnahme bis 9,15 s, 0,25 s Blende, dann die Titeltafel title_card.png bis 12,64 s. Der Ton bleibt
# unveraendert aus intro_final_tom.mp4, damit der Einschlag weiter auf dem Titel sitzt.
#
# Der Schnitt ist wiederholbar: die ersten 9,15 s bleiben unangetastet, ein erneuter Lauf erzeugt
# dasselbe Ergebnis. Nach einer neuen title_card.png also einfach nochmal aufrufen.
#
# Anderes Intro: assemble.sh baut die laengere Fassung intro_final.mp4 (1280x720) aus shot1/shot2.
set -e
cd "$(dirname "$0")"
FF=${FFMPEG:-/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg}   # Theora/Vorbis nur in ffmpeg-full
$FF -y -v error -i intro_final_tom.mp4 -loop 1 -framerate 30 -i title_card.png \
  -filter_complex "[0:v]trim=0:9.15,setpts=PTS-STARTPTS,fps=30,scale=836:480,format=yuv420p[a];\
[1:v]scale=836:480,fps=30,trim=duration=3.733,setpts=PTS-STARTPTS,fade=t=out:st=3.53:d=0.2,format=yuv420p[b];\
[a][b]xfade=transition=fade:duration=0.25:offset=8.9,format=yuv420p[v]" \
  -map "[v]" -map 0:a -c:v libx264 -crf 18 -c:a aac -b:a 160k -t 12.64 neu.mp4
mv neu.mp4 intro_final_tom.mp4
mkdir -p ../../game/assets/intro
$FF -y -v error -i intro_final_tom.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 ../../game/assets/intro/intro.ogv
ls -la intro_final_tom.mp4 ../../game/assets/intro/intro.ogv | awk '{print $5, $9}'
