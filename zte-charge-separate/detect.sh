#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# detect.sh - USB connection discriminator (PC data host vs charger).
#
# Verified against both ground truths on ZTE W210DS (charger type is the ONLY
# reliable signal):
#   PC      /sys/class/power_supply/charger_psy/usb_type = "Unknown [SDP] ..."  -> SDP
#   CHARGER                                           ... = "Unknown SDP [DCP] ..." -> DCP
#   android_usb/state = CONFIGURED (data session) on PC, DISCONNECTED on charger.
#
# Interface:
#   detect_connection()  -> echo "PC" | "CHARGER" | "DISCONNECTED"; rc 0
#                          rc 2 if undetectable (no fallback signal)

USB_ONLINE="/sys/class/power_supply/usb/online"
CHARGER_TYPE_NODE="/sys/class/power_supply/charger_psy/usb_type"
GADGET_NODE="/sys/class/android_usb/android0/state"

detect_connection() {
    # 1) Physical link guard: unplugged -> DISCONNECTED regardless of stale state.
    local online
    online="$(cat "$USB_ONLINE" 2>/dev/null)"
    [ "$online" = "1" ] || { echo "DISCONNECTED"; return 0; }

    # 2) Charger type is authoritative: bracket holds the current type.
    local usb_type cur gadget
    usb_type="$(cat "$CHARGER_TYPE_NODE" 2>/dev/null)"
    cur="$(printf '%s\n' "$usb_type" | sed -n 's/^.*\[\([A-Za-z0-9_]*\)\].*$/\1/p')"

    case "$cur" in
        SDP|CDP)
            echo "PC"; return 0 ;;
        DCP|PD|PD_DRP|BrickID|C)
            echo "CHARGER"; return 0 ;;
    esac

    # 3) Fallback when the type node is missing/unparsed: data session = PC.
    gadget="$(cat "$GADGET_NODE" 2>/dev/null)"
    if [ "$gadget" = "CONFIGURED" ]; then
        echo "PC"; return 0
    fi
    if [ -n "$gadget" ]; then
        echo "CHARGER"; return 0
    fi
    echo "UNKNOWN"; return 2
}

# Allow: sh detect.sh   (print classification once)
if [ "$(basename "$0")" = "detect.sh" ]; then
    detect_connection
fi