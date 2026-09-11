#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QTINFO="$ROOT/src/com/painless/pc/qs/QTInfo.java"
TILE="$ROOT/src/com/painless/pc/qs/TileConfigActivity.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Persisted/imported Quick Settings definitions are attacker-controlled once a
# user selects an external backup. Keep the JSON allocation and state-image
# cardinality bounded to the four rendered tile states.
grep -q 'MAX_ICON_COUNT = 4' "$QTINFO" || fail "tile icon-count ceiling missing"
grep -q 'MAX_DEFINITION_CHARS = 64 \* 1024' "$QTINFO" || fail "tile definition bound missing"
grep -q 'iconCount < 1 || iconCount > MAX_ICON_COUNT' "$QTINFO" || fail "tile icon-count validation missing"
grep -q 'iconCount != expectedIconCount' "$QTINFO" || fail "tile tracker/icon cardinality mismatch is not rejected"
grep -q 'diplayNum < 0 || diplayNum >= icons.length' "$QTINFO" || fail "tile runtime icon index is not fail-closed"
grep -q 'pos < 0 || pos >= icons.length' "$QTINFO" || fail "tile icon lazy-load index is not bounded"

# The outer SAF import file has a size ceiling, but ZIP entries can expand far
# beyond that. Bound decompressed config/icon entries independently and validate
# image dimensions before any UI decode/normalization.
grep -q 'MAX_TILE_CONFIG_BYTES = 64L \* 1024L' "$TILE" || fail "tile config ZIP-entry bound missing"
grep -q 'MAX_TILE_ICON_BYTES = 512L \* 1024L' "$TILE" || fail "tile icon ZIP-entry bound missing"
grep -q 'readZipEntry(zip, "config.txt", MAX_TILE_CONFIG_BYTES, true)' "$TILE" || fail "tile config import bypasses bounded ZIP reader"
grep -q 'readZipEntry(zip, "icon_" + i, MAX_TILE_ICON_BYTES, true)' "$TILE" || fail "tile icon import bypasses bounded ZIP reader"
grep -q 'BackupUtil.copy(in, out, maxBytes)' "$TILE" || fail "tile ZIP reader is not decompression-bounded"
grep -q 'BitmapImportUtils.decode(iconBytes)' "$TILE" || fail "tile archive icon is not bounds-first validated"
grep -q 'BitmapImportUtils.decode(existingTile.icons\[i\])' "$TILE" || fail "tile UI path bypasses bounds-first bitmap decode"
! grep -q 'ParseUtil.readStream(zip.getInputStream' "$TILE" || fail "unbounded tile ZIP stream read returned"
! grep -q 'BitmapFactory.decodeByteArray(existingTile.icons' "$TILE" || fail "direct unbounded tile bitmap decode returned"

echo "PASS: Quick Settings tile import is cardinality-, decompression-, bitmap-, and runtime-index bounded"
