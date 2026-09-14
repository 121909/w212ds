#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Charger-separation control for ZTE hardware (W210DS / charger-manager + zte_battery).
#
# Dual mechanism:
#   1) ZTE official switch (charge_separation_switch global setting) - keeps the
#      built-in Settings UI (com.zte.powersavemode SeparationChargeSettingActivity)
#      in sync and lets the vendor daemon drive its own policy.
#   2) Hardware sysfs node (battery_charging_enabled) as a hard override - engages
#      separation even when the ZTE charge-threshold policy would not (capacity
#      below the "start separation at" threshold).
#
# Node semantics:
#   battery_charging_enabled  1 -> disable charging (bypass / charge separation)
#                             0 -> resume charging
#   charge_separation_switch  1 -> Settings UI shows ON
#                             0 -> Settings UI shows OFF

CTL="/sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled"
USB_ONLINE="/sys/class/power_supply/usb/online"
SETTING_KEY="charge_separation_switch"

log() {
    echo "[zte-charge-separate] $*" >&2
}

MODE="$1"

check_env() {
    [ -w "$CTL" ] || { log "control node not writable: $CTL"; return 1; }
    [ -e "$USB_ONLINE" ] || { log "usb online node missing: $USB_ONLINE"; return 1; }
    return 0
}

usb_attached() {
    [ "$(cat "$USB_ONLINE")" = "1" ]
}

# The separation should engage only when a real data host (PC/Windows with adb)
# supplies the port - NOT for a plain wall/USB charger. A charger still reports
# usb/online=1, so gate on the USB gadget config instead:
#   "charging,adb" / "mtp,adb" / "rndis,adb" ...  -> data host present -> split
#   "charging" / "charge_only" ...                -> charger only -> normal charge
usb_host_attached() {
    case "$(getprop sys.usb.state)" in
        *,adb) return 0 ;;
        *) return 1 ;;
    esac
}

set_setting() {
    # Persist the ZTE switch so the Settings UI reflects our state.
    # Best-effort: ignore failure (settings binary may not be ready early at boot).
    settings put global "$SETTING_KEY" "$1" 2>/dev/null
}

split_on() {
    # Setting first: vendor.charged watches charge_separation_switch and
    # re-applies its own policy to the node. Then we hard-write the node so
    # separation engages even below the vendor charge threshold.
    set_setting 1
    sleep 1
    echo 1 > "$CTL"
    log "charge separation enabled (node=1, switch=1)"
}

split_off() {
    set_setting 0
    sleep 1
    echo 0 > "$CTL"
    log "charge separation disabled (node=0, switch=0)"
}

configure() {
    check_env || return 1
    if usb_host_attached; then
        split_on
    else
        split_off
    fi
}

case "$MODE" in
    service)
        # Boot daemon. USB present state is not reliably available early at boot
        # (usb/online settles late) and sysfs attributes do not emit inotify
        # events, so poll instead of watching.
        #
        # Phase 1: wait for the usb/online node to exist (up to 2 min, every 3s).
        # Phase 2: apply initial state, then poll every 5s, re-applying only when
        # the desired state differs from the current node value (so we also
        # recover from any charger-policy service that re-enables charging).
        SETTLE=120
        INTERVAL=5
        waited=0
        while [ "$waited" -lt "$SETTLE" ]; do
            [ -e "$USB_ONLINE" ] && break
            sleep 3
            waited=$((waited + 3))
        done

        while true; do
            wanted=0
            usb_host_attached && wanted=1

            node="$(cat "$CTL" 2>/dev/null || echo -)"
            sw="$(settings get global "$SETTING_KEY" 2>/dev/null)"

            # Re-apply only when node or the UI switch disagrees with the desired
            # state. This also repairs a stale switch (e.g. vendor reset it to 0
            # while separation is still hardware-active).
            if [ "$node" != "$wanted" ] || [ "$sw" != "$wanted" ]; then
                if [ "$wanted" = "1" ]; then
                    split_on
                else
                    split_off
                fi
            fi

            sleep "$INTERVAL"
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
        if [ "$(cat "$CTL" 2>/dev/null)" = "1" ]; then
            split_off
        else
            split_on
        fi
        ;;
    status)
        echo "node=$(cat "$CTL" 2>/dev/null) switch=$(settings get global "$SETTING_KEY" 2>/dev/null)"
        ;;
    *)
        echo "usage: $0 {service|on|off|toggle|status}" >&2
        exit 1
        ;;
esac