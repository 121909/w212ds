#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# zte-charge-separate service.sh
# Runs at boot as the root domain. Drives charge separation via the ZTE official
# setting switch (so the built-in Settings UI stays in sync) and hard-engages
# the sysfs node - even below the vendor charge threshold - whenever a USB host
# is attached. Reverts to normal charging when USB is removed / state unknown.

SELF="/data/adb/modules/zte-charge-separate"
CONFIG_SH="$SELF/charger_separate.sh"
LOG_DIR="/cache"
LOG_FILE="$LOG_DIR/zte-charge-separate.log"

# --- Log to a persistent path (cache survives over data, writable early). ----
[ -d "$LOG_DIR" ] || LOG_DIR="/data"
: > "$LOG_FILE"

(
    # Give Android a few seconds to settle before touching power nodes.
    sleep 5

    # Run the controller in service mode (blocks, polling usb/online).
    # Invoke via sh: KernelSU/Magisk extract module zips without preserving
    # Unix exec bits, so relying on +x would fail after every update.
    exec sh "$CONFIG_SH" service
) >>"$LOG_FILE" 2>&1 &

exit 0