#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

forbidden='com\.android\.internal|android\.os\.ServiceManager|android\.os\.SystemProperties|android\.os\.IPowerManager|android\.app\.ActivityManagerNative|android\.app\.IActivityManager|android\.net\.IConnectivityManager|android\.nfc\.INfcAdapter|IStatusBarService|com\.android\.internal\.telephony'
if grep -nE "$forbidden" "${java_files[@]}"; then
  fail "direct hidden/non-SDK framework dependency found in Java source"
fi

for deleted_bridge in \
    "$ROOT/src/com/painless/pc/CmdFont.java" \
    "$ROOT/src/com/painless/pc/CmdNfc.java" \
    "$ROOT/src/com/painless/pc/CmdUsbT.java"; do
  [ ! -e "$deleted_bridge" ] || fail "retired hidden command bridge returned: ${deleted_bridge#$ROOT/}"
done

echo "PASS: no legacy hidden API stub jars, Gradle dependencies, or known direct hidden-framework Java references"
