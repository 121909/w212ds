#!/system/bin/sh

ui_print "***************************************"
ui_print " ZTE 充电分离（PC 接入自动开启）v2.0.0"
ui_print "***************************************"
ui_print "仅写 charge_separation_switch（1=分离，0=充电）"
ui_print "PC(USB 数据口)接入自动分离；充电器/拔线恢复或交还手动。"
ui_print "退出充电分离：settings put global charge_separation_switch 0"

set_perm_recursive "$MODPATH" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755