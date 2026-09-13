#!/usr/bin/env bash
set -euo pipefail

# QA-only runtime translation for the final public package. Shipping Java remains in
# the restored com.painless.pc namespace while Android installs the app as
# com.ramybaheeg.togglebay. Static source QA runs before this script.
python3 - <<'PY'
from pathlib import Path
import re

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

    # PreferenceActivity fragment extras contain Java class names rather than Android
    # package/component identities. Keep those extras in the retained source namespace.
    text = text.replace(
        "--es ':android:show_fragment' com.ramybaheeg.togglebay.",
        "--es ':android:show_fragment' com.painless.pc.")

    # Runtime scripts also contain source-tree assertions and generated Java source.
    # The Java/source namespace is deliberately unchanged. Restore only actual Java
    # package declarations (line-start anchored), never arbitrary shell text such as
    # `--package com.ramybaheeg.togglebay` or `dumpsys package ...`: those commands
    # must continue to address the installed public applicationId.
    text = text.replace('src/com/ramybaheeg/togglebay', 'src/com/painless/pc')
    text = text.replace('qa-debug/src/com/ramybaheeg/togglebay', 'qa-debug/src/com/painless/pc')
    text = re.sub(r'(?m)^package com\.ramybaheeg\.togglebay', 'package com.painless.pc', text)
    text = text.replace("'package com.ramybaheeg.togglebay", "'package com.painless.pc")
    text = text.replace('import com.ramybaheeg.togglebay', 'import com.painless.pc')

    # The Android 13+ permission controller renders the final public app label.
    # Keep the customer-visible notification-permission assertion bound to ToggleBay.
    text = text.replace(
        'Allow Power Toggles to send you notifications?',
        'Allow ToggleBay to send you notifications?')

    # The public identity migration intentionally renamed customer-visible backup
    # filenames. Keep the rendered SAF assertions and all round-trip fixture paths
    # bound to the exact shipping names rather than the historical product name.
    if name == 'scripts/publication_import_export_qa.sh':
        text = text.replace('power-toggles-backup.zip', 'togglebay-backup.zip')
    if name == 'scripts/publication_folder_backup_share_qa.sh':
        text = text.replace('power-toggles-folders.pcf', 'togglebay-folders.pcf')

    # The folder-share QA script generates a completely separate external consumer
    # application inside a heredoc. It intentionally follows the translated public
    # package and must NOT be restored to the app's historical source namespace.
    text = text.replace(
        'package com.painless.pc.qaconsumer;',
        'package com.ramybaheeg.togglebay.qaconsumer;')

    # The inherited Gate 2A runtime probe used synthetic AppWidget IDs for its
    # configurator/picker interaction slice. Shipping code now correctly rejects
    # unowned synthetic IDs. Replace those two QA-only IDs with one genuinely
    # framework-allocated/bound widget, then delete it at the end of the slice.
    if name == 'scripts/gate2a_runtime_qa.sh':
        widget_anchor = '''# Widget configurator and picker evidence.\nadb shell am force-stop com.ramybaheeg.togglebay\n'''
        widget_setup = '''# Widget configurator and picker evidence.\nGATE2A_USER_ID="$(adb shell am get-current-user | tr -d '\\r')"\ncase "$GATE2A_USER_ID" in\n  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $GATE2A_USER_ID" >&2; exit 1 ;;\nesac\nadb shell appwidget grantbind --package com.ramybaheeg.togglebay --user "$GATE2A_USER_ID" > "$OUT/state/gate2a-widget-grantbind.txt"\nadb shell am force-stop com.ramybaheeg.togglebay\nadb shell am start -W -n com.ramybaheeg.togglebay/com.painless.pc.tracker.PublicationWidgetHostProbeActivity \\\n  --es probe allocate_bind > "$OUT/state/gate2a-widget-allocate-bind.txt"\nsleep 1\nadb shell run-as com.ramybaheeg.togglebay cat shared_prefs/publication_widget_host_probe.xml > "$OUT/state/gate2a-widget-probe-prefs.xml"\nGATE2A_WIDGET_ID="$(python3 -c 'import sys,xml.etree.ElementTree as ET; r=ET.parse(sys.argv[1]).getroot(); print(next(n.attrib["value"] for n in r if n.attrib.get("name")=="widget_id"))' "$OUT/state/gate2a-widget-probe-prefs.xml")"\ntest "$GATE2A_WIDGET_ID" -gt 0\ngrep -Eq 'name="bound" value="true"|value="true" name="bound"' "$OUT/state/gate2a-widget-probe-prefs.xml"\ngrep -Eq 'name="provider_info_present" value="true"|value="true" name="provider_info_present"' "$OUT/state/gate2a-widget-probe-prefs.xml"\nadb shell am force-stop com.ramybaheeg.togglebay\n'''
        if widget_anchor not in text:
            raise SystemExit(f'{name}: widget configurator anchor missing')
        text = text.replace(widget_anchor, widget_setup, 1)
        text = text.replace('--ei appWidgetId 1002', '--ei appWidgetId "$GATE2A_WIDGET_ID"', 1)
        text = text.replace('--ei appWidgetId 1003', '--ei appWidgetId "$GATE2A_WIDGET_ID"', 1)
        cleanup_anchor = '# Final package/install facts and permission state.\n'
        cleanup = '''adb shell am force-stop com.ramybaheeg.togglebay >/dev/null 2>&1 || true\nadb shell am start -W -n com.ramybaheeg.togglebay/com.painless.pc.tracker.PublicationWidgetHostProbeActivity \\\n  --es probe delete --ei widget_id "$GATE2A_WIDGET_ID" > "$OUT/state/gate2a-widget-delete.txt"\nadb shell appwidget revokebind --package com.ramybaheeg.togglebay --user "$GATE2A_USER_ID" >/dev/null 2>&1 || true\n\n# Final package/install facts and permission state.\n'''
        if cleanup_anchor not in text:
            raise SystemExit(f'{name}: widget cleanup anchor missing')
        text = text.replace(cleanup_anchor, cleanup, 1)

    # Fail closed if the main-app package still uses relative component shorthand or
    # if a shell package-option was accidentally restored to the historical package.
    bad = [
        'com.ramybaheeg.togglebay/.',
        '$PKG/.', '${PKG}/.',
        '$PACKAGE/.', '${PACKAGE}/.',
        '$APP_PACKAGE/.', '${APP_PACKAGE}/.',
        '--package com.painless.pc',
        "--es ':android:show_fragment' com.ramybaheeg.togglebay.",
    ]
    leftovers = [token for token in bad if token in text]
    if leftovers:
        raise SystemExit(f'{name}: unresolved ToggleBay runtime identity: {leftovers}')

    p.write_text(text)
    print(f'{name}: ToggleBay runtime identity normalized')

print('ToggleBay runtime identity preparation: PASS')
PY
