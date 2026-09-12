#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="$ROOT/src/com/painless/pc/singleton/WidgetDB.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Legacy shortcut/icon rows can survive across upgrades and can be restored from
# user-selected backups. Decode stored image blobs through the same bounds-first
# bitmap gate used by current import surfaces; never return to a direct full
# BitmapFactory decode of database bytes.
grep -q 'import com.painless.pc.util.BitmapImportUtils;' "$DB" || fail "bounded bitmap decoder import missing"
grep -q 'BitmapImportUtils.decode(bitmapData)' "$DB" || fail "legacy widget icon blob bypasses bounded bitmap decoder"
! grep -q 'BitmapFactory.decodeByteArray' "$DB" || fail "direct legacy database bitmap decode returned"

# Database read cursors are long-lived-process resources. Both shortcut and icon
# reads must close them on success and every exceptional return path.
grep -q 'throw new IllegalStateException("Missing shortcut " + parsedId)' "$DB" || fail "missing shortcut row is not handled explicitly"
grep -q '"_id = ?"' "$DB" || fail "shortcut lookup is not parameterized"
close_count="$(grep -c 'cursor.close();' "$DB")"
[ "$close_count" -ge 3 ] || fail "database read cursors are not all fail-closed"

echo "PASS: legacy widget database image decoding and cursor lifetimes are bounded"
