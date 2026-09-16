#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
read_config

save_config() {
  printf '# 两个自动充电分离开关（模块界面"执行/Action"调整）\n# 0=关闭 1=开启\nSEP_ON_USB=%s\nSEP_ON_CHARGER=%s\n' \
    "$SEP_ON_USB" "$SEP_ON_CHARGER" > "$CONFIG_FILE"
}

echo "======================================="
echo "  充电分离自动开关设置"
echo "======================================="
echo "音量+  : 切换「插电脑USB自动分离」"
echo "音量-  : 切换「插充电器自动分离」"
echo "停止按键 6 秒自动保存并退出"
echo ""
echo "当前："
echo "  插电脑USB → 自动分离 : $([ "$SEP_ON_USB" = "1" ] && echo 开启 || echo 关闭)"
echo "  插充电器  → 自动分离 : $([ "$SEP_ON_CHARGER" = "1" ] && echo 开启 || echo 关闭)"
echo ""

while true; do
  EVENT="$(timeout 6 getevent -ql 2>/dev/null | grep -m 1 -E 'KEY_VOLUME(UP|DOWN).*DOWN')"

  case "$EVENT" in
    *KEY_VOLUMEUP*DOWN*)
      SEP_ON_USB=$((1 - SEP_ON_USB))
      save_config
      echo "插电脑USB → 自动分离 : $([ "$SEP_ON_USB" = "1" ] && echo 开启 || echo 关闭)  [已保存]"
      ;;
    *KEY_VOLUMEDOWN*DOWN*)
      SEP_ON_CHARGER=$((1 - SEP_ON_CHARGER))
      save_config
      echo "插充电器  → 自动分离 : $([ "$SEP_ON_CHARGER" = "1" ] && echo 开启 || echo 关闭)  [已保存]"
      ;;
    *)
      break
      ;;
  esac
done

save_config
echo ""
echo "已保存："
echo "  插电脑USB → 自动分离 : $([ "$SEP_ON_USB" = "1" ] && echo 开启 || echo 关闭)"
echo "  插充电器  → 自动分离 : $([ "$SEP_ON_CHARGER" = "1" ] && echo 开启 || echo 关闭)"