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

# Retirement documentation intentionally names the old settings keys. Ignore
# comments while preserving code and string literals so an executable settings
# mutation or settings-route target still fails closed.
python3 - "$PULSE" "$SIP_RECEIVE" "$SIP_CALL" <<'PY'
import re
import sys

checks = {
    sys.argv[1]: [r'notification_light_pulse'],
    sys.argv[2]: [r'sip_receive_calls', r'CHANGE_PHONE_ACCOUNTS'],
    sys.argv[3]: [r'sip_call_options', r'Settings\.System'],
}

def strip_comments(text):
    out = []
    i = 0
    state = 'code'
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if state == 'code':
            if ch == '/' and nxt == '/':
                state = 'line_comment'; out.extend('  '); i += 2; continue
            if ch == '/' and nxt == '*':
                state = 'block_comment'; out.extend('  '); i += 2; continue
            if ch == '"': state = 'string'
            elif ch == "'": state = 'char'
            out.append(ch); i += 1; continue
        if state == 'line_comment':
            if ch == '\n': state = 'code'; out.append('\n')
            else: out.append(' ')
            i += 1; continue
        if state == 'block_comment':
            if ch == '*' and nxt == '/':
                state = 'code'; out.extend('  '); i += 2
            else:
                out.append('\n' if ch == '\n' else ' '); i += 1
            continue
        out.append(ch)
        if ch == '\\' and i + 1 < len(text):
            out.append(text[i + 1]); i += 2; continue
        if state == 'string' and ch == '"': state = 'code'
        elif state == 'char' and ch == "'": state = 'code'
        i += 1
    return ''.join(out)

labels = {
    'notification_light_pulse': 'retired notification-light setting mutation reintroduced',
    'sip_receive_calls': 'retired SIP receive setting mutation reintroduced',
    'CHANGE_PHONE_ACCOUNTS': 'retired SIP receive settings route reintroduced',
    'sip_call_options': 'retired SIP call setting mutation reintroduced',
    'Settings\\.System': 'retired SIP call Settings.System path reintroduced',
}
for path, patterns in checks.items():
    clean = strip_comments(open(path, encoding='utf-8').read())
    for pattern in patterns:
        if re.search(pattern, clean):
            raise SystemExit('FAIL: ' + labels[pattern])
PY

echo "PASS: retired notification-light and SIP tracker IDs remain inert compatibility shells"
