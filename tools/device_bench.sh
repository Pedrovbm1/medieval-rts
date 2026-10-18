#!/usr/bin/env bash
# Runs a scenario from game/data/scenarios.json on the phone and prints the
# game's [REALM] perf / scenario lines. Debug APK only (uses run-as).
# Usage: bash tools/device_bench.sh <scenario> <seconds>
set -u
ADB="${ADB:-C:/Users/pedro/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
PKG_NAME="dev.pedro.realm"
ACTIVITY="$PKG_NAME/com.godot.game.GodotAppLauncher"
SCENARIO="${1:-stress150}"
SECONDS_TO_RUN="${2:-20}"

"$ADB" shell am force-stop "$PKG_NAME"
"$ADB" shell "run-as $PKG_NAME sh -c 'mkdir -p files && echo $SCENARIO > files/scenario.txt'"
"$ADB" logcat -c
"$ADB" shell am start -W -n "$ACTIVITY" | tr -d '\r' | grep -E "TotalTime"
sleep "$SECONDS_TO_RUN"
"$ADB" logcat -d -s godot:I | tr -d '\r' | grep -E "\[REALM\] (perf|scenario)" | sed -E 's/.*\[REALM\] //'
# Leave the phone in its normal state (sandbox) for manual play.
"$ADB" shell "run-as $PKG_NAME rm -f files/scenario.txt"
"$ADB" shell am force-stop "$PKG_NAME"
