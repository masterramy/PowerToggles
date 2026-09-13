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

    # Publication-only rendered picker audits must also use a framework-owned
    # AppWidget ID. Shipping correctly rejects synthetic IDs such as 1004/1005.
    if name == 'scripts/publication_runtime_qa.sh':
        audit_anchor = '# Flashlight is farther down the categorized picker.'
        audit_setup = '''PUBLICATION_USER_ID="$(adb shell am get-current-user | tr -d '\\r')"
case "$PUBLICATION_USER_ID" in
  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $PUBLICATION_USER_ID" >&2; exit 1 ;;
esac
adb shell appwidget grantbind --package com.ramybaheeg.togglebay --user "$PUBLICATION_USER_ID" > runtime-evidence/state/publication-widget-grantbind.txt
adb shell am force-stop com.ramybaheeg.togglebay
adb shell am start -W -n com.ramybaheeg.togglebay/com.painless.pc.tracker.PublicationWidgetHostProbeActivity \
  --es probe allocate_bind > runtime-evidence/state/publication-widget-allocate-bind.txt
sleep 1
adb shell run-as com.ramybaheeg.togglebay cat shared_prefs/publication_widget_host_probe.xml > runtime-evidence/state/publication-widget-probe-prefs.xml
PUBLICATION_AUDIT_WIDGET_ID="$(python3 -c 'import sys,xml.etree.ElementTree as ET; r=ET.parse(sys.argv[1]).getroot(); print(next(n.attrib["value"] for n in r if n.attrib.get("name")=="widget_id"))' runtime-evidence/state/publication-widget-probe-prefs.xml)"
test "$PUBLICATION_AUDIT_WIDGET_ID" -gt 0
grep -Eq 'name="bound" value="true"|value="true" name="bound"' runtime-evidence/state/publication-widget-probe-prefs.xml
grep -Eq 'name="provider_info_present" value="true"|value="true" name="provider_info_present"' runtime-evidence/state/publication-widget-probe-prefs.xml

'''
        if audit_anchor not in text:
            raise SystemExit(f'{name}: publication picker audit anchor missing')
        text = text.replace(audit_anchor, audit_setup + audit_anchor, 1)
        text = text.replace('--ei appWidgetId 1004', '--ei appWidgetId "$PUBLICATION_AUDIT_WIDGET_ID"', 1)
        text = text.replace('--ei appWidgetId 1005', '--ei appWidgetId "$PUBLICATION_AUDIT_WIDGET_ID"', 1)
        inventory_end = "find runtime-evidence/screens -maxdepth 1 -type f -name '*.png'"
        audit_cleanup = '''adb shell am force-stop com.ramybaheeg.togglebay >/dev/null 2>&1 || true
adb shell am start -W -n com.ramybaheeg.togglebay/com.painless.pc.tracker.PublicationWidgetHostProbeActivity \
  --es probe delete --ei widget_id "$PUBLICATION_AUDIT_WIDGET_ID" > runtime-evidence/state/publication-widget-delete.txt
adb shell appwidget revokebind --package com.ramybaheeg.togglebay --user "$PUBLICATION_USER_ID" >/dev/null 2>&1 || true

'''
        if inventory_end not in text:
            raise SystemExit(f'{name}: publication picker cleanup anchor missing')
        text = text.replace(inventory_end, audit_cleanup + inventory_end, 1)

    # Import/export tracker-33 reopens an already-configured widget and therefore
    # legitimately lands in EditWidgetConfigActivity. Accept that exact shipping
    # activity on every reopen, including the final process-persistence proof.
    if name == 'scripts/publication_import_export_qa.sh':
        text = text.replace(
            "grep -q 'com.ramybaheeg.togglebay/com.painless.pc.cfg.WidgetConfigActivity'",
            "grep -Eq 'com\\.ramybaheeg\\.togglebay/com\\.painless\\.pc\\.cfg\\.EditWidgetConfigActivity'")

    # Android's compact sharesheet can hide a newly installed QA target behind
    # "See all". Expand it through the rendered customer chooser before selecting
    # the external consumer so the URI grant originates from ToggleBay itself.
    # publication_qa_harness_prepare.sh runs before this translator and may already
    # have replaced the original chooser block with its deterministic system-target
    # proof. Support both shapes and fail closed on any third/unexpected shape.
    if name == 'scripts/publication_folder_backup_share_qa.sh':
        share_anchor = '''adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
if ! adb shell run-as "$CONSUMER_PKG" test -s files/result.txt >/dev/null 2>&1; then
  if wait_for_node "02-share-target-wait" "QA Folder Share Consumer" 8; then
    capture "02-share-target-list"
    tap_node "02-share-target-source" "QA Folder Share Consumer"
    sleep 2
  fi
fi
'''
        share_replacement = '''adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
if ! adb shell run-as "$CONSUMER_PKG" test -s files/result.txt >/dev/null 2>&1; then
  if ! wait_for_node "02-share-target-wait" "QA Folder Share Consumer" 3; then
    if wait_for_node "02-share-see-all-wait" "See all" 3; then
      tap_node "02-share-see-all-source" "See all"
      sleep 2
    fi
  fi
  if wait_for_node "02-share-target-wait-expanded" "QA Folder Share Consumer" 8; then
    capture "02-share-target-list"
    tap_node "02-share-target-source" "QA Folder Share Consumer"
    sleep 2
  fi
fi
'''
        prepared_positive_anchor = '''# `am` only propagates a URI grant for data/ClipData, not merely EXTRA_STREAM.
# Shipping ACTION_SEND uses ClipData; attach the same URI as data here so the
# controlled external consumer receives a real Android URI permission grant.
adb shell am start -W -a android.intent.action.SEND -t application/zip \\
  -d "$SHARE_URI" -f 0x1 -n "$CONSUMER_PKG/.ShareReceiverActivity" \\
  --eu android.intent.extra.STREAM "$SHARE_URI" > "$OUT/state/share-positive-start.txt" 2>&1
sleep 1
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\\.ramybaheeg\\.togglebay\\.file/folder-share$' "$OUT/state/share-positive-result.txt"
'''
        prepared_positive_replacement = '''# Prove the positive grant through ToggleBay's rendered customer chooser. The
# preceding deterministic system-target proof returns with BACK; tolerate one
# additional nested system surface before requiring the Folder action mode again.
if ! wait_for_node "02-share-return-wait" "Share" 3; then
  adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep 1
fi
if ! wait_for_node "02-share-return-wait-retry" "Share" 5; then
  echo "Folder Share action did not return after system-target archive proof" >&2
  exit 1
fi
adb logcat -c
tap_node "02-share-consumer-source" "Share"
sleep 2
if ! wait_for_node "02-share-consumer-wait" "QA Folder Share Consumer" 3; then
  if wait_for_node "02-share-see-all-wait" "See all" 3; then
    tap_node "02-share-see-all-source" "See all"
    sleep 2
  else
    echo "QA Folder Share Consumer and See all were both absent from the rendered chooser" >&2
    exit 1
  fi
fi
if ! wait_for_node "02-share-consumer-expanded-wait" "QA Folder Share Consumer" 8; then
  echo "QA Folder Share Consumer did not render after chooser expansion" >&2
  exit 1
fi
capture "02-share-consumer-target-list"
tap_node "02-share-consumer-target-source" "QA Folder Share Consumer"
for attempt in $(seq 1 10); do
  adb shell run-as "$CONSUMER_PKG" test -s files/result.txt >/dev/null 2>&1 && break
  sleep 1
done
adb shell run-as "$CONSUMER_PKG" test -s files/result.txt
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\\.ramybaheeg\\.togglebay\\.file/folder-share$' "$OUT/state/share-positive-result.txt"
'''
        if prepared_positive_anchor in text:
            text = text.replace(prepared_positive_anchor, prepared_positive_replacement, 1)
        elif share_anchor in text:
            text = text.replace(share_anchor, share_replacement, 1)
        elif '02-share-consumer-expanded-wait' in text:
            print(f'{name}: folder sharesheet already normalized')
        else:
            raise SystemExit(f'{name}: folder sharesheet anchor missing')

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
