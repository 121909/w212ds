#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

# Wait for Android to finish booting, then watch ONLY for insertion events
# (usb/online 0 -> 1). On each insertion we decide once and go back to idle —
# no polling of the switch, no enforcement. Unplug is handled by the system.
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done
sleep 10

prev="$(cat "$USB_ONLINE_NODE" 2>/dev/null)"
while true; do
  cur="$(cat "$USB_ONLINE_NODE" 2>/dev/null)"
  if [ "$prev" != "1" ] && [ "$cur" = "1" ]; then
    apply_once
  fi
  prev="$cur"
  sleep 1
done