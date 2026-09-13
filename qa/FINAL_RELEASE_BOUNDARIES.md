# Final Release Boundaries — ToggleBay Publication Branch

Technical baseline authority: `publication-readiness`
Current identity-integration branch: `togglebay-q3-integration-20260912`
Purpose: preserve the exact remaining boundary between the certified restored-product baseline, the approved ToggleBay identity integration, and a genuinely final/publishable build. This file is a gate checklist, not permission to perform signing/account/publication actions automatically.

## Already established before the final-identity tranche

- Technical Gate 2A restored-product benchmark remains closed and is not to be restarted absent a concrete evidence-backed regression.
- Android compile/target SDK is 36.
- The publication control disposition is reconciled separately in `qa/PUBLICATION_CONTROL_MATRIX.md`: 34 new-picker survivors / 14 retired historical IDs, while stable tracker IDs 0–47 remain preserved for legacy definitions.
- Worker-owned API-36 emulator/runtime/rendered control scopes are evidence-backed as recorded in the matrix; explicitly listed physical/OEM/account variants remain open.
- `ScreenOnService` is the surviving special-use foreground service and declares its user-initiated screen-awake subtype in the manifest.
- Obsolete Rotation Lock `RLService` source/manifest registration has been removed; Rotation Lock uses the public WRITE_SETTINGS path.
- No public Publish/go-live action is authorized without explicit Ramy approval.

## G9 — public identity decision CLOSED; exact-byte certification still required

Master App Restoration authority now controls these public decisions:

- public app name: **ToggleBay**
- Android application/package ID: `com.ramybaheeg.togglebay`
- publisher/developer identity: **Ramy Baheeg / Ramy**
- approved store price: **$2.49**
- current Gradle version code: `1`
- current Gradle version name: `1.0.0`
- historical `com.painless.pc` remains only where required as the internal Java/resource namespace or deliberately preserved implementation/provenance identity; it is not the installed public application ID.

The identity decision itself is no longer an open gate. What remains is to certify the exact integrated customer bytes and ensure no unintended historical public branding/package authority survives outside deliberate attribution/provenance text.

## Production signing boundary

`build.gradle` currently has no production release `signingConfig`. CI can assemble the release AAB for technical validation, but that is not evidence that a production-upload signing identity/account is configured.

Final release requires the authorized Google Play App Signing/upload-key path and actual Play account state. Never commit or upload private signing keys/passwords to GitHub or ordinary Drive, never fabricate a keystore, and never claim account/signing state without reading the authorized environment.

## Privacy / Play user-data boundary

The identity integration contains ToggleBay privacy/attribution-facing resources, but repository source alone cannot certify the final public privacy-policy URL, Play Data safety answers, or real Play Console configuration.

Before submission:

1. determine the exact final data-access/collection/sharing behavior from the frozen candidate plus actual Play/SDK configuration;
2. publish the approved active public privacy-policy URL;
3. verify the in-app privacy access surface against the frozen candidate;
4. verify final Play Data safety answers against actual behavior rather than boilerplate;
5. rendered/readback-certify the privacy/attribution surface on the exact final bytes.

`android:allowBackup="true"` remains part of the current app behavior. Its interaction with local app state must be described accurately in the final privacy/Data safety review; do not change backup behavior by assumption.

## Foreground-service Play boundary

The surviving manifest declaration is `ScreenOnService` using `specialUse`, with a subtype explaining that it keeps the screen awake only while the user explicitly enables Screen Always On.

Before submission, verify the corresponding Play Console foreground-service declaration accurately describes that same user-initiated behavior and matches the exact final manifest. Do not resurrect the obsolete Rotation Lock foreground service.

## Target API boundary

Official Play requirements effective 2026-08-31 require new Android mobile apps and app updates to target Android 16 / API 36 or higher. The current Gradle target is API 36.

Reverify target/compile metadata from the exact final signed candidate; do not rely only on the inherited restored-product audit.

## Q4 / Q5 — exact integrated candidate certification

Identity/package/customer-visible changes invalidate only the affected surfaces; they do not erase the already-certified restored-product behavior baseline.

The correct sequence is:

1. finish Q3 identity/package/QA-harness integration with zero known customer-byte deltas;
2. freeze one exact Q4 candidate commit/tree;
3. run Q5 impact-scoped maximal certification on that frozen candidate, including build, install, package/component routing, provider/share/import-export/widget paths, runtime/rendered branding, privacy/attribution surfaces, and affected regression defenses;
4. retain exact-head artifacts/hashes and explicitly record inherited evidence rather than silently rerunning or silently assuming unrelated scopes.

Do not mutate frozen Q4 source while Q5 is in progress. A defect requires a successor candidate and a new impacted proof.

## G12 — physical/OEM/hardware boundary

Emulator evidence must not be promoted into hardware proof. Preserve explicit coverage/disposition for physical/device-only variants identified in the matrix, including:

- real flashlight/torch illumination and no-flash behavior;
- Screen Light optional torch behavior;
- foldable/slab orientation and Rotation Lock variants;
- Bluetooth/NFC/tethering hardware and permission-state variants;
- physical Screen Always On/foreground-notification behavior;
- OEM/DND/audio behavior where the matrix keeps a device-scoped qualifier.

Any other physical-only variant exposed by the final matrix remains part of this gate unless explicitly dispositioned by owning authority.

## Account-dependent control boundary

ID28 Sync Now is green only for the clean-emulator no-account lifecycle. Account-populated/sync-adapter variants require a real authorized account/device environment and remain explicitly open until exercised or intentionally scoped out by publication authority.

## Play Console / account-state boundary

Before submission, inspect the real authorized Play Console state rather than assuming:

- registration/availability of `com.ramybaheeg.togglebay`;
- Android developer-verification/package-registration state;
- Play App Signing/upload-key state;
- required testing-track / production-access state for the actual developer account;
- privacy-policy URL and Data safety form;
- foreground-service declarations;
- content rating and store-listing requirements;
- release/version-code availability and account-specific warnings.

These are account/external-state checks; they cannot be truthfully certified from repository source alone.

## Final release rule

Do not call ToggleBay publicly published merely because CI is green.

A final publication closure still requires, in order:

1. exact Q4/Q5 integrated-source certification;
2. production signing/account path configured without exposing secrets;
3. privacy policy + in-app access + Play declarations verified against actual final behavior;
4. required physical/OEM/account variants completed or explicitly dispositioned by authority;
5. real Play Console preflight clean for the final package/version;
6. explicit Ramy approval for public Publish/go-live.
