#!/usr/bin/env bash
# F7 device check: Town Center panel with era + tech buttons, then research Era II.
set -u
. "$(dirname "$0")/device_guard.sh" || exit 3
guard_wait_free || exit 2
PKG_NAME="dev.pedro.realm"
OUT="${1:-/tmp/f7.png}"
SHORT=$("$ADB" shell wm size | tr -d '\r' | grep -E "Override|Physical" | tail -1 | sed -E 's/.*: ([0-9]+)x([0-9]+)/\1/')
SCALE=$(awk -v s="$SHORT" 'BEGIN {print s/720}')
px() { awk -v v="$1" -v s="$SCALE" 'BEGIN {printf "%d", v*s}'; }
log() { "$ADB" logcat -d -s godot:I | tr -d '\r'; }
btn() { log | grep -oE "hud btn $1=\([0-9]+,[0-9]+\)" | tail -1 | sed -E 's/.*\(([0-9]+),([0-9]+)\)/\1 \2/'; }
"$ADB" shell am force-stop "$PKG_NAME"
"$ADB" shell "run-as $PKG_NAME sh -c 'mkdir -p files && echo techdemo > files/scenario.txt'"
"$ADB" logcat -c
"$ADB" shell am start -W -n "$PKG_NAME/com.godot.game.GodotAppLauncher" >/dev/null
sleep 4
"$ADB" shell input tap "$(px 760)" "$(px 360)"; sleep 1.5
"$ADB" exec-out screencap -p > "$OUT"
read -r bx by < <(btn "#era2")
if [ -n "${bx:-}" ]; then
  "$ADB" shell input tap "$(px "$bx")" "$(px "$by")"
  echo "tapped era2 at $bx,$by"; sleep 70
  log | grep -E "era player=0" && echo "ERA OK"
  "$ADB" exec-out screencap -p > "${OUT%.png}_era2.png"
else
  echo "no era2 button"; log | grep "hud btn" | tail -5
fi
"$ADB" shell "run-as $PKG_NAME rm -f files/scenario.txt"
guard_release
