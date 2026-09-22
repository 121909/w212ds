#!/system/bin/sh

ui_print "***************************************"
ui_print " ZTE 充电分离自动控制 v2.2.0"
ui_print "***************************************"
ui_print "仅写 charge_separation_switch（1=分离，0=充电）"
ui_print "PC USB：插入时按开关动作一次，不做持续监控"
ui_print "充电器：可选关闭/插入立即分离/电量阈值模式"
ui_print "阈值模式：达到阈值(50-90%)开启分离，"
ui_print "可选低于阈值自动关闭或闩锁保持到拔电"
ui_print "断电后系统自动关闭分离，无需其它操作"
ui_print "在 KernelSU 模块页打开 WebUI 调整全部设置"

set_perm_recursive "$MODPATH" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
