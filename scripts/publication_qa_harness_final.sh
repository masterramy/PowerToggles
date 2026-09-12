#!/usr/bin/env bash
set -euo pipefail

# Final QA-only normalization for defects independently observed in the
# d0b34a74 hosted evidence. Shipping source is intentionally untouched.
python3 - <<'PY'
from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    old_count = text.count(old)
    new_count = text.count(new)
    if old_count == 1:
        p.write_text(text.replace(old, new, 1))
        print(f'{path}: {label}')
        return
    if old_count == 0 and new_count >= 1:
        print(f'{path}: {label} already normalized')
        return
    raise SystemExit(f'{path}: expected one {label} anchor; old={old_count} new={new_count}')

# 1) publication_runtime_qa.sh still used synthetic widget IDs for its
# publication-specific label and exhaustive picker audits. Shipping correctly
# rejects unbound IDs. Allocate one genuine framework-bound widget, reuse it for
# both audits, then delete it and revoke temporary bind authority.
first_old = r'''adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1004 \
  > runtime-evidence/state/publication-label-audit-start.txt 2>&1
sleep 2
adb shell input tap 850 312
sleep 2
'''
first_new = r'''PUBLICATION_WIDGET_USER="$(adb shell am get-current-user | tr -d '\r')"
case "$PUBLICATION_WIDGET_USER" in
  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $PUBLICATION_WIDGET_USER" >&2; exit 1 ;;
esac
adb shell appwidget grantbind --package com.painless.pc --user "$PUBLICATION_WIDGET_USER" \
  > runtime-evidence/state/publication-widget-grantbind.txt
adb shell am force-stop com.painless.pc
adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
  --es probe allocate_bind > runtime-evidence/state/publication-widget-allocate-bind.txt
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/publication_widget_host_probe.xml \
  > runtime-evidence/state/publication-widget-probe-prefs.xml
PUBLICATION_WIDGET_ID="$(python3 -c 'import sys,xml.etree.ElementTree as ET; r=ET.parse(sys.argv[1]).getroot(); print(next(n.attrib["value"] for n in r if n.attrib.get("name")=="widget_id"))' runtime-evidence/state/publication-widget-probe-prefs.xml)"
test "$PUBLICATION_WIDGET_ID" -gt 0
grep -Eq 'name="bound" value="true"|value="true" name="bound"' runtime-evidence/state/publication-widget-probe-prefs.xml
grep -Eq 'name="provider_info_present" value="true"|value="true" name="provider_info_present"' runtime-evidence/state/publication-widget-probe-prefs.xml
publication_widget_cleanup() {
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
    --es probe delete --ei widget_id "$PUBLICATION_WIDGET_ID" \
    > runtime-evidence/state/publication-widget-delete.txt 2>&1 || true
  adb shell appwidget revokebind --package com.painless.pc --user "$PUBLICATION_WIDGET_USER" >/dev/null 2>&1 || true
}
trap publication_widget_cleanup EXIT

adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$PUBLICATION_WIDGET_ID" \
  > runtime-evidence/state/publication-label-audit-start.txt 2>&1
sleep 2
adb shell input tap 850 312
sleep 2
'''
replace_once('scripts/publication_runtime_qa.sh', first_old, first_new,
             'publication label audit moved to genuine bound widget')

second_old = r'''adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1005 \
  > runtime-evidence/state/publication-picker-inventory-start.txt 2>&1
'''
second_new = r'''adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$PUBLICATION_WIDGET_ID" \
  > runtime-evidence/state/publication-picker-inventory-start.txt 2>&1
'''
replace_once('scripts/publication_runtime_qa.sh', second_old, second_new,
             'publication picker inventory moved to genuine bound widget')

end_old = r'''find runtime-evidence/screens -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > runtime-evidence/screenshot-index.txt
echo "Publication rendered label audit: PASS" > runtime-evidence/state/publication-label-audit-summary.txt
echo "Publication picker exposure audit: PASS" > runtime-evidence/state/publication-picker-inventory-summary.txt
'''
end_new = r'''publication_widget_cleanup
trap - EXIT
find runtime-evidence/screens -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > runtime-evidence/screenshot-index.txt
echo "Publication rendered label audit: PASS" > runtime-evidence/state/publication-label-audit-summary.txt
echo "Publication picker exposure audit: PASS" > runtime-evidence/state/publication-picker-inventory-summary.txt
'''
replace_once('scripts/publication_runtime_qa.sh', end_old, end_new,
             'publication genuine widget cleanup')

# 2) The Android 11+ manifest visibility fix correctly changes the compact share
# submenu. In d0b34a74 evidence the outer "Choose an app" accessibility node's
# center landed on Gmail; the actual affordance that opens the complete target
# chooser is the rendered "See all" row. Open that row before selecting the QA
# receiver so the owner-originated URI grant is proven against the real target.
folder = Path('scripts/publication_folder_backup_share_qa.sh')
text = folder.read_text()
old_comment = '# otherwise open the full chooser through its rendered "Choose an app" affordance.'
new_comment = '# otherwise open the full chooser through its rendered "See all" affordance.'
if old_comment in text:
    text = text.replace(old_comment, new_comment, 1)
elif new_comment not in text:
    raise SystemExit('folder share full-chooser comment anchor missing')

pairs = [
    ('"02-share-choose-app-wait" "Choose an app" 5', '"02-share-see-all-wait" "See all" 5'),
    ('"02-share-choose-app-source" "Choose an app"', '"02-share-see-all-source" "See all"'),
]
for old, new in pairs:
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit(f'folder share chooser anchor missing: {old}')
folder.write_text(text)
print('scripts/publication_folder_backup_share_qa.sh: full chooser now uses rendered See all affordance')

print('Publication QA harness final normalization: PASS')
PY

echo "Publication QA harness final normalization: PASS"
