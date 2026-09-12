# Independent Publication Control Matrix

Authority branch: `publication-readiness`
Stable historical tracker authority: `TrackerManager.TRACKER_LIST` IDs 0–47.
Current new-picker disposition: **34 KEEP / 14 RETIRE**.
Retired IDs: **14, 29, 30, 35, 36, 37, 39, 40, 41, 42, 44, 45, 46, 47**.

This file is the current publication-readiness control disposition matrix. Stable historical IDs/classes remain preserved for legacy persisted definitions even when a control is retired from new-user picker exposure.

Scope language is deliberate:
- **EMULATOR-CLOSED** / **EMULATOR/RENDERED-CLOSED** means the stated API-36 worker-owned runtime/rendered scope is evidenced; it does not erase explicitly listed physical/OEM/account variants.
- **ROUTE-CLOSED** means the current user-mediated Android Settings/consent route was exercised on API 36 and rendered coherently.
- **PHYSICAL-OPEN** / account/device qualifications remain later gates and are not inferred from emulator success.
- **F3 RETIRED** means absent from new-user picker exposure while the stable historical tracker ID/class remains available for legacy definitions.
- Exact-final customer-facing rendered certification remains a separate G11 gate after final identity/customer bytes exist.

| ID | Current customer label | Class | Current publication status | New-picker disposition | Evidence / remaining boundary |
|---:|---|---|---|---|---|
| 0 | Hotspot (Wi-Fi) | HotSpotTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered public Hotspot & tethering route closed; device/tether-state variants remain physical. |
| 1 | Mobile Data Settings | GprsStateTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Data usage route closed; dual-SIM/no-SIM variants remain device-scoped. |
| 2 | Data Sync | SyncStateTracker | **F1 EMULATOR-CLOSED** | **KEEP** | Real master-sync mutation and exact restoration passed; account/provider variants remain device/account-scoped. |
| 3 | Wi-Fi | WifiStateTracker | **F2 EMULATOR/RENDERED-CLOSED** | **KEEP** | Modern user-mediated Wi-Fi panel path evidenced; exact-final bytes still require G11 rerender. |
| 4 | Flashlight | FlashStateTracker | **F0 PHYSICAL-OPEN** | **KEEP** | API23+ source uses CameraManager torch path and safe no-flash exit; real illumination/hardware variants require physical device. |
| 5 | GPS / Location | GpsStateTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Location settings route closed. |
| 6 | Bluetooth | BluetoothTracker | **F2 EMULATOR/RENDERED-CLOSED** | **KEEP** | Modern user-mediated enable/settings and permission-safe state behavior evidenced; hardware/OEM variants remain physical. |
| 7 | Brightness | BacklightTracker | **F1 EMULATOR-CLOSED** | **KEEP** | WRITE_SETTINGS deny/grant/revoke, real mutation, and exact restore passed. |
| 8 | Airplane Mode | AirplaneTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Network & internet / Airplane mode route closed. |
| 9 | Screen Auto Rotate | AutoRotateTracker | **F1 EMULATOR-CLOSED** | **KEEP** | WRITE_SETTINGS denial plus real accelerometer_rotation mutation and exact restore passed. |
| 10 | Volume Toggle | VolumeTracker | **F1 EMULATOR-CLOSED** | **KEEP** | Notification Policy denied route plus granted real ringer transition and exact restoration passed; OEM/DND variants remain device-scoped. |
| 11 | Mobile Network | DataNetworkTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Mobile network route closed. |
| 12 | USB Tether | UsbTetherTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Hotspot & tethering route closed; connected-USB variants remain physical. |
| 13 | Screen Always On | ScreenOnTracker | **F1 EMULATOR/RENDERED-CLOSED** | **KEEP** | API-36 foreground-service lifecycle and fail-closed visible notification card proof passed; physical/OEM variants remain. |
| 14 | WiMAX (4G) | WiMaxTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; stable historical ID/class retained for legacy definitions. |
| 15 | Battery Info | BatteryTracker | **F0/F2 EMULATOR/RENDERED-CLOSED** | **KEEP** | Exact shipping action landed on Android battery/power Settings with no accepted fatal. |
| 16 | Screen Timeout | TimeoutTracker | **F1 EMULATOR-CLOSED** | **KEEP** | WRITE_SETTINGS deny/grant/revoke, real mutation, and exact restore passed. |
| 17 | Auto Brightness | AutoBacklightTracker | **F1 EMULATOR-CLOSED** | **KEEP** | WRITE_SETTINGS deny/grant/revoke, real mutation, and exact restore passed; sensor/device variants remain physical. |
| 18 | Play/Pause Music | MediaPlayPause | **F0 EMULATOR-CLOSED** | **KEEP** | Active MediaSession delivery, no-player safety, configured-player explicit route, exact DOWN/UP pairing, and preference restoration passed. |
| 19 | Next Track | MediaNext | **F0 EMULATOR-CLOSED** | **KEEP** | Active MediaSession delivery, no-player safety, configured-player explicit route, exact DOWN/UP pairing, and preference restoration passed. |
| 20 | Previous Track | MediaPrev | **F0 EMULATOR-CLOSED** | **KEEP** | Active MediaSession delivery, no-player safety, configured-player explicit route, exact DOWN/UP pairing, and preference restoration passed. |
| 21 | Music Volume | MediaVolume | **F0 EMULATOR-CLOSED** | **KEEP** | Real mute/remembered restore and exact original-volume cleanup passed. |
| 22 | Bluetooth Discovery | BluetoothDiscoveryTracker | **F2 EMULATOR/RENDERED-CLOSED** | **KEEP** | API-36 permission-safe state read and public Bluetooth Settings fallback passed; real Nearby Devices/discoverability hardware variants remain. |
| 23 | Brightness Slider | BrightnessSliderToggle | **F1 EMULATOR/RENDERED-CLOSED** | **KEEP** | Real slider/system-brightness behavior plus WRITE_SETTINGS permission lifecycle and exact restore passed. |
| 24 | NFC | NfcStateTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered NFC Settings route closed; NFC-hardware/no-NFC variants remain physical. |
| 25 | Screen Lock | LockScreenToggle | **F1 EMULATOR/RENDERED-CLOSED** | **KEEP** | Genuine Device Admin consent plus DevicePolicyManager lock path passed; OEM/device variants remain physical. |
| 26 | Bluetooth Tether | BluetoothHotspotTracker | **F2 ROUTE-CLOSED** | **KEEP** | API-36 emulator/rendered Hotspot & tethering route with Bluetooth tethering control passed; live tether-state variants remain physical. |
| 27 | Volume Slider | VolumeSliderToggle | **F0 EMULATOR/RENDERED-CLOSED** | **KEEP** | Real STREAM_MUSIC slider mutation through distinct states and exact original restoration passed. |
| 28 | Sync Now | SyncNowTracker | **F1 EMULATOR-PARTIAL** | **KEEP** | Clean-emulator no-account lifecycle passed; account-populated/sync-adapter variants remain account/device-scoped. |
| 29 | Shutdown | ShutdownCommand | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; root/REBOOT workflow not offered to new configurations. |
| 30 | Restart | RestartCommand | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; root/REBOOT workflow not offered to new configurations. |
| 31 | Screen Light | ScreenLightCommand | **F0 EMULATOR/RENDERED-CLOSED + PHYSICAL-OPEN** | **KEEP** | Color/brightness customer behavior and exact restoration passed; optional torch illumination remains physical-device-only. |
| 32 | Notification Widget | NotifyWidgetTracker | **F1 EMULATOR-CLOSED** | **KEEP** | Two-way notification-widget transition/restoration passed within broader notification runtime coverage. |
| 33 | Widget Settings | WidgetSettingCommand | **F0 EMULATOR/RENDERED-CLOSED** | **KEEP** | Genuine AppWidgetHost allocation/bind/create-save/same-ID tracker-33 reopen/delete/stale/malformed handling passed with no app fatal/ANR. |
| 34 | Second Notification Row | TwoRowTracker | **F1 EMULATOR-CLOSED** | **KEEP** | Two-way row transition and exact restoration passed. |
| 35 | Shutdown Menu | ShutdownMenuCommand | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; root power/recovery menu not offered. |
| 36 | Increase System Font | FontIncreaseTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; privileged/root font mutation not offered. |
| 37 | Decrease System Font | FontDecreaseTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; privileged/root font mutation not offered. |
| 38 | Rotation Lock | RotationLockTracker | **F1 EMULATOR-CLOSED** | **KEEP** | Public WRITE_SETTINGS Auto→Portrait→Landscape→exact restore path passed on repaired bytes; physical/foldable/OEM orientation variants remain. |
| 39 | ADB Wireless | AdbWirelessTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; root setprop/adbd control not offered. |
| 40 | Pulse Notification Light | PulseLightTracker | **F3 RETIRED** | **RETIRE / absent** | Android 16 rejected the private secure-setting mutation; absent from new picker while legacy ID/class remains. |
| 41 | Receive Internet Calls (SIP) | SipReceiveTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; obsolete platform SIP behavior not offered. |
| 42 | Internet Calling (SIP) | SipCallTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; obsolete platform SIP behavior not offered. |
| 43 | Home Shortcut | HomeCommand | **F0 EMULATOR-CLOSED** | **KEEP** | Real command routed foreground to the resolved system launcher. |
| 44 | Recent Apps | RecentAppsCommand | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; hidden status-bar action not offered. |
| 45 | No Lock Screen | NoLockTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; deprecated KeyguardLock-disable behavior not offered. |
| 46 | Wi-Fi Optimize | WifiOptimizeTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; secure/global/root optimization mutation not offered. |
| 47 | Immersive Mode | ImmersiveTracker | **F3 RETIRED** | **RETIRE / absent** | Absent from new picker; deprecated global/system-UI service behavior not offered. |

