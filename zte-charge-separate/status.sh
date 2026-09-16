#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

conn="$(detect_conn)"
node="$(cat /sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled 2>/dev/null)"
switch="$(settings get global "$SETTING_KEY" 2>/dev/null)"
cap="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
cur="$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
status="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"

echo "conn=$conn node=$node switch=$switch"
echo "cap=$cap% status=$status current=${cur}uA"
if [ "$switch" = "1" ]; then
  echo ">> 充电分离 = 开启"
else
  echo ">> 充电分离 = 关闭（正常充电）"
fi
exit 0