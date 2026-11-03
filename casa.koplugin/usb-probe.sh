#!/bin/sh
# Tells a computer (USB host) from a wall charger after the cable is plugged in.
# "start" runs at plug-in time, "check" a few seconds later and prints HOST=1 or HOST=0.
STATE=/var/tmp/casa-usb-probe.count
LOG=/mnt/us/casa/usb-probe.log
UDC=/sys/devices/platform/fsl-usb2-udc
case "$1" in
 start)
  dmesg 2>/dev/null | wc -l >"$STATE"
  ;;
 check)
  before=$(cat "$STATE" 2>/dev/null); [ -n "$before" ] || before=0
  new=$(dmesg 2>/dev/null | tail -n +$((before+1)))
  host=0
  # A computer enumerates the Kindle as a USB device; a wall charger never does.
  echo "$new" | grep -i -e config -e speed -e enumerat -e "usb host" -e gadget >/dev/null && host=1
  for f in connected host_connected; do
   [ "$(cat $UDC/$f 2>/dev/null)" = "1" ] && host=1
  done
  {
   echo "== $(date) HOST=$host"
   for f in $UDC/*; do [ -f "$f" ] && echo "$(basename $f)=$(head -c 120 $f 2>/dev/null | tr '\n' ' ')"; done
   echo "-- dmesg nuovo"
   echo "$new" | tail -25
  } >>"$LOG" 2>&1
  echo "HOST=$host"
  ;;
esac
