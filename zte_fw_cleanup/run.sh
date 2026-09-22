#!/system/bin/sh
#
# Shared runner for zte_fw_cleanup.
# Runs cleanup.sh, then appends a timestamped, paragraph-separated result
# section to $MODDIR/webroot/result.log, keeping the last 5 sections.
# Used both at boot (service.sh) and on-demand from the WebUI ("立即执行").
#
# Exit code: 0 even if cleanup reports failure — the caller treats all
# output as diagnostics. The log is how the result surfaces in the WebUI.

MODDIR=$(dirname "$0")
[ "$MODDIR" = "." ] && MODDIR=$(pwd)
LOG_FILE="$MODDIR/webroot/result.log"
TMP_LOG="$LOG_FILE.tmp"

# Timestamp; drop to a literal when date is unavailable.
TS=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')

# New section (paragraph-separated by a trailing blank line).
{
    echo "===== $TS ====="
    /system/bin/sh "$MODDIR/cleanup.sh"
    echo "rc=$?"
    echo
} > "$TMP_LOG" 2>&1

# Append the previous log, then keep only the most recent 5 paragraphs.
# Paragraph mode (RS="") treats each blank-line-separated run as a record.
if [ -f "$LOG_FILE" ]; then
    cat "$LOG_FILE" >> "$TMP_LOG"
fi
awk 'BEGIN{RS="";ORS="\n\n"} { a[++n]=$0 } END{ for(i=n-4;i<=n;i++) if(i>=1) print a[i] }' \
    "$TMP_LOG" > "$LOG_FILE" 2>/dev/null || cp "$TMP_LOG" "$LOG_FILE"
rm -f "$TMP_LOG"

# Make sure the file is visible to the WebUI (webroot served by ksu httpd).
chmod 644 "$LOG_FILE" 2>/dev/null
chown root:root "$LOG_FILE" 2>/dev/null

exit 0
