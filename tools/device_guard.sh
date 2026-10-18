#!/usr/bin/env bash
# Shared-phone etiquette for the Galaxy S10+ test device (R58M154WY9A), agreed
# with the other Claude sessions that use it (AppScanner: com.pedro.escaner,
# Mateo's game: mx.mateo.misioncolima). Source it from device scripts:
#   . "$(dirname "$0")/device_guard.sh"; guard_wait_free; ...; guard_release
# Rules: never touch the screen / start apps while another app is in front;
# `adb install -r` is always fine; when done, force-stop our app and go home.
ADB="${ADB:-C:/Users/pedro/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
OUR_PKG="dev.pedro.realm"
OTHER_PKGS="com.pedro.escaner mx.mateo.misioncolima"
GUARD_MAX_WAIT_S="${GUARD_MAX_WAIT_S:-600}"

guard_foreground() {
  "$ADB" shell dumpsys activity activities | tr -d '\r' | grep -m1 "mResumedActivity" | sed -E 's/.* ([a-zA-Z0-9_.]+)\/.*/\1/'
}

# Waits until no other session's app is in front. Returns 1 on timeout.
guard_wait_free() {
  local waited=0 fg
  while :; do
    fg=$(guard_foreground)
    local busy=0
    for p in $OTHER_PKGS; do [ "$fg" = "$p" ] && busy=1; done
    if [ "$busy" -eq 0 ]; then return 0; fi
    if [ "$waited" -ge "$GUARD_MAX_WAIT_S" ]; then
      echo "guard: $fg is still in front after ${waited}s; not touching the phone" >&2
      return 1
    fi
    echo "guard: $fg in front, waiting..." >&2
    sleep 10; waited=$((waited + 10))
  done
}

# Leaves the phone free: our app stopped, launcher in front.
guard_release() {
  "$ADB" shell am force-stop "$OUR_PKG"
  "$ADB" shell input keyevent KEYCODE_HOME
}
