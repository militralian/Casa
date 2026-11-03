#!/bin/sh
# SSH/SFTP server for Casa (KOReader's bundled dropbear), key-only login on port 2222.
# It must be stopped before USB drive mode: it runs from /mnt/us and would keep it busy.
KO=/mnt/us/koreader
PORT=2222
PIDFILE=/tmp/dropbear_koreader.pid
running() { [ -f "$PIDFILE" ] && [ -d "/proc/$(cat $PIDFILE)" ]; }
case "$1" in
 start)
  running && exit 0
  # No authorized key installed (tools/crea-chiave): key-only login would be useless, stay off.
  [ -f "$KO/plugins/casa.koplugin/authorized_keys" ] || exit 0
  mkdir -p "$KO/settings/SSH"
  cp "$KO/plugins/casa.koplugin/authorized_keys" "$KO/settings/SSH/authorized_keys"
  # Kindle firewall: open the port once (delete first so rules never pile up).
  iptables -D INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null
  iptables -D OUTPUT -p tcp --sport $PORT -j ACCEPT 2>/dev/null
  iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
  iptables -I OUTPUT -p tcp --sport $PORT -j ACCEPT
  cd "$KO" && ./dropbear -R -s -p $PORT -P "$PIDFILE" </dev/null >/dev/null 2>&1
  sleep 1
  running && echo "SFTP=on" || echo "SFTP=error"
  ;;
 stop)
  if running; then pid=$(cat "$PIDFILE"); pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; fi
  rm -f "$PIDFILE"
  ;;
esac
