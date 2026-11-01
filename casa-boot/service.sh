#!/bin/sh
# CASA_HOME_SERVICE
case "${1:-start}" in
 start)
  # Fork before returning so system startup never waits on KOReader.
  /bin/sh /mnt/us/casa/boot.sh </dev/null >/dev/null 2>&1 &
  ;;
esac
exit 0
