#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
LEGACY="$ROOT/res/xml/backup_rules.xml"
MODERN="$ROOT/res/xml/data_extraction_rules.xml"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

grep -Fq 'android:allowBackup="true"' "$MANIFEST" || fail "User-data migration unexpectedly disabled"
grep -Fq 'android:fullBackupContent="@xml/backup_rules"' "$MANIFEST" || fail "Legacy backup rules not wired"
grep -Fq 'android:dataExtractionRules="@xml/data_extraction_rules"' "$MANIFEST" || fail "Modern extraction rules not wired"

for rules in "$LEGACY" "$MODERN"; do
  grep -Fq 'domain="sharedpref" path="file_provider_capabilities.xml"' "$rules" || fail "File-provider capability tokens are backup-eligible: $rules"
  grep -Fq 'domain="file" path="folder.pcf"' "$rules" || fail "Generated folder share archive is backup-eligible: $rules"
  grep -Fq 'domain="file" path="widget.zip"' "$rules" || fail "Generated widget share archive is backup-eligible: $rules"
done

# Keep the exclusions coupled to the actual capability/share implementation so a
# future filename change cannot silently bypass the backup boundary.
grep -Fq 'BACK_TOKEN_PREFS = "file_provider_capabilities"' "$PROVIDER" || fail "Capability preference name changed without backup review"
grep -Fq 'FOLDER_SHARE_FILE_NAME = "folder.pcf"' "$PROVIDER" || fail "Folder share filename changed without backup review"
grep -Fq 'WIDGET_SHARE_FILE_NAME = "widget.zip"' "$PROVIDER" || fail "Widget share filename changed without backup review"

echo "PASS: backup keeps user migration while excluding ephemeral capabilities/share artifacts"
