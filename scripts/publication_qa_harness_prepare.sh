#!/usr/bin/env bash
set -euo pipefail

# QA-only normalization for publication CI. This does not touch shipping source.
# 1) Attribute fatal/ANR checks to Power Toggles instead of treating unrelated
#    emulator-process crashes as candidate crashes.
# 2) Keep the import/export divergence fixture inside run-as by preserving the
#    inner shell redirection instead of letting adb's outer shell consume it.
python3 - <<'PY'
from pathlib import Path

fatal_old = r'FATAL EXCEPTION|Process: com\\.painless\\.pc.*has died|ANR in com\\.painless\\.pc|am_crash.*com\\.painless\\.pc|am_anr.*com\\.painless\\.pc'
fatal_new = r'Process: com\\.painless\\.pc(?:,|[[:space:]])|Process com\\.painless\\.pc.*has died|ANR in com\\.painless\\.pc|am_crash.*com\\.painless\\.pc|am_anr.*com\\.painless\\.pc'

for name in (
    'scripts/gate2a_runtime_qa.sh',
    'scripts/publication_runtime_qa.sh',
    'scripts/publication_import_export_qa.sh',
):
    path = Path(name)
    text = path.read_text()
    count = text.count(fatal_old)
    if count < 1:
        raise SystemExit(f'Expected fatal-scan anchor missing from {name}')
    path.write_text(text.replace(fatal_old, fatal_new))
    print(f'{name}: candidate-scoped fatal scan replacements={count}')

path = Path('scripts/publication_import_export_qa.sh')
text = path.read_text()
old = "cat \"$OUT/state/widget-prefs-mutated.xml\" | adb shell run-as com.painless.pc sh -c 'cat > shared_prefs/widget_preference.xml'"
new = "adb shell \"run-as com.painless.pc sh -c 'cat > shared_prefs/widget_preference.xml'\" < \"$OUT/state/widget-prefs-mutated.xml\""
if text.count(old) != 1:
    raise SystemExit('Expected run-as mutation anchor missing or non-unique')
path.write_text(text.replace(old, new, 1))
print('publication_import_export_qa.sh: run-as mutation redirect repaired')
PY

echo "Publication QA harness preparation: PASS"
