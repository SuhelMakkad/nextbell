# Validation

## Automated checks

`pnpm check:mobile` (or `./tool/check.sh` from `apps/mobile`) performs Dart formatting, Flutter analysis/tests and Android native unit tests. CI configuration also builds unsigned release bundles and iOS archives and runs iOS native tests. CI is prepared, not a claim of a remotely executed passing workflow.

Flutter tests cover 3 PM → 2:50/2:55, inherited rules/resets, all-day/declined/watched events, shared-event deduplication, DST/travel instants, task alarm independence, hidden/paginated calendar discovery, returned private fields, FreeBusy limits/partial failures, account removal races, permission downgrades, off-during-fetch, empty/failed snapshots, durable offline completion, dismissal acknowledgement, snooze collisions, OS capacity, permission revocation, database reopen/rollback/indexes and widget navigation/large text/reduced motion.

Android Robolectric tests exercise real native persistence and alarm operations at API 28: reconstructing the store, retained action acknowledgements, snooze preserving a second reminder, dismiss preserving a second reminder, and expired alarm rejection. They do not prove real locked-device delivery. iOS XCTest covers its action ledger; compilation/execution is blocked locally by the unaccepted Xcode license.

Widget screenshots use bundled typography and actual Flutter widgets. They use sample data and a no-op native adapter. They are not physical-device evidence.

## Monorepo and publishing website — September 5, 2026

Validated after moving the complete Flutter tree into `apps/mobile` and adding `apps/web`:

- Node 24.18.0, pnpm 11.25.0, Next.js 16.3.4 and Flutter 3.47.2 verified locally.
- Root `pnpm install --frozen-lockfile` passes. Both apps are private workspace packages. Dart and Gradle lockfiles are retained separately.
- Web Prettier check, ESLint, TypeScript and production build pass. All five publishing routes, robots, sitemap, icons and the local social image are generated successfully.
- **26 Playwright checks pass** across Chromium desktop and WebKit mobile. Coverage includes all public routes, navigation, support/deletion links, 404 recovery, canonical/Open Graph/Twitter metadata, image loading, absence of unpublished store/auth links and forms, axe WCAG A/AA scans, 320px layout with 200% text, reduced motion, and keyboard reminder/FAQ interaction. WebKit uses Safari’s Option-Tab convention for link navigation.
- Desktop and phone-sized layouts were reviewed locally using the browser and actual bundled Flutter demo previews.
- **40 Flutter unit/widget tests and 4 Android native tests pass** after relocation. Android debug APK and unsigned release AAB build successfully. No physical-device beta result is implied.
- Verified the native account client identifier and callback configuration, package/bundle identifiers, local plugin resolution, regenerated Flutter application path, Flutter pin, and Git exclusion of local OAuth/configuration files. No OAuth console changes were made.
- iOS remains unverified: the system selects Command Line Tools by default. Running with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` reaches Xcode 26.6 but exits **69** because its license is unaccepted, before application compilation. No iOS license or global developer-directory setting was changed.
- CI now has independent web, Flutter/Android and iOS jobs with updated working directories and artifact paths. These workflows are prepared locally and have not run remotely.

No public deployment, DNS change, domain verification, web OAuth client, or store submission was performed. Public website links in the app depend on the later deployment. The local website tests do not establish production domain reachability.

## Physical device beta matrix — all pending

Record OS/build, device model, app commit, timezone, battery state, expected/actual UTC time and observed audio/action result. Use two Google test accounts and an owner-managed shared calendar with reader/freebusy/private cases. No physical phone was available during implementation.

| Scenario | Expected check | Android | iOS |
|---|---|---|---|
| Locked screen, 10/5 min offsets | Both native alarms fire; controls available immediately | Pending | Pending |
| Dismiss first reminder | Second reminder still fires | Pending | Pending |
| Snooze; collision with next offset | One ring for same identifiable occurrence/instant | Pending | Pending |
| Terminated Flutter process | Native delivery and actions work | Pending | Pending |
| Offline, no server changes | Downloaded alarms fire; completion queued | Pending | Pending |
| Remote moved/canceled meeting | Successful refresh cancels old alarms; failed refresh retains cache with error | Pending | Pending |
| Reboot before unlock | Future alarms restored according to OS restrictions; no expired backlog | Pending | Pending |
| Clock/timezone/DST changes | UTC instants preserved; local UI updated | Pending | Pending |
| Battery saving/background restrictions | Record delayed refresh and vendor-specific delivery restrictions | Pending | Pending |
| Silent/Focus/DND modes | Validate actual native behavior and alarm volume | Pending | Pending |
| Permission revocation/restoration | Visible failure; repair after grant; no claimed coverage while denied | Pending | Pending |
| OS alarm limit | Earliest accepted schedules and truthful partial coverage | Pending | Pending |
| Shared/private/freebusy access changes | Inaccessible details cleared; incompatible alarms paused | Pending | Pending |
| Multiple accounts after restart | Independent tokens restored, correct source provenance | Pending | Pending |
| Remove account during refresh | No stale content, queued writes or alarms reappear | Pending | Pending |
| Large text/VoiceOver/TalkBack | Readable controls, meaningful labels, no clipped actions | Pending | Pending |
| Reduce Motion | No springs/wiggles/stagger; controls still immediately interactive | Pending | Pending |
| Long agenda scrolling/profile build | Measure frame timings against display refresh budget | Pending | Pending |

**Android force-stop:** test separately from swiping away/normal process termination. Document that the OS may suppress alarms and workers until the user launches the app again. Never present force-stop as a supported guaranteed-delivery condition.

## Emulator checks

The Android 16 / API 36 Pixel 9 emulator passed the native-bridge and three-screen navigation smoke test. This uses a real Flutter engine and native plugin, with sample data. Use `flutter test integration_test/native_smoke_test.dart -d DEVICE_ID` to repeat it.

The native delivery integration test also passed on that emulator. `integration_test/alarm_delivery_test.dart` schedules a temporary native alarm, waits for its ringing state, then cancels and acknowledges its actions. It needs alarm permission first and is intentionally separate from unit tests. On a dedicated development emulator with the app installed:

```sh
adb shell appops set com.suhel.nextbell SCHEDULE_EXACT_ALARM allow
adb shell pm grant com.suhel.nextbell android.permission.POST_NOTIFICATIONS
flutter test integration_test/alarm_delivery_test.dart -d DEVICE_ID --no-uninstall
```

This test can audibly ring on a physical device; use a dedicated test device and expect the alarm. An emulator run does not replace the physical-device matrix above.

## Local build status

Formatting and static analysis pass. The application has 40 Flutter unit/widget tests plus four Android native tests. Android debug and unsigned release bundles build. Both Android emulator integration checks passed (bridge/navigation and actual native ringing/cancellation). iOS release invocation exits with Xcode's license error (exit 69), before compiling application code. Production OAuth/signing and physical-device delivery behavior remain unverified.
