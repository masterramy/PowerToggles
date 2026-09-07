# Final Release Boundaries — Power Toggles Publication Branch

Authority branch: `publication-readiness`
Purpose: preserve the exact remaining boundary between the current pre-identity publication candidate and a genuinely final/publishable build. This file is a gate checklist, not permission to make identity/account/publication decisions automatically.

## Already established before the final-identity tranche

- Technical Gate 2A benchmark remains closed and is not to be restarted.
- Android compile/target SDK is 36.
- The publication control disposition is reconciled separately in `qa/PUBLICATION_CONTROL_MATRIX.md`: 34 new-picker survivors / 14 retired historical IDs, while stable tracker IDs 0–47 remain preserved for legacy definitions.
- Worker-owned API-36 emulator/runtime/rendered control scopes are evidence-backed as recorded in the matrix; explicitly listed physical/OEM/account variants remain open.
- `ScreenOnService` is the surviving special-use foreground service and declares its user-initiated screen-awake subtype in the manifest.
- Obsolete Rotation Lock `RLService` source/manifest registration has been removed; Rotation Lock uses the public WRITE_SETTINGS path.
- No public Publish/go-live action is authorized without explicit Ramy approval.

## G9 — identity decision required before permanent release bytes

Current repository values are historical/pre-identity values, not a silent final-identity decision:

- application/package ID: `com.painless.pc`
- Gradle version name: `6.0.4-gate2a`
- manifest version name: `6.0.4`
- app label/icon: current historical Power Toggles resources

Before final customer bytes exist, Ramy must explicitly approve the independent publication identity decisions that affect name/package/icon/developer identity and any intended versioning change. Do not infer these from historical branding or from the technical restoration branch.

## Production signing boundary

`build.gradle` currently has no release `signingConfig`. CI can assemble the release AAB for technical validation, but that is not evidence that a production-upload signing identity/account is configured.

Final release requires the authorized production signing/Play App Signing path and account state. Do not add credentials, fabricate a keystore, commit secrets, or select an account/signing identity without Ramy's authorized input.

## Privacy / Play user-data boundary

Current official Google Play policy (verified 2026-09-07) requires every app to have a comprehensive privacy policy linked in Play Console and a privacy-policy link or text accessible inside the app.

The repository currently has no privacy-policy surface. Final identity/developer naming is needed before publishing permanent policy text/URL, so the correct sequence is:

1. approve final app/developer identity;
2. determine the actual final data-access/collection/sharing behavior from exact final source and Play configuration;
3. publish an active public privacy-policy URL using the approved identity;
4. add the smallest coherent in-app privacy access surface;
5. verify the final Play Data safety answers against actual behavior rather than generic boilerplate;
6. rendered/readback-certify the in-app privacy surface on the exact final bytes.

`android:allowBackup="true"` is currently present. Its interaction with local app state must be considered in the final privacy/Data safety review; do not change backup behavior by assumption.

## Foreground-service Play boundary

Current Android/Google Play guidance permits `specialUse` for valid foreground-service use cases not covered by another type, but the use case is reviewed at submission. The surviving manifest declaration is `ScreenOnService` with a subtype explaining that it keeps the screen awake only while the user explicitly enables Screen Always On.

Before submission, verify the corresponding Play Console foreground-service declaration accurately describes the same user-initiated behavior and matches the exact final manifest. Do not resurrect the obsolete Rotation Lock foreground service.

## Target API boundary

Official Play requirements effective 2026-08-31 require new Android mobile apps and app updates to target Android 16 / API 36 or higher. The current Gradle target is API 36, so the pre-identity candidate meets the current target-SDK baseline.

Reverify target/compile metadata from the exact final signed candidate after identity/version/signing changes; do not rely only on this pre-identity audit.

## G11 — exact-final rendered certification

A pre-identity green run is not final rendered certification. After all approved identity/privacy/version/customer-visible changes are applied:

- build the exact final candidate bytes;
- rerun the full publication runtime suite on those exact bytes;
- review every distinct meaningful customer-visible state required by the publication QA plan;
- verify final name/icon/package-facing copy and privacy access surface;
- retain exact-head build/runtime artifacts and hashes;
- record any impact-based inherited evidence explicitly rather than silently assuming it.

## G12 — physical/OEM/hardware boundary

Emulator evidence must not be promoted into hardware proof. At minimum preserve explicit coverage for the physical/device-only variants identified in the matrix, including:

- real flashlight/torch illumination and no-flash behavior;
- Screen Light optional torch behavior;
- foldable/slab orientation and Rotation Lock variants;
- Bluetooth/NFC/tethering hardware and permission-state variants;
- physical Screen Always On/foreground-notification behavior;
- OEM/DND/audio behavior where the matrix keeps a device-scoped qualifier.

Any other physical-only variant exposed by the final matrix remains part of this gate.

## Account-dependent control boundary

ID28 Sync Now is green only for the clean-emulator no-account lifecycle. Account-populated/sync-adapter variants require a real authorized account/device environment and must remain explicitly open until exercised or intentionally scoped out by the publication authority.

## Play Console / account-state boundary

Before submission, inspect the real authorized Play Console state rather than assuming:

- app/package registration availability and identity;
- Play App Signing/upload key state;
- required testing-track / production-access state for the actual developer account;
- privacy-policy URL and Data safety form;
- foreground-service declarations;
- content rating and store-listing requirements;
- release/version-code availability and any account-specific warnings.

These are account/external-state checks; they cannot be truthfully certified from repository source alone.

## Final release rule

Do not call the app final, release-ready, ready to publish, or publicly published merely because CI is green.

A final publication closure requires, in order:

1. G9 identity decision and approved permanent customer identity changes;
2. production signing/account path configured without exposing secrets;
3. privacy policy + in-app access + Play declarations based on actual final behavior;
4. exact-final full CI and rendered certification;
5. required physical/OEM/account variants completed or explicitly dispositioned by authority;
6. real Play Console preflight clean for the final package/version;
7. explicit Ramy approval for public Publish/go-live.
