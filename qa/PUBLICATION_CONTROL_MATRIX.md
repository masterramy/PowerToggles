# Independent Publication Control Matrix

Authority branch: `publication-readiness`
Historical certified base: `08bcdb9a418b95b55ea3fd92e3d10c309167005e`
Scope: all 48 stable historical tracker IDs in `TrackerManager.TRACKER_LIST`, plus publication exposure/disposition requirements.

This matrix is a publication-readiness working authority. A row marked **PROVISIONAL** is not a shipping PASS; runtime/rendered/device evidence must close it. Stable tracker IDs are preserved for legacy persisted definitions even when a tracker is retired from new-user picker exposure.

Legend:
- F0: directly preserved on supported current Android.
- F1: preserved with legitimate user-granted runtime/special access.
- F2: truthful user-mediated system panel/settings/consent replacement.
- F3: retired from new shipping UI; historical ID retained only for legacy compatibility unless separately migrated.

| ID | Historical label | Class | Publication disposition | New-picker exposure target | Required closure evidence |
|---:|---|---|---|---|---|
| 0 | Hotspot (Wifi) | HotSpotTracker | **F2 PROVISIONAL** | Keep only after direct modern settings-route repair | Tap opens correct tether/hotspot system surface; cancel/back; no hidden/root mutation attempted |
| 1 | GPRS (Mobile Data) | GprsStateTracker | **F2 PROVISIONAL** | Keep only after modern settings-route repair | Tap opens current mobile-data settings; dual-SIM/no-SIM states; cancel/back; no hidden telephony/root mutation |
| 2 | Data Sync | SyncStateTracker | **F1 PROVISIONAL** | Keep pending API/runtime proof | Read/write master sync succeeds only with legitimate declared access; denial/error; persistence |
| 3 | Wifi | WifiStateTracker | **F2 EVIDENCED AT GATE2A; REVALIDATE FINAL** | Keep | Android Wi-Fi panel rendered from exact final bytes; back/cancel; state refresh |
| 4 | Flash Light | FlashStateTracker | **F0 PROVISIONAL** | Keep pending runtime/device proof | Torch on/off, no-camera/no-flash, background/service lifecycle, Fold/slab hardware |
| 5 | GPS | GpsStateTracker | **F2 PROVISIONAL** | Keep only after direct location-settings repair | Tap opens Location settings; no secure-setting/root mutation; back/cancel; state truthfulness |
| 6 | Bluetooth | BluetoothTracker | **F2 EVIDENCED AT GATE2A; REVALIDATE FINAL** | Keep | User-mediated enable/settings path; deny/cancel/back; Nearby Devices permission behavior; rendered system UI |
| 7 | Brightness | BacklightTracker | **F1 PROVISIONAL** | Keep | WRITE_SETTINGS grant/deny/revoke; all configured levels; auto/manual transition; persistence |
| 8 | Airplane Mode | AirplaneTracker | **F2 PROVISIONAL** | Keep only after settings-only repair | Tap opens Airplane-mode settings; no root/global write attempt; back/cancel; truthful state |
| 9 | Screen Auto Rotate | AutoRotateTracker | **F1 EVIDENCED AT GATE2A; REVALIDATE FINAL** | Keep | WRITE_SETTINGS grant/deny/revoke; write + exact restore; rendered permission path |
| 10 | Volume Toggle | VolumeTracker | **F0/F1 PROVISIONAL** | Keep pending DND/audio-policy proof | All enabled modes; DND/policy restrictions; vibrate availability; persistence |
| 11 | Data Network Toggle | DataNetworkTracker | **F2 PROVISIONAL** | Keep | Opens current data settings; state label on Wi-Fi/no-cell/dual-SIM; back/cancel |
| 12 | USB Tether | UsbTetherTracker | **F2 PROVISIONAL** | Keep only after settings-only repair | Opens current tether settings; connected/disconnected USB; no MANAGE_USB/root path |
| 13 | Screen Always On (WakeLock) | ScreenOnTracker | **F0 PROVISIONAL** | Keep pending service proof | Enable/disable, foreground/background lifecycle, reboot/restart cleanup, notification requirements |
| 14 | WiMax (4G) | WiMaxTracker | **F3 EVIDENCED AT GATE2A** | **Retired / absent** | Absent from picker/search on exact final bytes; legacy persisted definition handled safely |
| 15 | Battery Info | BatteryTracker | **F0 EVIDENCED AT GATE2A; REVALIDATE FINAL** | Keep | Percent/status render, thresholds/colors, tap battery screen, low/high edge values |
| 16 | Screen Timeout | TimeoutTracker | **F1 PROVISIONAL** | Keep | WRITE_SETTINGS grant/deny/revoke; every configured interval; persistence; toast accuracy |
| 17 | Auto Brightness | AutoBacklightTracker | **F1 PROVISIONAL** | Keep | WRITE_SETTINGS grant/deny/revoke; toggle auto/manual; unsupported sensor/device behavior |
| 18 | Play/Pause Music | MediaPlayPause | **F0 PROVISIONAL** | Keep pending modern media proof | Real media app receives play/pause; no-player state; lock/background state |
| 19 | Next Track | MediaNext | **F0 PROVISIONAL** | Keep pending modern media proof | Real media app receives next; no-player state; selected-player option |
| 20 | Previous Track | MediaPrev | **F0 PROVISIONAL** | Keep pending modern media proof | Real media app receives previous; no-player state; selected-player option |
| 21 | Music volume | MediaVolume | **F0 PROVISIONAL** | Keep | Mute/restore exact prior volume; max/zero edge; persistence after process restart |
| 22 | Bluetooth Discovery | BluetoothDiscoveryTracker | **F1 PROVISIONAL** | Keep | User discoverability consent shown; accept/deny/cancel; Nearby Devices permission; timeout/state refresh |
| 23 | Brightness Slider | BrightnessSliderToggle | **F1 PROVISIONAL** | Keep | WRITE_SETTINGS grant/deny/revoke; slider extremes; cancel/back; visual panel QA |
| 24 | NFC | NfcStateTracker | **F2 PROVISIONAL** | Keep only after settings-only repair | NFC-capable and no-NFC device; tap opens correct settings; no root/privileged mutation |
| 25 | Screen Lock | LockScreenToggle | **F1 PROVISIONAL** | Keep | Device Admin request/deny/grant/revoke; lockNow; uninstall/deactivation guidance; Fold/slab proof |
| 26 | Bluetooth Tether | BluetoothHotspotTracker | **F2 PROVISIONAL** | Keep only if truthful public settings route is reliable; otherwise F3 | Bluetooth-off/on states; settings route; no hidden PAN reflection/direct enable-disable |
| 27 | Volume Slider | VolumeSliderToggle | **F0 PROVISIONAL** | Keep | All exposed streams; DND restrictions; min/max; panel back/cancel |
| 28 | Sync Now | SyncNowTracker | **F1 PROVISIONAL** | Keep only after account-visibility/sync proof | No-account/one/multi-account; disabled provider; request result/error; permissions/privacy review |
| 29 | Shutdown | ShutdownCommand | **F3** | **Retire from new picker** | Absent from picker/search; no REBOOT/root workflow reachable from new config |
| 30 | Restart | RestartCommand | **F3** | **Retire from new picker** | Absent from picker/search; no REBOOT/root workflow reachable from new config |
| 31 | Screen Light | ScreenLightCommand | **F0 PROVISIONAL** | Keep | Open/close panel; brightness/color controls; orientation; back/cancel |
| 32 | Notification Widget | NotifyWidgetTracker | **F1 PROVISIONAL** | Keep | POST_NOTIFICATIONS allow/deny/revoke; enable/shade/actions/disable; restart persistence |
| 33 | Widget Settings | WidgetSettingCommand | **F0 PROVISIONAL** | Keep | Correct widget settings target from configured widget; invalid/removed widget behavior |
| 34 | Second Notification Row | TwoRowTracker | **F1 PROVISIONAL** | Keep | Notification enabled/disabled; row enable/disable; shade rendering; persistence |
| 35 | Shutdown Menu | ShutdownMenuCommand | **F3** | **Retire from new picker** | Absent; power/recovery/bootloader root dialog not reachable from new config |
| 36 | Increase System Font | FontIncreaseTracker | **F3** | **Retire from new picker** | Absent; no CHANGE_CONFIGURATION/root mutation offered |
| 37 | Decrease System Font | FontDecreaseTracker | **F3** | **Retire from new picker** | Absent; no CHANGE_CONFIGURATION/root mutation offered |
| 38 | Rotation Lock | RotationLockTracker | **F1 PROVISIONAL** | Keep pending modern overlay/settings proof | Prompt/no-prompt modes; portrait/landscape; grant/deny if needed; process/service cleanup; Fold states |
| 39 | adbWireless | AdbWirelessTracker | **F3** | **Retire from new picker** | Absent; no root setprop/adbd control reachable |
| 40 | Pulse notification light | PulseLightTracker | **F1-or-F3 PROVISIONAL** | Keep only until hardware/API proof resolves it | LED-capable/no-LED devices; WRITE_SETTINGS behavior; notification settings fallback; truthful label |
| 41 | Receive internet calls (SIP) | SipReceiveTracker | **F3** | **Retire from new picker** | Absent; Android platform SIP is deprecated/no longer supported for future VOIP basis |
| 42 | Internet calling (SIP) | SipCallTracker | **F3** | **Retire from new picker** | Absent; obsolete platform SIP system setting not offered |
| 43 | Home Shortcut | HomeCommand | **F0 PROVISIONAL** | Keep | Returns to home from widget/notification/folder; background/cold app states |
| 44 | Recent Apps | RecentAppsCommand | **F3** | **Retire from new picker** | Absent; hidden IStatusBarService action not reachable |
| 45 | No Lock Screen | NoLockTracker | **F3** | **Retire from new picker** | Absent; deprecated KeyguardLock disable flow not offered as modern security control |
| 46 | Wifi Optimize | WifiOptimizeTracker | **F3** | **Retire from new picker** | Absent; secure/global/root optimization mutation not offered |
| 47 | Immersive mode | ImmersiveTracker | **F3** | **Retire from new picker** | Absent; deprecated global TYPE_TOAST/system-UI service not reachable |

## Immediate publication-safety consequences

The current Gate2A picker still exposes every historical ID except WiMAX. Before publication, the following clearly unsupported/obsolete IDs must be removed from *new-user picker exposure* while preserving stable IDs for legacy definitions: **29, 30, 35, 36, 37, 39, 41, 42, 44, 45, 46, 47**. WiMAX **14** remains retired.

The following IDs require explicit modern-route repair before they can be certified: **0, 1, 5, 8, 12, 24, 26**. They currently contain hidden/system/root-era mutation attempts or reflection and must not rely on those attempts in the independent Play-targeted product.

The following controls remain deliberately unresolved rather than falsely green: **2, 4, 10, 13, 18–20, 22, 25, 28, 38, 40**. Publication closure requires exact runtime/device evidence described above.

No row becomes final merely because this matrix classifies it. Final status requires the exact candidate bytes, per-control exercise, rendered evidence for distinct visible outcomes, and applicable physical-device proof under Head Notice 22.