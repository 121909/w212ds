#!/system/bin/sh

# Uninstall: restore normal charging (separation off).
settings put global charge_separation_switch 0 2>/dev/null
exit 0