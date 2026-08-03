#!/usr/bin/env bash
# pulse-bring-up.sh — reproducible two-emulator + signaling stack for Pulse.
# Idempotent: safe to re-run; kills only conflicting processes.
set -u

SDK="${LOCALAPPDATA:-$HOME/AppData/Local}/Android/Sdk"
ADB="$SDK/platform-tools/adb.exe"
EMU="$SDK/emulator/emulator.exe"
APK="C:/Users/Sayd/PrilaDlyaMolodej/Pulse/build/app/outputs/flutter-apk/app-debug.apk"
SIG_DIR="C:/Users/Sayd/PrilaDlyaMolodej/Pulse/signaling"

log() { echo "[stack] $*"; }

# --- 0) Kill stale wrangler + emulator instances
log "killing stale listeners on :8787 …"
for pid in $(netstat -ano | grep ":8787.*LISTEN" | awk '{print $NF}' | sort -u); do
  powershell.exe -NoProfile -Command "Stop-Process -Id $pid -Force" 2>/dev/null
done
log "killing emulator processes …"
powershell.exe -NoProfile -Command "Get-Process emulator -ErrorAction SilentlyContinue | Stop-Process -Force" 2>/dev/null
"$ADB" kill-server >/dev/null 2>&1
sleep 2

# --- 1) Signaling server
log "starting wrangler dev on 127.0.0.1:8787 …"
( cd "$SIG_DIR" && exec npx wrangler dev --port 8787 --local --ip 127.0.0.1 ) &
WPID=$!
for i in $(seq 1 20); do
  if curl -sS -m 2 http://127.0.0.1:8787/health >/dev/null 2>&1; then
    log "wrangler ready (pid $WPID)"; break
  fi
  sleep 1
done
curl -sS http://127.0.0.1:8787/health || { log "ERROR: signaling not up"; exit 1; }
echo

# --- 2) Two AVDs
log "starting AVD A (port 5554) …"
"$EMU" -avd pulse_emulator   -port 5554 -no-snapshot-load -no-boot-anim \
       -gpu swiftshader_indirect -noaudio -no-window >/dev/null 2>&1 &
log "starting AVD B (port 5556) …"
"$EMU" -avd pulse_emulator_b -port 5556 -no-snapshot-load -no-boot-anim \
       -gpu swiftshader_indirect -noaudio -no-window >/dev/null 2>&1 &

for s in emulator-5554 emulator-5556; do
  "$ADB" -s $s wait-for-device
  for i in $(seq 1 60); do
    if [ "$("$ADB" -s $s shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      log "$s booted"; break
    fi
    sleep 3
  done
done

# --- 3) Skip rebuild if APK exists
if [ ! -f "$APK" ]; then
  log "building APK …"
  ( cd "C:/Users/Sayd/PrilaDlyaMolodej/Pulse" && \
    flutter build apk --debug \
      --dart-define=SIGNALING_BASE_URL=http://10.0.2.2:8787 \
      --dart-define=useRealBleTransport=false )
fi

# --- 4) Install + reset
for s in emulator-5554 emulator-5556; do
  log "installing APK on $s …"
  "$ADB" -s $s install -r "$APK" | tail -1
  "$ADB" -s $s shell pm clear io.pulseapp.pulse >/dev/null
  "$ADB" -s $s shell am force-stop io.pulseapp.pulse
done
sleep 2

log "done — devices:"
"$ADB" devices
log "to start UIs: $ADB -s emulator-5554 shell am start -n io.pulseapp.pulse/.MainActivity"
