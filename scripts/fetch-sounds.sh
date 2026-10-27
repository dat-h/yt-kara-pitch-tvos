#!/bin/sh
# Rebuilds the audience reaction sounds from CC0 crowd recordings on Wikimedia Commons and
# Freesound (see KaraPitchTV/Resources/sounds/CREDITS.md). Needs ffmpeg. Run from the repo root:
#   sh scripts/fetch-sounds.sh
set -eu

out=KaraPitchTV/Resources/sounds
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() {
    curl -fsSL -A "KaraPitchTV sound fetch (https://github.com/dat-h/yt-kara-pitch-tvos)" -o "$work/$1" "$2"
    sleep 2  # both sites rate-limit quick bursts
}

fetch applause.wav "https://commons.wikimedia.org/wiki/Special:FilePath/277021_sandermotions_applause-2.wav"
# Freesound's public high-quality previews (128 kbps MP3), so no account is needed.
fetch concert.mp3 "https://cdn.freesound.org/previews/130/130568_2024417-hq.mp3"
fetch stadium.mp3 "https://cdn.freesound.org/previews/397/397434_4019029-hq.mp3"
fetch booing.mp3 "https://cdn.freesound.org/previews/25/25270_173513-hq.mp3"
fetch laughing.mp3 "https://cdn.freesound.org/previews/25/25296_173513-hq.mp3"

# Every clip gets the same loudness, so no reaction is much louder than another, except the
# ovation, which is meant to be the big one.
norm="loudnorm=I=-18:TP=-1.5:LRA=11,aresample=44100"
loud="loudnorm=I=-15:TP=-1.5:LRA=11,aresample=44100"
encode="-ac 2 -c:a aac -b:a 128k -movflags +faststart"

# Clap: a polite round of applause that swells and fades.
ffmpeg -v error -y -i "$work/applause.wav" \
    -af "atrim=0.3:4.6,asetpts=N/SR/TB,afade=t=in:d=0.15,afade=t=out:st=3.0:d=1.3,$norm" $encode "$out/clap.m4a"
# Ovation: a roaring rock-concert audience with a sports crowd's cheering layered in.
ffmpeg -v error -y -i "$work/concert.mp3" -i "$work/stadium.mp3" -filter_complex \
    "[0:a]atrim=12.5:18.5,asetpts=N/SR/TB,aformat=channel_layouts=stereo,aresample=44100[a];\
[1:a]atrim=1:7,asetpts=N/SR/TB,volume=-3dB,aformat=channel_layouts=stereo,aresample=44100[b];\
[a][b]amix=inputs=2:normalize=0,afade=t=in:d=0.15,afade=t=out:st=4.5:d=1.5,$loud" $encode "$out/ovation.m4a"
# Boo: an audience of 300+ booing.
ffmpeg -v error -y -i "$work/booing.mp3" \
    -af "atrim=0.4:5.4,asetpts=N/SR/TB,afade=t=in:d=0.1,afade=t=out:st=4.0:d=1.0,$norm" $encode "$out/boo.m4a"
# Laugh: the same 300+ audience laughing.
ffmpeg -v error -y -i "$work/laughing.mp3" \
    -af "atrim=3:8,asetpts=N/SR/TB,afade=t=in:d=0.15,afade=t=out:st=4.0:d=1.0,$norm" $encode "$out/laugh.m4a"

ls -l "$out"
