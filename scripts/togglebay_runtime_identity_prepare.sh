#!/usr/bin/env bash
set -euo pipefail

# QA-only runtime translation for the final public package. Shipping Java remains in
# the restored com.painless.pc namespace while Android installs the app as
# app.sufficient.togglebay. Static source QA runs before this script.
python3 - <<'PY'
from pathlib import Path

runtime_scripts = [
    'scripts/gate2a_runtime_qa.sh',
    'scripts/gate2a_fidelity_qa.sh',
    'scripts/publication_runtime_qa.sh',
    'scripts/publication_import_export_qa.sh',
    'scripts/publication_folder_backup_share_qa.sh',
    'scripts/publication_settings_route_qa.sh',
    'scripts/publication_write_settings_qa.sh',
    'scripts/publication_media_ui_qa.sh',
    'scripts/publication_media_behavior_qa.sh',
    'scripts/publication_rotation_setting_qa.sh',
    'scripts/publication_api36_compat_qa.sh',
    'scripts/publication_screen_on_card_qa.sh',
    'scripts/publication_rotation_picker_qa.sh',
    'scripts/publication_remaining_controls_qa.sh',
    'scripts/publication_next_controls_qa.sh',
    'scripts/publication_widget_settings_qa.sh',
]

for name in runtime_scripts:
    p = Path(name)
    text = p.read_text()
    if 'com.painless.pc' not in text:
        print(f'{name}: no legacy runtime package tokens')
        continue

    # Runtime package/authority/resource-id/process identity follows applicationId.
    text = text.replace('com.painless.pc', 'app.sufficient.togglebay')

    # Component classes intentionally remain in the restored Java namespace.
    text = text.replace(
        'app.sufficient.togglebay/.',
        'app.sufficient.togglebay/com.painless.pc.')
    text = text.replace(
        'app.sufficient.togglebay/app.sufficient.togglebay.',
        'app.sufficient.togglebay/com.painless.pc.')

    # Runtime scripts also contain source-tree assertions. The source namespace is
    # deliberately unchanged, so restore path/package assertions after translating
    # Android runtime identity.
    text = text.replace('src/app/sufficient/togglebay', 'src/com/painless/pc')
    text = text.replace('qa-debug/src/app/sufficient/togglebay', 'qa-debug/src/com/painless/pc')
    text = text.replace('package app.sufficient.togglebay', 'package com.painless.pc')
    text = text.replace('import app.sufficient.togglebay', 'import com.painless.pc')

    p.write_text(text)
    print(f'{name}: ToggleBay runtime identity normalized')

print('ToggleBay runtime identity preparation: PASS')
PY
