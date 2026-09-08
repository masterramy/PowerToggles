#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/folder-backup-share"
mkdir -p "$OUT/state"
SRC="src/com/painless/pc/nav/FolderFrag.java"
PROVIDER="src/com/painless/pc/FileProvider.java"
rc=0

check_absent() {
  local pattern="$1"
  local label="$2"
  if grep -Eq "$pattern" "$SRC"; then
    printf 'RED %s\n' "$label" | tee -a "$OUT/state/source-contract.txt" >&2
    rc=1
  else
    printf 'PASS %s\n' "$label" | tee -a "$OUT/state/source-contract.txt"
  fi
}

check_present() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "$pattern" "$file"; then
    printf 'PASS %s\n' "$label" | tee -a "$OUT/state/source-contract.txt"
  else
    printf 'RED %s\n' "$label" | tee -a "$OUT/state/source-contract.txt" >&2
    rc=1
  fi
}

: > "$OUT/state/source-contract.txt"
check_absent 'MODE_WORLD_READABLE' 'folder share never uses world-readable private files'
check_absent 'Uri\.fromFile\(' 'folder share never exposes file:// URIs'
check_present "$SRC" 'ACTION_CREATE_DOCUMENT' 'folder backup uses framework document creation'
check_present "$SRC" 'ACTION_OPEN_DOCUMENT' 'folder restore uses framework document opening'
check_present "$SRC" 'FLAG_GRANT_READ_URI_PERMISSION' 'folder share grants read access explicitly'
check_present "$SRC" 'content://com\.painless\.pc\.file/folder-share' 'folder share uses the scoped content URI'
check_present "$PROVIDER" 'folder-share' 'provider exposes a dedicated folder-share path'

if [ "$rc" -ne 0 ]; then
  echo 'Folder backup/share publication contract is RED.' >&2
fi
exit "$rc"
