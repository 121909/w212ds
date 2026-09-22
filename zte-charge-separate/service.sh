#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
TH_LATCH=0

# Wait for Android to finish booting. Single loop, two cadences:
# - every 1s: watch insertion events (usb/online 0 -> 1) and decide once
#   (PC / charger mode 1). Unplug is handled by the system.
# - every 30s: threshold mode state machine (charger mode 2), lightweight
#   polling copied from the Magisk reference, at a 30s interval.
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done
sleep 10

prev="$(cat "$USB_ONLINE_NODE" 2>/dev/null)"
tick=0
while true; do
  cur="$(cat "$USB_ONLINE_NODE" 2>/dev/null)"
  if [ "$prev" != "1" ] && [ "$cur" = "1" ]; then
    apply_once
  fi
  if [ "$prev" = "1" ] && [ "$cur" != "1" ]; then
    TH_LATCH=0
  fi
  prev="$cur"
  tick=$((tick + 1))
  if [ "$tick" -ge 30 ]; then
    tick=0
    threshold_tick
  fi
  sleep 1
done
