#!/usr/bin/env bash
# TOTEM battery helper.
#   (no args)  notify when a half is low; run periodically (systemd timer).
#   --waybar   print one waybar JSON line with both levels; class "low"/"critical"
#              lets the bar turn red. Never notifies. Empty text when the
#              keyboard isn't connected over Bluetooth (waybar then hides it).
# BlueZ/upower only surface the FIRST battery characteristic of the TOTEM, so we
# read every 0x2A19 characteristic ourselves: the left (central) half comes
# first, the proxied right half second.
LOW=${TOTEM_LOW:-20}; CRIT=${TOTEM_CRIT:-10}
STATE=${XDG_RUNTIME_DIR:-/tmp}/totem-battery-state
names=(left right other)
mode=notify; [ "$1" = "--waybar" ] && mode=waybar

readings=()   # "addr half pct"
tree=$(busctl --system tree org.bluez 2>/dev/null)
for addr in $(bluetoothctl devices Connected 2>/dev/null | awk '/ TOTEM/{print $2}'); do
  dev=/org/bluez/hci0/dev_${addr//:/_}
  i=0
  for c in $(grep -oE "$dev/service[0-9a-f]+/char[0-9a-f]+$" <<<"$tree"); do
    uuid=$(busctl --system get-property org.bluez "$c" org.bluez.GattCharacteristic1 UUID 2>/dev/null)
    [[ $uuid == *00002a19* ]] || continue
    pct=$(busctl --system call org.bluez "$c" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 2>/dev/null | awk '{print $3}')
    [[ $pct =~ ^[0-9]+$ ]] && readings+=("$addr ${names[$i]:-other} $pct")
    i=$((i+1))
  done
done

level() { if [ "$1" -le "$CRIT" ]; then echo crit; elif [ "$1" -le "$LOW" ]; then echo low; else echo ok; fi; }

if [ "$mode" = waybar ]; then
  text=""; worst=ok; tip=""
  for r in "${readings[@]}"; do
    read -r _ half pct <<<"$r"
    h=${half:0:1}; text+="${h^}${pct}% "; tip+="${half}: ${pct}%\n"
    l=$(level "$pct")
    [ "$l" = crit ] && worst=critical
    [ "$l" = low ] && [ "$worst" = ok ] && worst=low
  done
  [ -z "$text" ] && { echo '{"text":"","class":"disconnected"}'; exit 0; }
  printf '{"text":"󰌌 %s","tooltip":"%s","class":"%s"}\n' "${text% }" "${tip%\\n}" "$worst"
  exit 0
fi

mkdir -p "$STATE"
for r in "${readings[@]}"; do
  read -r addr half pct <<<"$r"
  f="$STATE/${addr//:/_}_$half"; last=$(cat "$f" 2>/dev/null || echo ok)
  lvl=$(level "$pct")
  if [ "$lvl" != "$last" ] && [ "$lvl" != ok ]; then
    urg=normal; [ "$lvl" = crit ] && urg=critical
    notify-send -u "$urg" "TOTEM $half battery $lvl" "The $half half is at ${pct}% - charge it."
  fi
  echo "$lvl" > "$f"
  [ -n "$TOTEM_VERBOSE" ] && echo "$half: ${pct}%"
done
