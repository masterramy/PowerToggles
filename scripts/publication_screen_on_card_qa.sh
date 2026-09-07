#!/usr/bin/env bash
set -u

OUT="runtime-evidence/screen-on-card"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationCompatProbeActivity"

run_probe() {
  local name="$1"
  adb shell am start -W -n "$PROBE" --es probe "$name" > "$OUT/state/${name}-start.txt" 2>&1
  local rc=$?
  sleep 2
  return $rc
}

dump_ui() {
  local slug="$1"
  local remote="/sdcard/${slug}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  rm -f "$OUT/ui/${slug}.xml"
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${slug}.xml" >/dev/null 2>&1 || true
      [ -s "$OUT/ui/${slug}.xml" ] && return 0
    fi
    sleep 1
  done
  return 1
}

had_post_notifications=false
if adb shell dumpsys package "$PKG" | grep -F 'android.permission.POST_NOTIFICATIONS: granted=true' >/dev/null 2>&1; then
  had_post_notifications=true
fi
printf 'original_post_notifications=%s\n' "$had_post_notifications" > "$OUT/state/permission-original.txt"

cleanup() {
  run_probe screen_on_disable >/dev/null 2>&1 || true
  run_probe screen_on_restore_notification_pref >/dev/null 2>&1 || true
  if [ "$had_post_notifications" = "true" ]; then
    adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  else
    adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  fi
  adb shell cmd statusbar collapse >/dev/null 2>&1 || true
}
trap cleanup EXIT

adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true
run_probe screen_on_prepare_notification
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS
run_probe screen_on_enable
sleep 3

adb shell dumpsys activity services "$PKG" > "$OUT/state/screen-on-services.txt" 2>&1 || true
adb shell dumpsys notification --noredact > "$OUT/state/screen-on-notification.txt" 2>&1 || true
adb logcat -d > "$OUT/logs/screen-on-card.logcat.txt"

grep -q 'ScreenOnService' "$OUT/state/screen-on-services.txt"
grep -Eq 'NotificationRecord\(.*pkg=com\.painless\.pc|pkg=com\.painless\.pc.*id=103' "$OUT/state/screen-on-notification.txt"
grep -q 'persistent_controls' "$OUT/state/screen-on-notification.txt"
if grep -E 'FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc' "$OUT/logs/screen-on-card.logcat.txt"; then
  echo 'Power Toggles fatal/ANR during Screen Always On notification-card proof'
  exit 1
fi

adb shell cmd statusbar expand-notifications >/dev/null 2>&1 || true
sleep 2
dump_ui screen-on-card-shade
adb exec-out screencap -p > "$OUT/screens/screen-on-card-shade.png"
adb shell dumpsys window windows > "$OUT/state/screen-on-card-shade.windows.txt" 2>&1 || true
adb shell dumpsys activity activities > "$OUT/state/screen-on-card-shade.activities.txt" 2>&1 || true

grep -q 'package="com.android.systemui"' "$OUT/ui/screen-on-card-shade.xml"
grep -Fq 'text="Wake lock active"' "$OUT/ui/screen-on-card-shade.xml"
grep -Fq 'text="Click to deactivate"' "$OUT/ui/screen-on-card-shade.xml"

run_probe screen_on_disable
sleep 2
adb shell dumpsys activity services "$PKG" > "$OUT/state/screen-on-disabled-services.txt" 2>&1 || true
adb shell dumpsys notification --noredact > "$OUT/state/screen-on-disabled-notification.txt" 2>&1 || true
if grep -q 'ScreenOnService' "$OUT/state/screen-on-disabled-services.txt"; then
  echo 'ScreenOnService remained running after disable'
  exit 1
fi
if grep -Eq 'NotificationRecord\(.*pkg=com\.painless\.pc.*id=103|pkg=com\.painless\.pc.*id=103' "$OUT/state/screen-on-disabled-notification.txt"; then
  echo 'Screen Always On foreground notification remained active after disable'
  exit 1
fi

run_probe screen_on_restore_notification_pref
if [ "$had_post_notifications" = "true" ]; then
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
else
  adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
fi
trap - EXIT
adb shell cmd statusbar collapse >/dev/null 2>&1 || true

printf '%s\n' \
  'screen_always_on_visible_card=PASS' \
  'notification_title=Wake lock active' \
  'notification_subtitle=Click to deactivate' \
  "post_notifications_restored=$had_post_notifications" \
  > "$OUT/summary.txt"
cat "$OUT/summary.txt"
