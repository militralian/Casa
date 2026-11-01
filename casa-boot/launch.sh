#!/bin/sh
BASE=/mnt/us/casa
/bin/sh "$BASE/install.sh"
# Open Casa even if boot registration could not be completed.
pidof reader.lua >/dev/null 2>&1 && exit 0
pidof luajit >/dev/null 2>&1 && exit 0
exec /bin/sh /mnt/us/koreader/koreader.sh --kual --framework_stop
