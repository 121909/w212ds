#!/system/bin/sh

MODDIR="${0%/*}"
SETTING_KEY="charge_separation_switch"
USB_ONLINE_NODE="/sys/class/power_supply/usb/online"
CHARGER_TYPE_NODE="/sys/class/power_supply/charger_psy/usb_type"
GADGET_NODE="/sys/class/android_usb/android0/state"
LOGFILE="$MODDIR/module.log"
# Track previous connection to act on transitions, not continuously.
LAST_CONN="none"

log() {
  [ -f "$LOGFILE" ] && [ "$(wc -c < "$LOGFILE" 2>/dev/null)" -ge 65536 ] && : > "$LOGFILE"
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOGFILE"
}

# Classify current connection: PC (USB data host) / CHARGER / OFF (unplugged).
detect_conn() {
  if [ "$(cat "$USB_ONLINE_NODE" 2>/dev/null)" != "1" ]; then
    echo "OFF"
    return
  fi
  cur="$(cat "$CHARGER_TYPE_NODE" 2>/dev/null | sed -n 's/^.*\[\([A-Za-z0-9_]*\)\].*$/\1/p')"
  case "$cur" in
    SDP|CDP) echo "PC"; return ;;
    DCP|PD|PD_DRP|BrickID|C) echo "CHARGER"; return ;;
  esac
  if [ "$(cat "$GADGET_NODE" 2>/dev/null)" = "CONFIGURED" ]; then
    echo "PC"; return
  fi
  echo "CHARGER"
}

# Only write when the switch actually differs from desired.
set_switch() {
  desired="$1"
  current="$(settings get global "$SETTING_KEY" 2>/dev/null)"
  if [ "$current" != "$desired" ]; then
    settings put global "$SETTING_KEY" "$desired"
    return 0
  fi
  return 1
}

apply_state() {
  conn="$(detect_conn)"

  # PC attached: always keep separation ON so the UI reflects it.
  if [ "$conn" = "PC" ]; then
    if set_switch 1; then log "conn=PC sep=on"; fi
    LAST_CONN="PC"
    return
  fi

  # Non-PC: on the transition away from PC, restore normal charging once,
  # then leave the switch alone so the user's manual choice on charger is respected.
  if [ "$LAST_CONN" = "PC" ]; then
    if set_switch 0; then log "conn=$conn sep=off"; fi
  fi
  if [ "$conn" = "OFF" ]; then
    LAST_CONN="OFF"
  else
    LAST_CONN="CHARGER"
  fi
}