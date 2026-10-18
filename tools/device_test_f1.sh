#!/usr/bin/env bash
# F1 device test: drives real touches on the phone with adb and checks the
# game's own log lines ([REALM] ...). Run from the repo root after installing
# build/realm-debug.apk. Usage: bash tools/device_test_f1.sh
set -u
. "$(dirname "$0")/device_guard.sh"
guard_wait_free || exit 2
ADB="${ADB:-C:/Users/pedro/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
PKG="dev.pedro.realm/com.godot.game.GodotAppLauncher"
PASS=0
FAIL=0

log() { "$ADB" logcat -d -s godot:I | tr -d '\r'; }
ok() { echo "  PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
expect() { # $1 = grep pattern that must appear in the log since the last clear, $2 = label
  if log | grep -qE "$1"; then ok "$2"; else ko "$2"; log | grep REALM | tail -5; fi
}
reject() {
  if log | grep -qE "$1"; then ko "$2"; log | grep REALM | tail -5; else ok "$2"; fi
}

"$ADB" shell am force-stop dev.pedro.realm
"$ADB" logcat -c
"$ADB" shell am start -W -n "$PKG" >/dev/null
sleep 4

# Viewport -> physical pixel scale (screen height / 720 viewport height).
PHYS_H=$("$ADB" shell wm size | tr -d '\r' | awk -F'[x ]' '/Override|Physical/ {h=$NF} END {print h}')
PHYS_W=$("$ADB" shell wm size | tr -d '\r' | awk -F'[: x]+' '/Override/ {print $3} /Physical/ && !w {w=$3} END {}')
SHORT=$("$ADB" shell wm size | tr -d '\r' | grep -E "Override|Physical" | tail -1 | sed -E 's/.*: ([0-9]+)x([0-9]+)/\1/')
SCALE=$(awk -v s="$SHORT" 'BEGIN {print s/720}')
echo "scale=$SCALE (short side $SHORT px)"

declare -a UX UY
while read -r idx x y; do UX[$idx]=$x; UY[$idx]=$y; done < <(log | grep -oE "unit [0-9]+ [a-z]+ screen=\([0-9]+,[0-9]+\)" | sed -E 's/unit ([0-9]+) [a-z]+ screen=\(([0-9]+),([0-9]+)\)/\1 \2 \3/')
if [ "${#UX[@]}" -lt 5 ]; then echo "could not read unit positions"; exit 1; fi
px() { awk -v v="$1" -v s="$SCALE" 'BEGIN {printf "%d", v*s}'; }

# 1. tap one unit
"$ADB" logcat -c
"$ADB" shell input tap "$(px "${UX[0]}")" "$(px "${UY[0]}")"; sleep 1
expect "tap selected=1" "tap on a unit selects 1"
STOP_LINE=$(log | grep -oE "hud stop=\([0-9]+,[0-9]+\)" | tail -1)

# 2. hold-and-drag box over units 0..2
"$ADB" logcat -c
X0=$(px $((UX[0]-30))); Y0=$(px $((UY[0]-30))); X1=$(px $((UX[2]+30))); Y1=$(px $((UY[2]+30)))
"$ADB" shell "input motionevent DOWN $X0 $Y0; sleep 0.6; input motionevent MOVE $(( (X0+X1)/2 )) $(( (Y0+Y1)/2 )); input motionevent MOVE $X1 $Y1; input motionevent UP $X1 $Y1"
sleep 1
expect "box_end selected=3" "hold + drag box selects 3"

# 3. tap ground: move order for 3
"$ADB" logcat -c
"$ADB" shell input tap "$(px "${UX[2]}")" "$(px $((UY[2]+170)))"; sleep 1
expect "tap selected=3" "tap on ground orders the 3 selected"

# 4. Stop button (HUD) must not leak a tap into the map
"$ADB" logcat -c
SX=$(echo "$STOP_LINE" | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\1/'); SY=$(echo "$STOP_LINE" | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\2/')
if [ -n "$SX" ]; then
  "$ADB" shell input tap "$(px "$SX")" "$(px "$SY")"; sleep 1
  expect "stop selected=3" "Stop button halts the group"
  reject "gesture tap" "touch on HUD does not reach the map"
else
  ko "could not read Stop button position"
fi

# 5. quick swipe starting on a unit = pan, never select
"$ADB" logcat -c
"$ADB" shell input swipe "$(px "${UX[4]}")" "$(px "${UY[4]}")" "$(px $((UX[4]-300)))" "$(px "${UY[4]}")" 150; sleep 1
reject "gesture (tap|double_tap|box_end)" "quick swipe on a unit pans without selecting"

# 6. ten cycles: select a unit, send it 120 px down, select it there, send it back
"$ADB" shell am force-stop dev.pedro.realm; "$ADB" logcat -c; "$ADB" shell am start -W -n "$PKG" >/dev/null; sleep 4
GOOD=0
for i in 0 1 2 3 4 5 6 7 8 9; do
  u=$((i % 5))
  AX=$(px "${UX[$u]}"); AY=$(px "${UY[$u]}"); BY=$(px $((UY[$u]+120)))
  "$ADB" logcat -c
  "$ADB" shell input tap "$AX" "$AY"; sleep 0.5
  "$ADB" shell input tap "$AX" "$BY"; sleep 2.5
  "$ADB" shell input tap "$AX" "$BY"; sleep 0.5
  "$ADB" shell input tap "$AX" "$AY"; sleep 2.5
  N=$(log | grep -c "tap selected=1")
  if [ "$N" -eq 4 ] && ! log | grep -qE "gesture (box_end|double_tap|box_armed)"; then GOOD=$((GOOD+1)); else echo "  cycle $i: $N select/order taps"; log | grep REALM | tail -4; fi
done
if [ "$GOOD" -eq 10 ]; then ok "10/10 select + order cycles"; else ko "10/10 select + order cycles (got $GOOD)"; fi

echo "== device: $PASS passed, $FAIL failed =="
guard_release
[ "$FAIL" -eq 0 ]
