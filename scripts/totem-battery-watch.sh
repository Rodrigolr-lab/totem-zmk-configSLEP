#!/usr/bin/env bash
# Notify when a TOTEM half's battery is low. Run periodically (systemd timer).
# BlueZ/upower only surface the FIRST battery characteristic of the TOTEM, so we
# read every 0x2A19 characteristic ourselves: the left (central) half comes
# first, the proxied right half second.
# Notifies once per half per threshold crossing; re-arms after recovery.
LOW=${TOTEM_LOW:-20}; CRIT=${TOTEM_CRIT:-10}
STATE=${XDG_RUNTIME_DIR:-/tmp}/totem-battery-state
mkdir -p "$STATE"
names=(left right other)

tree=$(busctl --system tree org.bluez 2>/dev/null) || exit 0
for addr in $(bluetoothctl devices Connected 2>/dev/null | awk '/ TOTEM/{print $2}'); do
  dev=/org/bluez/hci0/dev_${addr//:/_}
  i=0
  for c in $(grep -oE "$dev/service[0-9a-f]+/char[0-9a-f]+$" <<<"$tree"); do
    uuid=$(busctl --system get-property org.bluez "$c" org.bluez.GattCharacteristic1 UUID 2>/dev/null)
    [[ $uuid == *00002a19* ]] || continue
    pct=$(busctl --system call org.bluez "$c" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 2>/dev/null | awk '{print $3}')
    [[ $pct =~ ^[0-9]+$ ]] || { i=$((i+1)); continue; }
    half=${names[$i]:-other}; i=$((i+1))
    f="$STATE/${addr//:/_}_$half"; last=$(cat "$f" 2>/dev/null || echo ok)
    if   [ "$pct" -le "$CRIT" ]; then lvl=crit
    elif [ "$pct" -le "$LOW" ];  then lvl=low
    else lvl=ok; fi
    if [ "$lvl" != "$last" ] && [ "$lvl" != ok ]; then
      urg=normal; [ "$lvl" = crit ] && urg=critical
      notify-send -u "$urg" "TOTEM $half battery $lvl" "The $half half is at ${pct}% - charge it."
    fi
    echo "$lvl" > "$f"
    [ -n "$TOTEM_VERBOSE" ] && echo "$half: ${pct}%"
  done
done
