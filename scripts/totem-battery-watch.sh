#!/usr/bin/env bash
# Notify when a TOTEM half's battery is low. Run periodically (systemd timer).
# Notifies once per device per threshold crossing; re-arms after recovery.
LOW=${TOTEM_LOW:-20}; CRIT=${TOTEM_CRIT:-10}
STATE=${XDG_RUNTIME_DIR:-/tmp}/totem-battery-state
mkdir -p "$STATE"
for dev in $(upower -e); do
  info=$(upower -i "$dev")
  grep -qi 'model:.*totem' <<<"$info" || continue
  pct=$(awk '/percentage:/{gsub("%","",$2); print $2}' <<<"$info")
  [ -n "$pct" ] || continue
  id=$(awk '/serial:/{print $2}' <<<"$info"); id=${id:-$(basename "$dev")}
  f="$STATE/${id//:/_}"; last=$(cat "$f" 2>/dev/null || echo ok)
  if   [ "$pct" -le "$CRIT" ]; then lvl=crit
  elif [ "$pct" -le "$LOW" ];  then lvl=low
  else lvl=ok; fi
  if [ "$lvl" != "$last" ] && [ "$lvl" != ok ]; then
    urg=normal; [ "$lvl" = crit ] && urg=critical
    notify-send -u "$urg" "TOTEM battery $lvl" "Half $id is at ${pct}% - charge it."
  fi
  echo "$lvl" > "$f"
done
