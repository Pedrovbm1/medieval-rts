#!/usr/bin/env bash
# F8 device test with real touches: title menu -> New game -> Normal, minimap
# tap, pause menu -> Save, quit to menu -> Continue. Reads [REALM] log lines.
set -u
. "$(dirname "$0")/device_guard.sh" || exit 3
guard_wait_free || exit 2
PKG_NAME="dev.pedro.realm"
PASS=0; FAIL=0
SHORT=$("$ADB" shell wm size | tr -d '\r' | grep -E "Override|Physical" | tail -1 | sed -E 's/.*: ([0-9]+)x([0-9]+)/\1/')
LONG=$("$ADB" shell wm size | tr -d '\r' | grep -E "Override|Physical" | tail -1 | sed -E 's/.*: ([0-9]+)x([0-9]+)/\2/')
SCALE=$(awk -v s="$SHORT" 'BEGIN {print s/720}')
VW=$(awk -v l="$LONG" -v s="$SCALE" 'BEGIN {printf "%d", l/s}')
px() { awk -v v="$1" -v s="$SCALE" 'BEGIN {printf "%d", v*s}'; }
log() { "$ADB" logcat -d -s godot:I | tr -d '\r'; }
ok() { echo "  PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); log | grep REALM | tail -4; }
expect() { if log | grep -qE "$1"; then ok "$2"; else ko "$2"; fi; }
tap() { "$ADB" shell input tap "$(px "$1")" "$(px "$2")"; sleep "${3:-1}"; }
# Tap a logged button by its label: "[REALM] (menu|hud) btn <label>=(x,y)".
tap_label() {
  local line; line=$(log | grep -oE "btn $1=\([0-9]+,[0-9]+\)" | tail -1)
  if [ -z "$line" ]; then ko "button '$1' not found"; return 1; fi
  local x y; x=$(echo "$line" | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\1/'); y=$(echo "$line" | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\2/')
  tap "$x" "$y" "${2:-1.5}"
}

"$ADB" shell am force-stop "$PKG_NAME"
"$ADB" shell "run-as $PKG_NAME sh -c 'rm -f files/scenario.txt files/save_auto.json files/save_manual.json'"
"$ADB" logcat -c
"$ADB" shell am start -W -n "$PKG_NAME/com.godot.game.GodotAppLauncher" >/dev/null
sleep 3
CX=$((VW / 2))
# Title menu: buttons are centred; with no save the first is "New game".
tap_label "Nueva partida" 1.5
tap_label "Normal" 1.5
tap_label "Valle del Río" 5
expect "scenario skirmish start" "title menu -> New game -> Normal -> Valle del Río starts a skirmish"
# Minimap sits bottom-left: tap its centre.
tap 112 568 1
expect "perf|scenario" "the match is running after the minimap tap"
# Pause menu (top-right ≡), then Save (second button).
tap $((VW - 48)) 44 1.5
tap_label "Guardar partida" 2
expect "saved slot=manual err=0" "pause menu -> Save writes a save"
tap $((VW - 48)) 44 1.5
tap_label "Salir al menú" 3
expect "saved slot=auto" "quitting autosaves first"
"$ADB" logcat -c
sleep 1
tap_label "Continuar partida" 5
expect "scenario|saved" "Continue loads the saved match"
"$ADB" exec-out screencap -p > "${SHOT:-/tmp/f8.png}"
guard_release
echo "== device F8: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
