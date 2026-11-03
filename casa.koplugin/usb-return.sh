#!/bin/sh
# Runs from /var/tmp so it never keeps /mnt/us busy while the Mac owns the drive.
# Waits for: KOReader closed -> drive exported over USB -> cable unplugged, then reopens Casa.
LOG=/var/tmp/casa-usb-return.log
cd /
echo "$(date) avvio" >"$LOG"
# /mnt/us (fuse) stays listed during USB export; the vfat /mnt/base-us is what the Mac takes.
mounted() { grep -q " /mnt/base-us " /proc/mounts; }
i=0
while pidof reader.lua >/dev/null 2>&1; do
 sleep 1; i=$((i+1)); [ $i -gt 60 ] && echo "KOReader non si chiude" >>"$LOG" && exit 1
done
echo "$(date) Casa chiusa, aspetto il cavo" >>"$LOG"
# Up to 10 minutes to plug the cable in; otherwise just reopen Casa.
i=0
while mounted && [ $i -lt 600 ]; do sleep 1; i=$((i+1)); done
if ! mounted; then
 echo "$(date) unità USB attiva" >>"$LOG"
 while ! mounted; do sleep 2; done
 echo "$(date) cavo scollegato" >>"$LOG"
 # Let the Kindle finish re-indexing the drive before KOReader stops its services.
 sleep 8
else
 echo "$(date) nessun cavo collegato" >>"$LOG"
fi
pidof reader.lua >/dev/null 2>&1 && exit 0
[ -f /mnt/us/koreader/koreader.sh ] || exit 1
cat "$LOG" >>/mnt/us/casa/usb-return.log 2>/dev/null
exec /bin/sh /mnt/us/koreader/koreader.sh >>/mnt/us/casa/boot.log 2>&1
