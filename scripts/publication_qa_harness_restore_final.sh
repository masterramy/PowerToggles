#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/publication_folder_backup_share_qa.sh"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = 'tap_node "11-backup-select-source" "$BACKUP_NAME"'
new = 'tap_node "11-backup-select-source" "com.google.android.documentsui:id/item_root"'
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one restore filename tap, found {count}")
path.write_text(text.replace(old, new, 1))
PY

grep -Fq 'tap_node "11-backup-select-source" "com.google.android.documentsui:id/item_root"' "$TARGET"
echo 'scripts/publication_folder_backup_share_qa.sh: restore picker taps clickable document row'
echo 'Publication QA restore final normalization: PASS'
