#!/bin/sh
# Riattiva il Wi-Fi del Kindle 4 (FW 4.x) e scrive una diagnosi leggibile.
echo "== $(date)"
echo "PRIMA wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1) wifid.enable=$(lipc-get-prop com.lab126.wifid enable 2>&1) cmState=$(lipc-get-prop com.lab126.wifid cmState 2>&1)"
# Toglie la modalità aereo (KOReader su FW 4.x non lo fa) e riaccende wifid.
lipc-set-prop -i com.lab126.cmd wirelessEnable 1 2>&1
lipc-set-prop -i com.lab126.wifid enable 1 2>&1
s=""
i=0
while [ $i -lt 40 ]; do
 s=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
 [ "$s" = "CONNECTED" ] && break
 sleep 1
 i=$((i+1))
done
echo "STATO=$s"
echo "DOPO wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1) wifid.enable=$(lipc-get-prop com.lab126.wifid enable 2>&1)"
echo "-- proprietà wifid"
lipc-probe -v com.lab126.wifid 2>&1 | grep -v -i "psk\|passw" | head -60
echo "-- wlan0"
ifconfig wlan0 2>&1
echo "operstate=$(cat /sys/class/net/wlan0/operstate 2>&1) carrier=$(cat /sys/class/net/wlan0/carrier 2>&1)"
cat /proc/net/wireless 2>&1
echo "-- processi"
ps 2>/dev/null | grep -e wifid -e wpa_ -e dhcp | grep -v grep
echo "-- reti viste"
lipc-get-prop -s com.lab126.wifid scanList 2>&1 | head -40
echo FINE
