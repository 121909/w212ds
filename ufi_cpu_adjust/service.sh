#!/system/bin/sh
# UFI CPU调节器 - KernelSU 模块启动脚本 (late_start 阶段由 ksud 执行)
# 由 ctl.sh/WebUI 自动写入 config.sh;重启后应用
MODDIR=${0%/*}
CONFIG=$MODDIR/config.sh
[ -f "$CONFIG" ] || exit 0
. "$CONFIG"

# 1. 核心开关 (绝不关闭 CPU0)
i=0
for s in $CORE_SWITCH; do
    if [ "$i" -ne 0 ] && [ -e "/sys/devices/system/cpu/cpu$i/online" ]; then
        echo "$s" > "/sys/devices/system/cpu/cpu$i/online" 2>/dev/null
    fi
    i=$((i + 1))
done
sleep 2

# 2. 调节器 (governor), 自动适配任意 cluster 布局
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    rel=$(cat "$p/related_cpus" 2>/dev/null)
    first=${rel%% *}
    case "$first" in
        0|1|2|3) G="$LITTLE_GOVERNOR" ;;
        *) G="$BIG_GOVERNOR" ;;
    esac
    [ -n "$G" ] && echo "$G" > "$p/scaling_governor" 2>/dev/null
done

exit 0