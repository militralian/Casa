#!/bin/sh
BASE=/mnt/us/casa
# Give Kindle framework and user storage time to finish normal startup.
sleep 55
[ -f "$BASE/DISABLE_AUTOSTART" ] && exit 0
[ -f /mnt/us/koreader/koreader.sh ] || exit 0
# SSH/SFTP first, independent of Casa, so the Mac can always reach and fix the Kindle.
/bin/sh /mnt/us/koreader/plugins/casa.koplugin/sftp.sh start >/dev/null 2>&1
# Do not start two reader processes.
pidof reader.lua >/dev/null 2>&1 && exit 0
pidof luajit >/dev/null 2>&1 && exit 0
# Run once; on exit or failure there is no restart loop.
/bin/sh /mnt/us/koreader/koreader.sh >>"$BASE/boot.log" 2>&1
