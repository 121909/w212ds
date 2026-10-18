#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
read_config

conn="$(detect_conn)"
node="$(cat /sys/devices/platform/charger-manager/zte_power_supply/zte_battery/battery_charging_enabled 2>/dev/null)"
switch="$(settings get global "$SETTING_KEY" 2>/dev/null)"
cap="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
cur="$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
status="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"

mode_name="$(
  case "$CHARGER_MODE" in
    1) echo "插入立即分离" ;;
    2) echo "电量阈值模式" ;;
    *) echo "关闭" ;;
  esac
)"

full_name="$(
  if [ "$FULL_SEP" = "1" ]; then
    if [ "$FULL_DROP_CLOSE" = "1" ]; then echo "开启(掉电关闭)"; else echo "开启(保持到拔电)"; fi
  else
    echo "关闭"
  fi
)"

echo "conn=$conn node=$node switch=$switch"
echo "cap=$cap% status=$status current=${cur}uA"
echo "usb_toggle=$SEP_ON_USB charger_mode=$mode_name threshold=$THRESHOLD% auto_close=$AUTO_CLOSE latch=${TH_LATCH:-0}"
echo "full_sep=$full_name full_latch=${FULL_LATCH:-0}"
if [ "$switch" = "1" ]; then
  echo ">> 充电分离 = 开启"
else
  echo ">> 充电分离 = 关闭（正常充电）"
fi
exit 0
