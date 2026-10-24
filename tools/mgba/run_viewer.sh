#!/bin/zsh
# usage: run_viewer.sh [rom]
# Start the mGBA development build (/Applications/mGBA.app, 0.11+) with Radical Red and the AI
# score viewer loaded. The save file lives next to the ROM (roms/rr.sav).
here=${0:A:h}
repo=${here:h:h}
[[ -f $repo/.env ]] && source $repo/.env
rom=${1:-${RADICAL_RED_ROM:-$repo/roms/rr.gba}}
exec /Applications/mGBA.app/Contents/MacOS/mGBA --script $here/rr_ai_viewer.lua $rom
