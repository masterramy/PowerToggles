#!/usr/bin/env bash
set -euo pipefail
# Diagnostic patch recipe only; final source bytes are committed directly before freeze.
sed -i 's/private static final String AUTHORITY = "com.painless.pc.file";/private static final String AUTHORITY = BuildConfig.APPLICATION_ID + ".file";/' src/com/painless/pc/FileProvider.java
sed -i 's/private static final String PLUGIN_STATE_CHANGED_INTENT = "com.painless.pc.ACTION_STATE_CHANGED";/private static final String PLUGIN_STATE_CHANGED_INTENT = BuildConfig.APPLICATION_ID + ".ACTION_STATE_CHANGED";/' src/com/painless/pc/PluginUpdateReceiver.java
