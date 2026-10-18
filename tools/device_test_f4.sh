#!/usr/bin/env bash
# F4 device test: build a House with real touches on the phone through the HUD
# (box-select villagers -> Build -> House -> tap map -> ✓) and train a villager.
set -u
ADB="${ADB:-C:/Users/pedro/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
PKG_NAME="dev.pedro.realm"
PASS=0; FAIL=0
log() { "$ADB" logcat -d -s godot:I | tr -d '\r'; }
ok() { echo "  PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); log | grep REALM | tail -6; }
expect() { if log | grep -qE "$1"; then ok "$2"; else ko "$2"; fi; }
SHORT=$("$ADB" shell wm size | tr -d '\r' | grep -E "Override|Physical" | tail -1 | sed -E 's/.*: ([0-9]+)x([0-9]+)/\1/')
SCALE=$(awk -v s="$SHORT" 'BEGIN {print s/720}')
px() { awk -v v="$1" -v s="$SCALE" 'BEGIN {printf "%d", v*s}'; }
btn() { log | grep -oE "hud btn $1=\([0-9]+,[0-9]+\)" | tail -1 | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\1 \2/'; }
tap_btn() { read -r bx by < <(btn "$1"); if [ -z "${bx:-}" ]; then ko "button $1 not found"; return 1; fi; "$ADB" shell input tap "$(px "$bx")" "$(px "$by")"; sleep 0.8; }

"$ADB" shell am force-stop "$PKG_NAME"
"$ADB" shell "run-as $PKG_NAME sh -c 'mkdir -p files && echo build4min > files/scenario.txt'"
"$ADB" logcat -c
"$ADB" shell am start -W -n "$PKG_NAME/com.godot.game.GodotAppLauncher" >/dev/null
sleep 4
declare -a UX UY
while read -r idx x y; do UX[$idx]=$x; UY[$idx]=$y; done < <(log | grep -oE "unit [0-9]+ [a-z]+ screen=\([0-9-]+,[0-9-]+\)" | sed -E 's/unit ([0-9]+) [a-z]+ screen=\(([0-9-]+),([0-9-]+)\)/\1 \2 \3/')
MINX=99999; MINY=99999; MAXX=-99999; MAXY=-99999
for i in 0 1 2 3; do
  [ "${UX[$i]}" -lt "$MINX" ] && MINX=${UX[$i]}; [ "${UY[$i]}" -lt "$MINY" ] && MINY=${UY[$i]}
  [ "${UX[$i]}" -gt "$MAXX" ] && MAXX=${UX[$i]}; [ "${UY[$i]}" -gt "$MAXY" ] && MAXY=${UY[$i]}
done
X0=$(px $((MINX-30))); Y0=$(px $((MINY-30))); X1=$(px $((MAXX+30))); Y1=$(px $((MAXY+30)))
"$ADB" shell "input motionevent DOWN $X0 $Y0; sleep 0.6; input motionevent MOVE $(( (X0+X1)/2 )) $(( (Y0+Y1)/2 )); input motionevent MOVE $X1 $Y1; input motionevent UP $X1 $Y1"
sleep 1
expect "box_end selected=4" "box-select the 4 villagers"
tap_btn build && expect "hud btn house=" "Build opens the building menu"
tap_btn house && expect "build begin house" "House enters build mode"
# Tap a spot right of the Town Center (screen centre + 300 px) to move the ghost there.
"$ADB" shell input tap "$(px 1060)" "$(px 360)"; sleep 0.8
tap_btn confirm && expect "build placed house" "✓ places the house foundation"
sleep 12
"$ADB" logcat -c
# Tap the Town Center (screen centre) to select it and train a villager.
"$ADB" shell input tap "$(px 760)" "$(px 360)"; sleep 1
expect "hud btn villager=" "tapping the Town Center shows its train buttons"
tap_btn villager
sleep 1
"$ADB" exec-out screencap -p > "${SHOT:-/tmp/f4.png}"
"$ADB" shell "run-as $PKG_NAME rm -f files/scenario.txt"
echo "== device F4: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
