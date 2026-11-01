#!/bin/sh
# Kindle K4B: SysV boot registration. This runs on the Kindle, as root.
set -eu
BASE=/mnt/us/casa
SERVICE=/etc/init.d/casa-home
LINK=/etc/rc5.d/S99zCasaHome
LOG="$BASE/boot-install.log"
mkdir -p "$BASE"
exec >>"$LOG" 2>&1
if [ ! -d /etc/rc5.d ] || [ ! -d /etc/init.d ] || [ -d /etc/upstart ]; then
 echo 'Not a supported Kindle K4 SysV system'; exit 1
fi
if [ ! -f /mnt/us/koreader/koreader.sh ] || [ ! -f "$BASE/boot.sh" ]; then
 echo 'Missing Casa/KOReader files'; exit 1
fi
if [ -L "$LINK" ] && [ -f "$SERVICE" ] && cmp -s "$BASE/service.sh" "$SERVICE"; then
 echo 'Casa boot already active'; exit 0
fi
mntroot rw
trap 'mntroot ro >/dev/null 2>&1 || true' EXIT
# Refuse to replace an unknown service at our dedicated name.
if [ -e "$SERVICE" ] && ! grep -q 'CASA_HOME_SERVICE' "$SERVICE"; then
 echo 'Service name already used';exit 1
fi
cp "$BASE/service.sh" "$SERVICE"
chmod 755 "$SERVICE"
ln -sf "$SERVICE" "$LINK"
sync
printf 'Installed Casa SysV boot hook\n' > "$BASE/boot-enabled.txt"
echo 'Casa boot enabled'
