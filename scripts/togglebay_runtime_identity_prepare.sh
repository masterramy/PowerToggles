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

# The folder-share probe intentionally compiles a separate cross-UID consumer app.
# Its identity must remain independent from the app under test; otherwise a global
# package rewrite can make the manifest/component name disagree with the generated
# Java class and turn the permission probe into a false RED.
QA_CONSUMER = 'com.painless.pc.qaconsumer'
QA_CONSUMER_SENTINEL = '__TOGGLEBAY_QA_CONSUMER_PACKAGE__'
QA_CONSUMER_ESCAPED = r'com\.painless\.pc\.qaconsumer'
QA_CONSUMER_ESCAPED_SENTINEL = '__TOGGLEBAY_QA_CONSUMER_ESCAPED_PACKAGE__'

for name in runtime_scripts:
    p = Path(name)
    text = p.read_text()
    if 'com.painless.pc' not in text and r'com\.painless\.pc' not in text:
        print(f'{name}: no legacy runtime package tokens')
        continue

    # Preserve deliberately independent QA helper identity before translating the
    # applicationId.  Restore it after all app-identity substitutions below.
    text = text.replace(QA_CONSUMER_ESCAPED, QA_CONSUMER_ESCAPED_SENTINEL)
    text = text.replace(QA_CONSUMER, QA_CONSUMER_SENTINEL)

    # Runtime package/authority/resource-id/process identity follows applicationId.
    # Translate both ordinary literals and regex-escaped literals used against
    # dumpsys/logcat.  Plain string replacement does not match the escaped form.
    text = text.replace(r'com\.painless\.pc', r'com\.ramybaheeg\.togglebay')
    text = text.replace('com.painless.pc', 'com.ramybaheeg.togglebay')

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

    # Restore the deliberately separate cross-UID helper after the broad source-
    # namespace restoration above so its Gradle id, component target, and Java
    # package remain mutually consistent.
    text = text.replace(QA_CONSUMER_ESCAPED_SENTINEL, QA_CONSUMER_ESCAPED)
    text = text.replace(QA_CONSUMER_SENTINEL, QA_CONSUMER)

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

    # Fail closed on regex-escaped legacy runtime identity. The only allowed escaped
    # legacy package here is the intentionally independent qaconsumer helper.
    escaped_legacy = r'com\.painless\.pc'
    escaped_consumer = r'com\.painless\.pc\.qaconsumer'
    scrubbed = text.replace(escaped_consumer, '')
    if escaped_legacy in scrubbed:
        raise SystemExit(f'{name}: unresolved regex-escaped legacy runtime package')

    p.write_text(text)
    print(f'{name}: ToggleBay runtime identity normalized')

print('ToggleBay runtime identity preparation: PASS')
PY
