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
# FULL_SEP: 1=at 100% open separation regardless of connection type (top priority).
# FULL_DROP_CLOSE: (FULL_SEP only) 0=keep separation until unplug, 1=close when capacity leaves 100.
# TH_LATCH: session latch for AUTO_CLOSE=0, reset on unplug.
# FULL_LATCH: session latch for full-charge protection, reset on unplug.
read_config() {
  SEP_ON_USB=1
  CHARGER_MODE=0
  THRESHOLD=70
  AUTO_CLOSE=0
  FULL_SEP=0
  FULL_DROP_CLOSE=0
  [ -r "$CONFIG_FILE" ] || return 0
  while IFS='=' read -r key value; do
    case "$key" in
      SEP_ON_USB) [ "$value" = "0" ] && SEP_ON_USB=0 ;;
      CHARGER_MODE) case "$value" in 1|2) CHARGER_MODE="$value" ;; esac ;;
      THRESHOLD) case "$value" in 0|50|60|70|80|90) THRESHOLD="$value" ;; esac ;;
      AUTO_CLOSE) [ "$value" = "1" ] && AUTO_CLOSE=1 ;;
      FULL_SEP) [ "$value" = "1" ] && FULL_SEP=1 ;;
      FULL_DROP_CLOSE) [ "$value" = "1" ] && FULL_DROP_CLOSE=1 ;;
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

# SukiSU module switch (disable file): master gate for the charger path.
# Off -> plugging a charger never touches the separation switch; the PC path
# is unchanged (still governed by SEP_ON_USB).
module_enabled() {
  [ -e "$MODDIR/disable" ] && return 1
  return 0
}

# Called once on an insertion event (usb/online 0->1). PC and charger mode 1
# decide once and go idle. Mode 2 does nothing here — threshold_tick owns it.
apply_once() {
  read_config
  # Full-charge protection: inserting while already at 100% -> separate NOW,
  # regardless of connection type; threshold_tick owns it from here on.
  if [ "$FULL_SEP" = "1" ] && module_enabled; then
    cap="$(cat "$CAPACITY_NODE" 2>/dev/null)"
    case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
    if [ "$cap" -ge 100 ]; then
      FULL_LATCH=1
      if set_switch 1; then
        log "insert conn=$(detect_conn) cap=100 sep=1 (full_sep)"
      fi
      return 0
    fi
  fi
  conn="$(detect_conn)"
  case "$conn" in
    PC)
      desired=0
      [ "$SEP_ON_USB" = "1" ] && desired=1
      set_switch "$desired" && log "insert conn=PC sep=$desired (usb_toggle=$SEP_ON_USB)"
      ;;
    CHARGER)
      if module_enabled; then
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
      else
        log "insert conn=CHARGER skipped (module switch off)"
      fi
      ;;
  esac
  return 0
}

# Policy tick (every 30s from service.sh), one decision function per tick:
#
# 1. Full-charge protection (FULL_SEP=1): while ANY source is attached, at 100%
#    capacity force separation ON regardless of connection type (charger or PC).
#    FULL_DROP_CLOSE=1: once capacity leaves 100, close separation and resume
#    charging (=0: keep separation until unplug). Highest priority — wins over
#    both the threshold state machine and the PC one-shot decision.
# 2. Threshold mode (CHARGER_MODE=2): only while a CHARGER is attached,
#    per AUTO_CLOSE semantics. Unplug handling lives in service.sh's loop.
threshold_tick() {
  read_config
  module_enabled || return 0
  [ "$(cat "$USB_ONLINE_NODE" 2>/dev/null)" = "1" ] || return 0
  capacity="$(cat "$CAPACITY_NODE" 2>/dev/null)"
  case "$capacity" in ''|*[!0-9]*) return 0 ;; esac

  if [ "$FULL_SEP" = "1" ]; then
    if [ "$capacity" -ge 100 ]; then
      FULL_LATCH=1
      if set_switch 1; then
        log "full cap=$capacity drop_close=$FULL_DROP_CLOSE sep=1"
      fi
      return 0
    fi
    if [ "${FULL_LATCH:-0}" = "1" ]; then
      if [ "$FULL_DROP_CLOSE" = "1" ] && [ "$capacity" -ge 95 ]; then
        # Left 100% while still connected: resume charging (re-opens at 100).
        if set_switch 0; then
          log "full cap=$capacity drop_close=1 sep=0 (left 100%)"
        fi
        return 0
      fi
      if [ "$FULL_DROP_CLOSE" != "1" ]; then
        # Hold separation until unplug — the normal policy must not override.
        set_switch 1
        return 0
      fi
      # Discharged far below 100 (below 95): release the latch; the normal
      # policy owns the switch again and a later 100% re-triggers.
      FULL_LATCH=0
    fi
    # Below 100 and not actively owned by full protection: fall through to the
    # normal policy — threshold mode (or nothing) owns the switch again.
  fi

  [ "$CHARGER_MODE" = "2" ] || return 0
  [ "$THRESHOLD" != "0" ] || return 0
  [ "$(detect_conn)" = "CHARGER" ] || return 0

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
