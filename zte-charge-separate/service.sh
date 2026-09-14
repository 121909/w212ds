#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# zte-charge-separate service.sh
# Runs at boot as the root domain. Applies charge separation whenever the
# device is powered from a USB host (adb sessions, wired USB), and reverts to
# normal charging when it is unplugged / switched to a wall charger.

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

    # Run the controller in service mode (blocks on inotifywait).
    exec "$CONFIG_SH" service
) >>"$LOG_FILE" 2>&1 &

exit 0