#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# uninstall.sh - revert charge separation to normal charging on removal.

CTL="/sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled"

[ ! -e "$CTL" ] || echo 0 > "$CTL" 2>/dev/null

exit 0