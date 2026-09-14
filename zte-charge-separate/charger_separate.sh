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
        # Boot daemon. USB present state is not reliably available early at
        # boot (usb/online settles late) and sysfs attributes do not emit
        # inotify events, so poll instead of watching.
        #
        # Phase 1: wait for the charger policy to settle before touching the
        # control node (up to 2 min, checking every 3s). Then apply.
        # Phase 2: while running, re-check periodically so we also react to
        # plug/unplug and to any charger-manager reset of the node.
        SETTLE=120
        INTERVAL=5
        waited=0
        while [ "$waited" -lt "$SETTLE" ]; do
            [ "$(cat "$USB_ONLINE" 2>/dev/null)" = "None" ] || break
            sleep 3
            waited=$((waited + 3))
        done
        # Always apply initial state (online 1 -> split; 0/absent -> normal).
        configure || exit 1
        # Main loop: re-apply on every interval. Cheap write if unchanged.
        while true; do
            sleep "$INTERVAL"
            configure || break
        done
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