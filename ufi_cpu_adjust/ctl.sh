#!/system/bin/sh
# UFI CPU调节器 v2.0 控制入口 (WebUI 通过 sh 调用)
# 用法:
#   ctl.sh dump                读取各 cluster 的调节器与核心状态 (key=value)
#   ctl.sh gov <governor>      设置全部核心簇调节器并保存配置 (重启生效)
#   ctl.sh core <cpu> <0|1>    开关单个核心并保存配置
#   ctl.sh on_all              启用全部核心
MODDIR=/data/adb/modules/ufi_cpu_adjust
CFG=$MODDIR/config.sh
GOVS=" userspace uscfreq conservative powersave performance schedutil "

fail() {
    echo "ERR: $*" >&2
    exit 1
}

[ -f "$CFG" ] || fail "config.sh 不存在 ($CFG)"

getv() {
    grep -E "^$1=" "$CFG" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'
}

LITTLE_FREQ="$(getv LITTLE_FREQ)"
[ -n "$LITTLE_FREQ" ] || LITTLE_FREQ="614400 614400 614400 614400"
BIG_FREQ="$(getv BIG_FREQ)"
[ -n "$BIG_FREQ" ] || BIG_FREQ="768000 768000 768000 768000"

cores_now() {
    s=""
    i=0
    while [ $i -lt 8 ]; do
        if [ -e /sys/devices/system/cpu/cpu$i/online ]; then
            v=$(cat /sys/devices/system/cpu/cpu$i/online 2>/dev/null)
            s="$s $v"
        else
            s="$s 1"
        fi
        i=$((i + 1))
    done
    printf '%s\n' "$s"
}

save_cfg() {
    # $1 core_string  $2 little_gov  $3 big_gov
    tmp="$CFG.tmp.$$"
    {
        printf '# UFI CPU调节器配置\n'
        printf '# 由 ctl.sh/WebUI 自动写入;手动修改后重启生效\n'
        printf 'CORE_SWITCH="%s"\n' "$1"
        printf 'LITTLE_GOVERNOR="%s"\n' "$2"
        printf 'BIG_GOVERNOR="%s"\n' "$3"
        printf 'LITTLE_FREQ="%s"\n' "$LITTLE_FREQ"
        printf 'BIG_FREQ="%s"\n' "$BIG_FREQ"
    } > "$tmp" || fail "无法写入临时配置"
    cat "$tmp" > "$CFG" || fail "无法写入 config.sh"
    rm -f "$tmp"
}

cur_gov() {
    g=$(cat "/sys/devices/system/cpu/cpufreq/$1/scaling_governor" 2>/dev/null)
    [ -n "$g" ] && printf '%s' "$g" || printf 'schedutil'
}

set_gov() {
    g="$1"
    case "$GOVS" in
        *" $g "*) ;;
        *) fail "不支持的调节器: $g" ;;
    esac
    for p in policy0 policy4 policy7; do
        f="/sys/devices/system/cpu/cpufreq/$p/scaling_governor"
        if ! echo "$g" > "$f" 2>/dev/null; then
            fail "写入失败: $f"
        fi
    done
    save_cfg "$(cores_now)" "$g" "$g"
    echo "OK governor=$g"
}

set_core() {
    c="$1"; v="$2"
    case "$c" in
        0|1|2|3|4|5|6|7) ;;
        *) fail "无效核心: $c" ;;
    esac
    case "$v" in
        0|1) ;;
        *) fail "无效值: $v" ;;
    esac
    # 安全底线: 绝不关闭最后一个在线核心 (否则系统死锁)
    if [ "$v" = "0" ]; then
        n=0
        i=0
        while [ $i -lt 8 ]; do
            [ -e /sys/devices/system/cpu/cpu$i/online ] && [ "$(cat /sys/devices/system/cpu/cpu$i/online 2>/dev/null)" = "1" ] && n=$((n + 1))
            i=$((i + 1))
        done
        [ "$n" -le 1 ] && fail "不能关闭最后一个在线核心"
    fi
    f="/sys/devices/system/cpu/cpu$c/online"
    [ -e "$f" ] || fail "不存在: $f"
    echo "$v" > "$f" 2>/dev/null || fail "写入失败: $f"
    sleep 0.2
    cur=$(cat "$f" 2>/dev/null)
    [ "$cur" = "$v" ] || fail "CPU$c 仍为 $cur"
    g0=$(cur_gov policy0)
    gb=$(cur_gov policy4)
    save_cfg "$(cores_now)" "$g0" "$gb"
    echo "OK cpu$c=$v"
}

on_all() {
    i=0
    while [ $i -lt 8 ]; do
        [ -e /sys/devices/system/cpu/cpu$i/online ] && echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null
        i=$((i + 1))
    done
    sleep 0.3
    g0=$(cur_gov policy0)
    gb=$(cur_gov policy4)
    save_cfg "$(cores_now)" "$g0" "$gb"
    echo "OK all-cores-enabled"
}

dump() {
    echo "CTX=uid$(id -u) $(cat /proc/self/attr/current 2>/dev/null)"
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        pol=${p##*/policy}
        echo "POLICY=$pol"
        echo "REL=$(cat "$p/related_cpus" 2>/dev/null)"
        echo "GOV=$(cat "$p/scaling_governor" 2>/dev/null)"
    done
    i=0
    while [ $i -lt 8 ]; do
        [ -e /sys/devices/system/cpu/cpu$i/online ] && echo "ON=$i:$(cat /sys/devices/system/cpu/cpu$i/online 2>/dev/null)"
        i=$((i + 1))
    done
}

case "$1" in
    dump)
        dump
        ;;
    gov)
        [ $# -ge 2 ] && set_gov "$2" || fail "用法: gov <governor>"
        ;;
    core)
        [ $# -ge 3 ] && set_core "$2" "$3" || fail "用法: core <cpu> <0|1>"
        ;;
    on_all)
        on_all
        ;;
    *)
        fail "用法: dump|gov|core|on_all"
        ;;
esac
exit 0