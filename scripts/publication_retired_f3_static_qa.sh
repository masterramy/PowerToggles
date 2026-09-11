#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PULSE="$ROOT/src/com/painless/pc/tracker/PulseLightTracker.java"
SIP_RECEIVE="$ROOT/src/com/painless/pc/tracker/SipReceiveTracker.java"
SIP_CALL="$ROOT/src/com/painless/pc/tracker/SipCallTracker.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# IDs 40-42 are RETIRED_F3 but must remain class-loadable because historical
# widget definitions retain stable tracker IDs. Publication source therefore
# preserves inert compatibility shells while forbidding the obsolete settings
# mutation keys/actions that previously made those retired controls executable.
for file in "$PULSE" "$SIP_RECEIVE" "$SIP_CALL"; do
  grep -q 'RETIRED_F3' "$file" || fail "retired F3 marker missing: ${file#$ROOT/}"
  grep -q 'return STATE_DISABLED' "$file" || fail "retired F3 shell is not fail-closed: ${file#$ROOT/}"
  ! grep -q 'AbstractSystemSettingsTracker' "$file" || fail "retired F3 shell regained Settings.System mutation base: ${file#$ROOT/}"
done

! grep -q 'notification_light_pulse' "$PULSE" || fail "retired notification-light setting mutation reintroduced"
! grep -q 'sip_receive_calls' "$SIP_RECEIVE" || fail "retired SIP receive setting mutation reintroduced"
! grep -q 'CHANGE_PHONE_ACCOUNTS' "$SIP_RECEIVE" || fail "retired SIP receive settings route reintroduced"
! grep -q 'sip_call_options' "$SIP_CALL" || fail "retired SIP call setting mutation reintroduced"
! grep -q 'Settings.System' "$SIP_CALL" || fail "retired SIP call Settings.System path reintroduced"

echo "PASS: retired notification-light and SIP tracker IDs remain inert compatibility shells"
