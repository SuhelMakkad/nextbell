# Android 1.0.0 release record

The Android bundle is built from `main` commit `680ca1ea1f629d4d95483348bc57b419f494d6c8`. It contains the existing device-only application. The cloud-sync feature branch is excluded. This release branch only prepares publishing content, SEO, artwork, and documentation; it does not change mobile runtime code.

## Published internal build

- Package: `com.suhel.nextbell`; version name `1.0.0`; version code `1`.
- Minimum Android API 26; target API 36.
- AAB SHA-256: `7b90c8ad2d087d52f24530b23ba4120ddf704bc6127d78b8ba7dc35d0b888f76`.
- [Play Console](https://play.google.com/console/u/0/developers/8703189410650816296/app/4972373463556104132/app-dashboard).
- [Internal test opt-in](https://play.google.com/apps/internaltest/4701290743880211191), restricted to the selected tester list. The initial list contains the owner's Gmail account only.
- Internal release published on 7 September 2026. Play displays a temporary package-based name until review is complete. This is not public production availability.
- Play reports a typical 10.5 MB download; the upload bundle contains all supported ABIs.

## Closed test submitted for review

On 7 September 2026, Play Console confirmed **Changes in review** for the Alpha closed track, using the same version 1 bundle from the Play library. The release is named **1.0.0 — Device-only Android**. All 176 available countries/regions plus the rest of the world are selected. Managed publishing is off, so the closed release can become available after approval; this does not publish a production release.

- [Closed-test opt-in](https://play.google.com/apps/testing/com.suhel.nextbell), usable by eligible testers after approval.
- The initial selected email list contains only the owner's account. Additional testers' Google-account addresses have not yet been supplied. No invitations were sent.
- Google requires at least 12 testers opted in continuously for 14 days before a new personal developer can apply for production access. The period has not been established by this submission; internal testing does not satisfy it.
- Privacy, app access, ads, content rating, age targeting, Data safety, government, financial, health, advertising ID, full-screen intent, and foreground-service declarations are complete. See [DATA_SAFETY.md](DATA_SAFETY.md) for the submitted data mapping.
- A dedicated reusable Google review account is saved privately in Play Console. Never copy its password into Git, screenshots, issue bodies, or support pages.

## Signing and source separation

The upload keystore and `key.properties` stay ignored, with owner-only file permissions. Back up the keystore and its password securely outside Git. Never attach them to a PR, store listing, or website deployment.

The locally signed APK uses the upload certificate. Google Play signs installed APKs with its app-signing certificates. All required Android OAuth registrations are recorded in [OAUTH_CONFIGURATION.md](../OAUTH_CONFIGURATION.md). The development APK has a different certificate; installing a release over it is not an in-place update. Do not uninstall a user's development installation without arranging its local-data loss first.

## Store content and images

`en-GB/listing.json` is the submitted English copy. The listing uses the Productivity category and Calendar, Clock/alarm/timer, and Productivity tags. The saved audience is teens and adults (13+), with no marketing to children. IARC generated the regional content ratings independently from that audience selection.

`assets/` contains a 512px icon, a 1024×500 feature graphic, and five 1080×1920 phone screenshots. The screenshots were captured from the signed release APK on a fresh Android API 36 emulator using the app's built-in sample-data mode. No personal or work calendar data appears in them. Demo mode does not schedule real alarms. The icon and promotional graphic use the existing code-rendered bell design; their AI-assisted artwork is declared in Play. The screenshots are actual app captures.

The visual asset library is deliberately phone-focused. Do not relabel these as tablet or XR screenshots.

To regenerate the promotional graphic:

```sh
cd apps/mobile
flutter test tool/generate_store_graphics.dart
```

To export losslessly optimized RGB PNGs, place approved device captures in `apps/mobile/build/store-screens/{today,reminders,calendars-dark,tasks,today-dark}.png`, then run from the repository root:

```sh
node apps/web/scripts/export-play-assets.mjs
```

The widget preview harness can also produce draft 9:16 renders with `CAPTURE_PREVIEWS=true` and `STORE_PREVIEWS=true`; final listing assets above are device captures.

## Validation completed

- 49 Flutter tests, Flutter static analysis, and 4 Android native tests passed.
- Signed Android release APK and AAB built; the AAB passed signature verification and Play upload validation.
- Signed APK installed and opened on a fresh API 36 emulator. Agenda, details, reminder controls, Tasks, Settings, and theme changes were exercised with sample data.
- Real Google sign-in with the dedicated reviewer account succeeded on that signed APK. Calendar discovery, calendar mode changes, occurrence reminder changes, Google Tasks reading, and explicit task completion were tested. The completed task was confirmed in Google Tasks on the web.
- Generic fixtures in the review account include a private recurring “Daily planning” event and an active “Prepare meeting notes” task. No personal or work events were used in the review video.
- Notification and exact-alarm access, locked-emulator alarm presentation, five-minute Snooze, reopening the snoozed alarm, Dismiss, and calendar-alarm cancellation were exercised. The screen recording has no audio track and does not establish physical-device audibility.
- Web formatting, ESLint, TypeScript, production build, and 26 Chromium/WebKit checks passed. Browser coverage includes public routes, canonical metadata, keyboard access, accessibility scans, mobile reflow, enlarged text, and reduced motion.
- Website visually reviewed locally. The SEO edits remain separate from the already-live site until their PR is merged/deployed.
- Existing physical-device alarm checks are documented in the main branch's validation notes. This release has not yet completed Google sign-in and ringing on a physical device installed through Play.

## Remaining external gates

1. Wait for Play's closed-test review and address any findings. Supply real tester addresses and obtain at least 12 opted-in testers for 14 continuous days after the track becomes accessible.
2. Finish Google sensitive-scope verification. The unlisted [Android review video](https://youtu.be/-zGvuykleL8) and scope justification are saved in Google Auth Platform, and the video is attached to Play's foreground-service declaration. Branding and domain ownership are verified. The OAuth submission form asks for video coverage of every assigned OAuth client; the retained, unreleased iOS client has no validated demo because of the existing Xcode blocker. The final all-requirements attestation was left unchecked, and sensitive-scope verification was **not submitted**. Resolve that coverage requirement before attesting; do not claim iOS was tested or delete its registration as a workaround.
3. Verify the Play-installed build on a physical device, including Google sign-in, locked/offline ringing, reboot, permission revocation, and force-stop behavior. Preserve the user's existing local data when planning installation; the connected phone's debug app was not uninstalled.
4. Apply for production access and complete Google's reviews before adding a public store download link to the website.

The website remains coming soon. No cloud backend deployment, cloud testing, paid infrastructure, or public Android production rollout is part of this release.

References: [Google's closed-testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465), [reviewer app access](https://support.google.com/googleplay/android-developer/answer/9859455), [OAuth verification requirements](https://support.google.com/cloud/answer/13464321).
