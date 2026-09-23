#!/system/bin/sh
#
# zte_fw_cleanup — late_start service phase entry point (runs as root).
# Waits for Android to finish booting, then executes the firewall cleanup
# and records the result for the WebUI.
#
# KernelSU starts service.sh for installed modules. We do not log to
# stdout/stderr (those are discarded); all diagnostics land in
# webroot/result.log for the module WebUI.

MODDIR=${0%/*}

# Wait for boot to complete. KernelSU starts this service early in
# post-fs-data; boot_completed only flips to 1 once the system is up.
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
done

sleep 30   # settle a little after boot_completed so iptables is usable

/system/bin/sh "$MODDIR/run.sh"
exit 0
