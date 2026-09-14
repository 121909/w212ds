# customize.sh - KernelSU/Magisk extracts module zips without Unix exec bits,
# so re-apply them here (runs as root on install/update and boot-ish stages).
MODDIR="${0%/*}"

for f in service.sh uninstall.sh charger_separate.sh; do
    [ -f "$MODDIR/$f" ] && chmod 0755 "$MODDIR/$f"
done

exit 0