#!/system/bin/sh

ui_print "***************************************"
ui_print " ZTE 充电分离自动控制 v2.1.0"
ui_print "***************************************"
ui_print "仅写 charge_separation_switch（1=分离，0=充电）"
ui_print "插入时按类型与开关动作一次，不做持续监控"
ui_print "断电后系统自动关闭分离，无需其它操作"
ui_print "在 KernelSU 模块页打开 WebUI 可随时调整两个开关"

set_perm_recursive "$MODPATH" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755