#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Charger-separation control for ZTE hardware (W210DS / charger-manager + zte_battery).
#
# Node: /sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled
#   write 1 -> disable charging (bypass / charge separation)
#   write 0 -> resume charging
#
# Unlike the generic "battery/status", the AC-supplied + bypassed state keeps
# status=Charging but current_now goes positive -> detect the bypass via that node.

CTL="/sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled"
USB_ONLINE="/sys/class/power_supply/usb/online"

log() {
    # Redirect into the module log like normal mount-trigger scripts.
    echo "[zte-charge-separate] $*" >&2
}

# How are we being governed?
#   "service.sh"      -> boot daemon, acted on usb attach/detach uevent.
#   "on" / "off"      -> CLI force split / resume.
#   "toggle"          -> flip current state.
#   "status"          -> report current state.
MODE="$1"

check_env() {
    [ -w "$CTL" ] || { log "control node not writable: $CTL"; return 1; }
    [ -e "$USB_ONLINE" ] || { log "usb online node missing"; return 1; }
    return 0
}

usb_attached() {
    [ "$(cat "$USB_ONLINE")" = "1" ]
}

state_val() {
    cat "$CTL" 2>/dev/null || echo unknown
}

split_on() {
    echo 1 > "$CTL"
    log "charge separation enabled (battery_charging_enabled=1)"
}

split_off() {
    echo 0 > "$CTL"
    log "charge separation disabled (battery_charging_enabled=0)"
}

configure() {
    check_env || return 1
    if usb_attached; then
        split_on
    else
        split_off
    fi
}

case "$MODE" in
    service)
        # Used from service.sh; also reacts to inotifywait on usb/online.
        # If inotifywait is absent, fall back to one-shot configure.
        if command -v inotifywait >/dev/null 2>&1; then
            configure
            while inotifywait -q -e modify "$USB_ONLINE"; do
                configure
            done
        else
            configure
        fi
        ;;
    on)
        check_env || exit 1
        split_on
        ;;
    off)
        check_env || exit 1
        split_off
        ;;
    toggle)
        check_env || exit 1
        if [ "$(state_val)" = "1" ]; then
            split_off
        else
            split_on
        fi
        ;;
    status)
        state_val
        ;;
    *)
        echo "usage: $0 {service|on|off|toggle|status}" >&2
        exit 1
        ;;
esac