#!/system/bin/sh

SETTING_KEY="charge_separation_switch"
USB_ONLINE_NODE="/sys/class/power_supply/usb/online"
CHARGER_TYPE_NODE="/sys/class/power_supply/charger_psy/usb_type"
GADGET_NODE="/sys/class/android_usb/android0/state"
CONFIG_FILE="$MODDIR/config.conf"
LOGFILE="/cache/zte-charge-separate.log"

# Load the two toggles: SEP_ON_USB (PC->sep), SEP_ON_CHARGER (charger->sep).
read_config() {
  SEP_ON_USB=1
  SEP_ON_CHARGER=0
  [ -r "$CONFIG_FILE" ] || return 0
  while IFS='=' read -r key value; do
    case "$key" in
      SEP_ON_USB) [ "$value" = "0" ] && SEP_ON_USB=0 ;;
      SEP_ON_CHARGER) [ "$value" = "1" ] && SEP_ON_CHARGER=1 ;;
    esac
  done < "$CONFIG_FILE"
}

log() {
  if [ -f "$LOGFILE" ] && [ "$(wc -c < "$LOGFILE" 2>/dev/null)" -ge 65536 ]; then
    : > "$LOGFILE"
  fi
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOGFILE" 2>/dev/null
}

# Classify current connection: PC / CHARGER / OFF (unplugged).
detect_conn() {
  if [ "$(cat "$USB_ONLINE_NODE" 2>/dev/null)" != "1" ]; then
    echo "OFF"; return
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

# Only write when the switch actually differs.
set_switch() {
  desired="$1"
  current="$(settings get global "$SETTING_KEY" 2>/dev/null)"
  if [ "$current" != "$desired" ]; then
    settings put global "$SETTING_KEY" "$desired"
    return 0
  fi
  return 1
}

# Called once on an insertion event (usb/online 0->1). Decide separation by the
# connection type and the matching toggle. No continuous enforcement: on unplug
# the system closes separation by itself and we do nothing further.
apply_once() {
  read_config
  conn="$(detect_conn)"
  desired=0
  case "$conn" in
    PC)
      [ "$SEP_ON_USB" = "1" ] && desired=1
      ;;
    CHARGER)
      [ "$SEP_ON_CHARGER" = "1" ] && desired=1
      ;;
  esac
  if set_switch "$desired"; then
    log "insert conn=$conn sep=$desired (usb_toggle=$SEP_ON_USB charger_toggle=$SEP_ON_CHARGER)"
    return 0
  fi
  return 0
}