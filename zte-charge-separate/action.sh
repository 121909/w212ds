#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
read_config

save_config() {
  printf '# 充电分离配置（KernelSU 模块页 WebUI 可视化调整）\n# 0=关闭 1=开启\nSEP_ON_USB=%s\n# 充电器模式：0=关闭  1=插入立即分离  2=电量阈值模式\nCHARGER_MODE=%s\n# 电量阈值（仅 CHARGER_MODE=2 生效）：0=不启用  可选 50/60/70/80/90\nTHRESHOLD=%s\n# 低于阈值自动关闭充电分离（仅 CHARGER_MODE=2 且 THRESHOLD>0 生效）\n# 0=达到阈值开启后保持（闩锁，直到拔电）  1=低于阈值自动关闭、回到阈值再次开启\nAUTO_CLOSE=%s\n' \
    "$SEP_ON_USB" "$CHARGER_MODE" "$THRESHOLD" "$AUTO_CLOSE" > "$CONFIG_FILE"
}

echo "======================================="
echo "  充电分离自动开关设置"
echo "======================================="
echo "音量+  : 切换「插电脑USB自动分离」"
echo "充电器模式/阈值/自动关闭：请在模块 WebUI 调整"
echo "停止按键 6 秒自动保存并退出"
echo ""
echo "当前："
echo "  插电脑USB → 自动分离 : $([ "$SEP_ON_USB" = "1" ] && echo 开启 || echo 关闭)"
echo "  充电器模式           : $(
  case "$CHARGER_MODE" in
    1) echo 插入立即分离 ;;
    2) echo "电量阈值(${THRESHOLD}%$([ "$AUTO_CLOSE" = "1" ] && echo '，自动关闭'))" ;;
    *) echo 关闭 ;;
  esac
)"
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
      echo "充电器模式/阈值/自动关闭请在模块 WebUI 调整"
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
