#!/bin/sh
# Start-Intro zusammensetzen: shot1_tanks.mp4 (Higgsfield, Tom) + shot2_v2.mp4 (Veo 3.1 Lite) + Titeltafel
# → intro_final.mp4 (1280×720, 24 fps) und game/assets/video/intro_custom.ogv (Theora, 854×480); intro.tscn spielt es erst nach Toms Freigabe.
set -e
cd "$(dirname "$0")"
FF=/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg
SFX=../../game/assets/sfx
# Titel: 3,5 s, Einschlag in 6 Frames (Zoom 3→1 mit Wackeln), dann Halten und Ausblenden; Schlag = kaboom25 + bleep17
$FF -y -loglevel error -loop 1 -framerate 24 -i title_card.png -i $SFX/kaboom25.wav -i $SFX/crmble2.wav \
  -filter_complex "[0:v]scale=1280:720,zoompan=z='if(lte(on,6),3-2*on/6,1)':x='iw/2-(iw/zoom/2)+if(lte(on,10),(random(1)-0.5)*40,0)':y='ih/2-(ih/zoom/2)+if(lte(on,10),(random(1)-0.5)*40,0)':d=1:s=1280x720:fps=24,trim=duration=3.5,fade=t=out:st=3.0:d=0.5,format=yuv420p[v];[1:a]volume=1.4[a1];[2:a]adelay=120|120,volume=0.8[a2];[a1][a2]amix=inputs=2:duration=longest,apad=whole_dur=3.5,aresample=48000[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -crf 18 -c:a aac -b:a 160k -t 3.5 title.mp4
# Shots angleichen: 1280×720, 24 fps, 48 kHz Stereo
$FF -y -loglevel error -i shot1_tanks.mp4 -vf "scale=1280:-2,crop=1280:720,fps=24,format=yuv420p" -af "aresample=48000" -c:v libx264 -crf 18 -c:a aac -b:a 160k s1.mp4
$FF -y -loglevel error -i shot2_v2.mp4 -vf "scale=1280:720,fps=24,format=yuv420p" -af "aresample=48000" -c:v libx264 -crf 18 -c:a aac -b:a 160k s2.mp4
D1=$(/opt/homebrew/opt/ffmpeg-full/bin/ffprobe -v error -show_entries format=duration -of csv=p=0 s1.mp4)
D2=$(/opt/homebrew/opt/ffmpeg-full/bin/ffprobe -v error -show_entries format=duration -of csv=p=0 s2.mp4)
O1=$(python3 -c "print(max(0.0,$D1-0.6))")
O2=$(python3 -c "print(max(0.0,$D1+$D2-0.6-0.25))")
# Überblendung 0,6 s zwischen den Shots, harter Schnitt zur Titeltafel (kurzer Schwarzblitz 0,25 s durch fade)
$FF -y -loglevel error -i s1.mp4 -i s2.mp4 -i title.mp4 \
  -filter_complex "[1:v]fade=t=out:st=$(python3 -c "print($D2-0.25)"):d=0.25[v1];[0:v][v1]xfade=transition=fade:duration=0.6:offset=$O1[v01];[v01][2:v]xfade=transition=fade:duration=0.25:offset=$O2[v];[0:a][1:a]acrossfade=d=0.6[a01];[a01][2:a]acrossfade=d=0.25[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 160k intro_final.mp4
# Für Godot: Theora/Vorbis, 854×480 (Handy-CPU-freundlich)
mkdir -p ../../game/assets/video
$FF -y -loglevel error -i intro_final.mp4 -vf "scale=854:480" -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 ../../game/assets/video/intro_custom.ogv
rm -f s1.mp4 s2.mp4
ls -la intro_final.mp4 ../../game/assets/video/intro_custom.ogv | awk '{print $5, $9}'
