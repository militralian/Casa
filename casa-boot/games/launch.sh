#!/bin/sh
BASE=/mnt/us/Casa/Games
ROM="$1"
[ -f "$BASE/fbgnuboy" ] || exit 127
[ -f "$ROM" ] || exit 2
# Freeze KOReader while gnuboy owns the framebuffer, then resume Casa on exit.
if pidof reader.lua >/dev/null 2>&1; then
  killall -STOP reader.lua
  HOME=/tmp "$BASE/fbgnuboy" "$ROM"
  RESULT=$?
  killall -CONT reader.lua
  exit "$RESULT"
fi
HOME=/tmp "$BASE/fbgnuboy" "$ROM"
