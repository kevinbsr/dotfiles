#!/bin/bash
# Warn when a filesystem is running out of room -- once, quietly, and in place.
#
# WHY IT WAS REWRITTEN: the old version fired `notify-send -u critical` on every
# timer tick. Critical notifications never expire by specification, so a new
# copy piled up every ten minutes until the screen was a wall of identical
# warnings, and a warning you dismiss twenty times a day is one you stop
# reading. The disk had been over the threshold for days: nothing was urgent,
# and nothing new was being said.
#
# WHAT IT DOES NOW:
#   * normal urgency with a timeout, so it behaves like every other
#     notification and disappears on its own;
#   * replaces its own previous notification instead of stacking, by keeping
#     the id the server hands back;
#   * repeats only when the situation actually changes: it climbed at least
#     ONE point since the last warning, or QUIET_HOURS have passed;
#   * escalates to critical (sticky, on purpose) only past CRITICAL_PERCENT,
#     where the machine really is about to stop working;
#   * forgets everything once usage drops back below the threshold, so the
#     next crossing warns again.
#
# Percentages come from df: used over used+available, which is what the user
# can actually still write. The hub's sysmon_probe uses the same definition.
set -uo pipefail

THRESHOLD=${DISK_MONITOR_THRESHOLD:-90}
CRITICAL_PERCENT=${DISK_MONITOR_CRITICAL:-97}
QUIET_HOURS=${DISK_MONITOR_QUIET_HOURS:-6}
PARTITION=${DISK_MONITOR_PARTITION:-/home}
TIMEOUT_MS=10000

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/disk-monitor"
STATE="$STATE_DIR/$(systemd-escape "$PARTITION").state"
mkdir -p "$STATE_DIR"

read -r usage avail_h < <(df -B1 --output=pcent,avail "$PARTITION" 2>/dev/null | tail -1 |
  awk '{ gsub(/%/, "", $1); printf "%s %.1f\n", $1, $2 / 1073741824 }')
[[ -n ${usage:-} ]] || exit 0

if ((usage < THRESHOLD)); then
  rm -f "$STATE"
  exit 0
fi

last_id=0 last_usage=0 last_time=0
# shellcheck source=/dev/null
[[ -f $STATE ]] && source "$STATE"

now=$(date +%s)
elapsed_hours=$(((now - last_time) / 3600))
if ((last_time > 0 && usage <= last_usage && elapsed_hours < QUIET_HOURS)); then
  exit 0
fi

if ((usage >= CRITICAL_PERCENT)); then
  urgency=critical
  # No timeout: at this point writes are about to start failing.
  expiry=0
  title="Disk almost full"
else
  urgency=normal
  expiry=$TIMEOUT_MS
  title="Disk filling up"
fi

id=$(notify-send -p \
  ${last_id:+--replace-id="$last_id"} \
  -u "$urgency" \
  -t "$expiry" \
  -i drive-harddisk-system \
  -h "string:x-canonical-private-synchronous:disk-monitor-$PARTITION" \
  "$title" \
  "$PARTITION is ${usage}% full — ${avail_h} GiB left." 2>/dev/null)

printf 'last_id=%s\nlast_usage=%s\nlast_time=%s\n' "${id:-0}" "$usage" "$now" >"$STATE"
