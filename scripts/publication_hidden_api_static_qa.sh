#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
GLOBALS="$ROOT/src/com/painless/pc/singleton/Globals.java"
NOTIFY_LAYOUT="$ROOT/res/layout/nav_notify.xml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for jar in "$ROOT/libs/hidden-apis.jar" "$ROOT/libs/hidden-apis_2.jar"; do
  [ ! -e "$jar" ] || fail "legacy hidden API stub jar is present: ${jar#$ROOT/}"
done

if grep -RInE --include='*.gradle' --include='*.gradle.kts' \
    'hidden-apis(_2)?\.jar|compileOnly[[:space:]]+files\([^)]*hidden-apis' \
    "$ROOT" --exclude-dir=.git --exclude-dir=build; then
  fail "build files reference legacy hidden API stubs"
fi

mapfile -t java_files < <(find "$ROOT/src" "$ROOT/qa-debug" -type f -name '*.java' 2>/dev/null | sort)
if [ "${#java_files[@]}" -eq 0 ]; then
  fail "no Java source files found to audit"
fi

# Retirement comments intentionally name APIs that must never return. Strip Java
# comments before scanning so documentation cannot masquerade as executable use,
# while leaving imports, code, and string literals intact so reflective targets
# remain detectable.
python3 - "${java_files[@]}" <<'PY'
import re
import sys

forbidden = re.compile(
    r'com\.android\.internal|android\.os\.ServiceManager|android\.os\.SystemProperties|'
    r'android\.os\.IPowerManager|android\.app\.ActivityManagerNative|android\.app\.IActivityManager|'
    r'android\.net\.IConnectivityManager|android\.nfc\.INfcAdapter|IStatusBarService|'
    r'com\.android\.internal\.telephony|com\.painless\.pc\.singleton\.RootTools|'
    r'com\.painless\.pc\.util\.ReflectionUtil|ProcessBuilder\("su"\)|app_process\s|'
    r'\.setAccessible\(\s*true\s*\)|\.getDeclaredMethod\('
)

def strip_comments(text):
    out = []
    i = 0
    state = 'code'
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if state == 'code':
            if ch == '/' and nxt == '/':
                state = 'line_comment'
                out.extend('  ')
                i += 2
                continue
            if ch == '/' and nxt == '*':
                state = 'block_comment'
                out.extend('  ')
                i += 2
                continue
            if ch == '"':
                state = 'string'
            elif ch == "'":
                state = 'char'
            out.append(ch)
            i += 1
            continue
        if state == 'line_comment':
            if ch == '\n':
                state = 'code'
                out.append('\n')
            else:
                out.append(' ')
            i += 1
            continue
        if state == 'block_comment':
            if ch == '*' and nxt == '/':
                state = 'code'
                out.extend('  ')
                i += 2
            else:
                out.append('\n' if ch == '\n' else ' ')
                i += 1
            continue
        # Preserve literals so class names used for reflection remain visible.
        out.append(ch)
        if ch == '\\' and i + 1 < len(text):
            out.append(text[i + 1])
            i += 2
            continue
        if state == 'string' and ch == '"':
            state = 'code'
        elif state == 'char' and ch == "'":
            state = 'code'
        i += 1
    return ''.join(out)

failed = False
for path in sys.argv[1:]:
    text = open(path, encoding='utf-8').read()
    clean = strip_comments(text)
    for line_no, line in enumerate(clean.splitlines(), 1):
        if forbidden.search(line):
            print(f'{path}:{line_no}:{line.strip()}')
            failed = True
if failed:
    raise SystemExit('FAIL: direct hidden/non-SDK, private-reflection, or retired root-execution dependency found in Java source')
PY

# java.lang.reflect itself remains allowed for two bounded public/self-owned uses:
# TrackerManager instantiates classes from its own stable tracker registry, and
# IconPackPicker enumerates fields on this app's generated R.drawable class. The
# dangerous private-member pattern is blocked above via getDeclaredMethod and
# setAccessible(true); the generic ReflectionUtil bridge must remain deleted.

# Notification shade auto-collapse historically used hidden StatusBarManager
# reflection plus EXPAND_STATUS_BAR. Keep the compatibility method harmless and
# keep the old preference/view IDs migration-safe, but never expose or reactivate
# the unsupported behavior in publication source.
! grep -q 'android.permission.EXPAND_STATUS_BAR' "$MANIFEST" || fail "unsupported EXPAND_STATUS_BAR permission reintroduced"
! grep -R -nE 'collapsePanels|invokeGetter\("collapse"\)|getSystemService\("statusbar"\)|getSystemService\(Context\.STATUS_BAR_SERVICE\)' "$ROOT/src" || fail "hidden status-bar collapse path reintroduced"
grep -q 'Compatibility no-op' "$GLOBALS" || fail "status-bar compatibility no-op marker missing"

python3 - "$NOTIFY_LAYOUT" <<'PY'
import sys
import xml.etree.ElementTree as ET

layout = sys.argv[1]
android = "{http://schemas.android.com/apk/res/android}"
root = ET.parse(layout).getroot()
match = None
for node in root.iter():
    if node.get(android + "id") == "@+id/btn_auto_collapse":
        match = node
        break
if match is None:
    raise SystemExit("FAIL: legacy auto-collapse view ID missing")
if match.get(android + "visibility") != "gone":
    raise SystemExit("FAIL: unsupported auto-collapse UI is visible")
print("PASS: unsupported auto-collapse UI remains hidden")
PY

for deleted_bridge in \
    "$ROOT/src/com/painless/pc/CmdFont.java" \
    "$ROOT/src/com/painless/pc/CmdNfc.java" \
    "$ROOT/src/com/painless/pc/CmdUsbT.java" \
    "$ROOT/src/com/painless/pc/singleton/RootTools.java" \
    "$ROOT/src/com/painless/pc/util/ReflectionUtil.java"; do
  [ ! -e "$deleted_bridge" ] || fail "retired hidden/root/reflection command bridge returned: ${deleted_bridge#$ROOT/}"
done

echo "PASS: no legacy hidden API stubs, known direct hidden-framework references, private reflection bridge, retired root execution, or unsupported status-bar collapse path"
