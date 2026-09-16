#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

# Wait for Android to finish booting before touching anything.
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done
sleep 10

while true; do
  apply_state
  sleep 5
done