## Current disposition truth

The exact current `TogglePicker.mWidgetSections` exposes the 34 KEEP IDs above. The 14 retired IDs are absent from new-user picker exposure, and the stable 0–47 `TrackerManager` ordering remains preserved for legacy definitions.

The exhaustive real-picker publication inventory has already been recertified at **34/34 intended survivors observed** and **0/14 retired controls observed**. ID40 Pulse Notification Light is part of the retired set; its Android-16 secure-setting failure is not an unresolved keep/retire question.

IDs18–20 media transport are no longer provisional at emulator scope. The repaired active-session path is proven, the no-player path is non-fatal with exact preference restoration, and the configured explicit-player route is proven through a round-tripped explicit Intent whose QA endpoint was independently validated before the unchanged shipping path delivered exact DOWN/UP pairs with matching `downTime`.

ID33 Widget Settings is no longer provisional at emulator scope. Closure uses a genuine framework AppWidget ID and shipping configuration/receiver route, including create-save, same-ID reopen, deletion, stale numeric handling, malformed-fragment handling, and no app fatal/ANR.

## Gates not collapsed by this matrix

This reconciliation does **not** mark the product final or publicly publishable. The following remain separate:
- G9 independent identity / permanent name-package-icon-signing choice: user decision.
- G11 exact-final customer-visible rendered certification: requires exact final identity/customer bytes.
- G12 physical Fold/slab/OEM/hardware variants, including real flashlight/torch and other device-specific states.
- G13 privacy policy, Play Console/signing/account state, and account-populated variants such as Sync Now.
- Public Publish/go-live: explicit Ramy approval.

A green CI run or a row-level emulator closure does not substitute for those later boundaries.
