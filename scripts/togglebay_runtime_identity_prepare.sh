#!/usr/bin/env bash
set -euo pipefail

# QA-only runtime translation for the final public package. Shipping Java remains in
# the restored com.painless.pc namespace while Android installs the app as
# com.ramybaheeg.togglebay. Static source QA runs before this script.
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
    if ('com.painless.pc' not in text
            and r'com\.painless\.pc' not in text
            and r'com\\.painless\\.pc' not in text):
        print(f'{name}: no legacy runtime package tokens')
        continue

    # Runtime package/authority/resource-id/process identity follows applicationId.
    text = text.replace('com.painless.pc', 'com.ramybaheeg.togglebay')

    # Regex assertions carry escaped package dots and therefore are not covered by
    # the plain string replacement above. Normalize both one- and two-backslash
    # source spellings so package/resource-id/process assertions observe ToggleBay.
    text = text.replace(r'com\\.painless\\.pc', r'com\\.ramybaheeg\\.togglebay')
    text = text.replace(r'com\.painless\.pc', r'com\.ramybaheeg\.togglebay')

    # Component classes intentionally remain in the restored Java namespace.
    # Cover both literal package components and the shell-variable shorthand used by
    # the publication probes.  A component like "$PKG/.tracker.Probe" is wrong once
    # applicationId differs from the Java namespace: Android expands it to
    # com.ramybaheeg.togglebay.tracker.Probe, which does not exist.  Keep the
    # installed package on the left of '/' and the restored Java class on the right.
    text = text.replace(
        'com.ramybaheeg.togglebay/.',
        'com.ramybaheeg.togglebay/com.painless.pc.')
    text = text.replace(
        'com.ramybaheeg.togglebay/com.ramybaheeg.togglebay.',
        'com.ramybaheeg.togglebay/com.painless.pc.')
    for package_var in ('$PKG', '${PKG}', '$PACKAGE', '${PACKAGE}', '$APP_PACKAGE', '${APP_PACKAGE}'):
        text = text.replace(
            package_var + '/.',
            package_var + '/com.painless.pc.')

    # Runtime scripts also contain source-tree assertions. The source namespace is
    # deliberately unchanged, so restore path/package assertions after translating
    # Android runtime identity.
    text = text.replace('src/com/ramybaheeg/togglebay', 'src/com/painless/pc')
    text = text.replace('qa-debug/src/com/ramybaheeg/togglebay', 'qa-debug/src/com/painless/pc')
    text = text.replace('package com.ramybaheeg.togglebay', 'package com.painless.pc')
    text = text.replace('import com.ramybaheeg.togglebay', 'import com.painless.pc')

    # The folder-share QA script generates a completely separate external consumer
    # application inside a heredoc. It intentionally follows the translated public
    # package and must NOT be restored to the app's historical source namespace.
    text = text.replace(
        'package com.painless.pc.qaconsumer;',
        'package com.ramybaheeg.togglebay.qaconsumer;')

    # Fail closed if the main-app package still uses relative component shorthand.
    # That form is only valid when applicationId and Java namespace are identical.
    bad = [
        'com.ramybaheeg.togglebay/.',
        '$PKG/.', '${PKG}/.',
        '$PACKAGE/.', '${PACKAGE}/.',
        '$APP_PACKAGE/.', '${APP_PACKAGE}/.',
    ]
    leftovers = [token for token in bad if token in text]
    if leftovers:
        raise SystemExit(f'{name}: unresolved ToggleBay component shorthand: {leftovers}')

    p.write_text(text)
    print(f'{name}: ToggleBay runtime identity normalized')

print('ToggleBay runtime identity preparation: PASS')
PY
