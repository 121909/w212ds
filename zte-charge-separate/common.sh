#!/system/bin/sh

SETTING_KEY="charge_separation_switch"
USB_ONLINE_NODE="/sys/class/power_supply/usb/online"
CHARGER_TYPE_NODE="/sys/class/power_supply/charger_psy/usb_type"
GADGET_NODE="/sys/class/android_usb/android0/state"
CAPACITY_NODE="/sys/class/power_supply/battery/capacity"
CONFIG_FILE="$MODDIR/config.conf"
LOGFILE="/cache/zte-charge-separate.log"

# SEP_ON_USB: PC insert -> separation.
# CHARGER_MODE: 0=off, 1=separate on insert, 2=battery threshold mode.
# THRESHOLD: 0|50|60|70|80|90 (mode 2 only; 0 = feature disabled).
# AUTO_CLOSE: 0=latch once opened until unplug, 1=hysteresis (>=T open, <T close).
# TH_LATCH: session latch for AUTO_CLOSE=0, reset on unplug.
read_config() {
  SEP_ON_USB=1
  CHARGER_MODE=0
  THRESHOLD=70
  AUTO_CLOSE=0
  [ -r "$CONFIG_FILE" ] || return 0
  while IFS='=' read -r key value; do
    case "$key" in
      SEP_ON_USB) [ "$value" = "0" ] && SEP_ON_USB=0 ;;
      CHARGER_MODE) case "$value" in 1|2) CHARGER_MODE="$value" ;; esac ;;
      THRESHOLD) case "$value" in 0|50|60|70|80|90) THRESHOLD="$value" ;; esac ;;
      AUTO_CLOSE) [ "$value" = "1" ] && AUTO_CLOSE=1 ;;
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

# Called once on an insertion event (usb/online 0->1). PC and charger mode 1
# decide once and go idle. Mode 2 does nothing here — threshold_tick owns it.
apply_once() {
  read_config
  conn="$(detect_conn)"
  case "$conn" in
    PC)
      desired=0
      [ "$SEP_ON_USB" = "1" ] && desired=1
      set_switch "$desired" && log "insert conn=PC sep=$desired (usb_toggle=$SEP_ON_USB)"
      ;;
    CHARGER)
      case "$CHARGER_MODE" in
        1)
          set_switch 1 && log "insert conn=CHARGER sep=1 (mode=instant)"
          ;;
        2)
          # Fresh insertion starts a fresh latch session; tick owns the switch.
          TH_LATCH=0
          ;;
        *)
          set_switch 0 && log "insert conn=CHARGER sep=0 (mode=off)"
          ;;
      esac
      ;;
  esac
  return 0
}

# Threshold mode tick (every 30s from service.sh). Reads only usb/online while
# unplugged; while charging on a CHARGER source compares capacity against
# THRESHOLD per AUTO_CLOSE semantics. Never acts on PC connections.
threshold_tick() {
  read_config
  [ "$CHARGER_MODE" = "2" ] || return 0
  if [ "$(cat "$USB_ONLINE_NODE" 2>/dev/null)" != "1" ]; then
    if [ "${TH_LATCH:-0}" = "1" ]; then
      TH_LATCH=0
      set_switch 0 && log "unplug latch reset sep=0"
    fi
    return 0
  fi
  [ "$THRESHOLD" != "0" ] || return 0
  [ "$(detect_conn)" = "CHARGER" ] || return 0
  capacity="$(cat "$CAPACITY_NODE" 2>/dev/null)"
  case "$capacity" in ''|*[!0-9]*) return 0 ;; esac

  if [ "$AUTO_CLOSE" = "1" ]; then
    if [ "$capacity" -ge "$THRESHOLD" ]; then desired=1; else desired=0; fi
  else
    if [ "${TH_LATCH:-0}" = "1" ]; then
      desired=1
    elif [ "$capacity" -ge "$THRESHOLD" ]; then
      TH_LATCH=1
      desired=1
    else
      desired=0
    fi
  fi
  if set_switch "$desired"; then
    log "threshold cap=$capacity thr=$THRESHOLD auto_close=$AUTO_CLOSE latch=${TH_LATCH:-0} sep=$desired"
  fi
  return 0
}
