#!/system/bin/sh
#
# Cleanup ZTE vendor firewall rules (zte_fw_gms chain flush).
# Called by boxctl at apply time when clean_vendor_firewall is enabled.
#
# Exit 0 always — caller treats any output as diagnostics.

ZTE_CHAIN="zte_fw_gms"

flush_chain() {
    family="$1"      # "iptables" or "ip6tables"
    table="$2" # Check if chain exists (non-zero means missing → skip silently).
    "$family" -t "$table" -n -L "$ZTE_CHAIN" >/dev/null 2>&1 || return 0

    if "$family" -t "$table" -F "$ZTE_CHAIN" 2>/dev/null; then
        echo "${family}: flushed ${ZTE_CHAIN}"
    else
        echo "${family}: failed to flush ${ZTE_CHAIN}" >&2
    fi
}

flush_chain iptables  filter
flush_chain ip6tables filter

exit 0
