#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build.gradle"
MANIFEST="$ROOT/AndroidManifest.xml"
BOUNDARY="$ROOT/qa/FINAL_RELEASE_BOUNDARIES.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# This branch is a technical pre-identity candidate. Preserve the exact current
# package/SDK/version boundary until Ramy explicitly authorizes permanent release
# identity changes; do not silently turn QA/restoration metadata into final identity.
grep -Fq 'namespace "com.painless.pc"' "$BUILD" || fail "namespace drifted"
grep -Fq 'applicationId "com.painless.pc"' "$BUILD" || fail "applicationId drifted"
grep -Fq 'compileSdkVersion 36' "$BUILD" || fail "compileSdk is not 36"
grep -Fq 'targetSdkVersion 36' "$BUILD" || fail "targetSdk is not 36"
grep -Fq 'minSdkVersion 16' "$BUILD" || fail "minSdk drifted"
grep -Fq 'versionCode 160604' "$BUILD" || fail "Gradle versionCode drifted"
grep -Fq 'versionName "6.0.4-gate2a"' "$BUILD" || fail "pre-identity Gradle versionName drifted without identity approval"
grep -Fq 'android:versionCode="160604"' "$MANIFEST" || fail "manifest versionCode drifted"
grep -Fq 'android:versionName="6.0.4"' "$MANIFEST" || fail "historical manifest versionName drifted"
grep -q 'G9 — identity decision required before permanent release bytes' "$BOUNDARY" || fail "G9 identity boundary documentation missing"
grep -Fq 'Gradle version name: `6.0.4-gate2a`' "$BOUNDARY" || fail "documented pre-identity version boundary drifted"

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
        raise SystemExit('FAIL: pre-identity repository contains signing configuration/material reference: ' + token)
for token in ('debuggable true', 'testOnly true'):
    if token in text:
        raise SystemExit('FAIL: release source contains debug/test-only package flag: ' + token)
for token in ('implementation ', 'api ', 'runtimeOnly ', 'compileOnly '):
    if token in text:
        raise SystemExit('FAIL: unexpected app runtime/compile dependency declaration: ' + token.strip())
print('PASS: release/debug source and signing boundaries are isolated')
PY

! grep -Eq 'android:(debuggable|testOnly)="true"' "$MANIFEST" || fail "production manifest is debug/test-only"

echo "PASS: pre-identity package metadata, release source isolation, and no-signing boundary are pinned"
