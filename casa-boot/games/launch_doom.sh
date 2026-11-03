#!/bin/sh
BASE=/mnt/us/Casa/Games
[ -x "$BASE/doom" ] || exit 127
[ -f "$BASE/doom1.wad" ] || exit 2
PAUSED=0
if pidof reader.lua >/dev/null 2>&1; then
  killall -STOP reader.lua
  PAUSED=1
fi
resume_casa() {
  if [ "$PAUSED" = 1 ]; then killall -CONT reader.lua 2>/dev/null || true; fi
}
trap resume_casa EXIT HUP INT TERM
cd "$BASE" || exit 1
HOME=/tmp "$BASE/doom" -iwad "$BASE/doom1.wad" -episode 1 --mode greyscale
RESULT=$?
exit "$RESULT"
