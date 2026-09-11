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

forbidden='com\.android\.internal|android\.os\.ServiceManager|android\.os\.SystemProperties|android\.os\.IPowerManager|android\.app\.ActivityManagerNative|android\.app\.IActivityManager|android\.net\.IConnectivityManager|android\.nfc\.INfcAdapter|IStatusBarService|com\.android\.internal\.telephony|com\.painless\.pc\.singleton\.RootTools|com\.painless\.pc\.util\.ReflectionUtil|ProcessBuilder\("su"\)|app_process[[:space:]]|\.setAccessible\([[:space:]]*true[[:space:]]*\)|\.getDeclaredMethod\('
if grep -nE "$forbidden" "${java_files[@]}"; then
  fail "direct hidden/non-SDK, private-reflection, or retired root-execution dependency found in Java source"
fi

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
