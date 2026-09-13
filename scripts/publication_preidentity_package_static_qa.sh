#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build.gradle"
MANIFEST="$ROOT/AndroidManifest.xml"
VALUES="$ROOT/res/values/values.xml"
INFO="$ROOT/res/xml/app_info.xml"
PRIVACY="$ROOT/PRIVACY.md"
README="$ROOT/README.md"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"
PUBLIC_STRINGS="$ROOT/res/values/togglebay_public_strings.xml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# The public identity decision is explicit. Preserve the restored Java/R namespace
# while pinning the independent customer package and app-owned Android authorities.
grep -Fq 'namespace "com.painless.pc"' "$BUILD" || fail "restored Java namespace drifted"
grep -Fq 'applicationId "com.ramybaheeg.togglebay"' "$BUILD" || fail "ToggleBay applicationId missing"
grep -Fq 'compileSdkVersion 36' "$BUILD" || fail "compileSdk is not 36"
grep -Fq 'targetSdkVersion 36' "$BUILD" || fail "targetSdk is not 36"
grep -Fq 'minSdkVersion 16' "$BUILD" || fail "minSdk drifted"
grep -Fq 'versionCode 1' "$BUILD" || fail "public versionCode is not 1"
grep -Fq 'versionName "1.0.0"' "$BUILD" || fail "public versionName is not 1.0.0"
grep -Fq 'android:versionCode="1"' "$MANIFEST" || fail "manifest versionCode drifted"
grep -Fq 'android:versionName="1.0.0"' "$MANIFEST" || fail "manifest versionName drifted"
grep -Fq '<string name="app_name">ToggleBay</string>' "$VALUES" || fail "ToggleBay app label missing"
grep -Fq 'android:icon="@drawable/togglebay_launcher"' "$MANIFEST" || fail "independent launcher icon not wired"
grep -Fq 'com.ramybaheeg.togglebay.permission.CONTROL_PLUGIN' "$MANIFEST" || fail "independent plugin permission missing"
grep -Fq 'com.ramybaheeg.togglebay.permission.READ_FOLDER_SHARE' "$MANIFEST" || fail "independent folder-share permission missing"
grep -Fq 'android:authorities="com.ramybaheeg.togglebay.file"' "$MANIFEST" || fail "independent provider authority missing"
grep -Fq 'AUTHORITY = "com.ramybaheeg.togglebay.file"' "$PROVIDER" || fail "runtime provider authority missing"
grep -Fq '@string/togglebay_privacy_title' "$INFO" || fail "in-app privacy surface missing"
grep -Fq 'ToggleBay is published by Ramy Baheeg.' "$PRIVACY" || fail "publisher missing from privacy policy"
grep -Fq '<string name="togglebay_publisher_summary">Ramy Baheeg</string>' "$PUBLIC_STRINGS" || fail "in-app publisher identity missing"
grep -Fq 'not affiliated with or endorsed by the original' "$README" || fail "independent-restoration disclosure missing"

# Withdrawn identity must never leak into the public candidate.
if grep -R -n -E 'app\.sufficient\.togglebay|Sufficient Systems' \
    "$BUILD" "$MANIFEST" "$PRIVACY" "$PUBLIC_STRINGS" "$PROVIDER" "$ROOT/scripts/togglebay_runtime_identity_prepare.sh"; then
  fail "withdrawn Sufficient identity remains in public candidate"
fi

# QA probe code/manifests belong to the debug variant only. Release source must be
# production src/res/manifest and must not silently inherit debug harness classes.
grep -Fq "java.srcDirs = ['src']" "$BUILD" || fail "main production source set drifted"
grep -Fq "manifest.srcFile 'AndroidManifest.xml'" "$BUILD" || fail "main production manifest drifted"
grep -Fq "java.srcDirs = ['qa-debug/src']" "$BUILD" || fail "debug QA source-set isolation missing"
grep -Fq "manifest.srcFile 'qa-debug/AndroidManifest.xml'" "$BUILD" || fail "debug QA manifest isolation missing"

python3 - "$BUILD" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding='utf-8').read()
release = re.search(r'\brelease\s*\{(.*?)\n\s*\}', text, re.S)
if not release:
    raise SystemExit('FAIL: release build type missing')
if 'qa-debug' in release.group(1):
    raise SystemExit('FAIL: release build type references QA debug source')
for token in ('signingConfig', 'storeFile', 'storePassword', 'keyAlias', 'keyPassword'):
    if token in text:
        raise SystemExit('FAIL: repository contains signing configuration/material reference: ' + token)
for token in ('debuggable true', 'testOnly true'):
    if token in text:
        raise SystemExit('FAIL: release source contains debug/test-only package flag: ' + token)
for token in ('implementation ', 'api ', 'runtimeOnly ', 'compileOnly '):
    if token in text:
        raise SystemExit('FAIL: unexpected app runtime/compile dependency declaration: ' + token.strip())
print('PASS: release/debug source and signing boundaries are isolated')
PY

! grep -Eq 'android:(debuggable|testOnly)="true"' "$MANIFEST" || fail "production manifest is debug/test-only"

echo "PASS: ToggleBay public identity, package, privacy, attribution, and no-signing boundaries are pinned"
