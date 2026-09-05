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

## Physical device beta matrix

Record OS/build, device model, app commit, timezone, battery state, expected/actual UTC time and observed audio/action result. Use two Google test accounts and an owner-managed shared calendar with reader/freebusy/private cases. Initial implementation used an emulator; the Android checks below now include a connected A001 physical phone on Android 16 (API 36), build B4.1-260615-1653, in Asia/Kolkata on September 5, 2026. Checks not explicitly marked passed remain pending.

| Scenario | Expected check | Android | iOS |
|---|---|---|---|
| Locked screen, 10/5 min offsets | Both native alarms fire; controls available immediately | Passed: personal event at 18:45 and 18:50 | Pending |
| Dismiss first reminder | Second reminder still fires | Passed on personal and watched work events | Pending |
| Snooze; collision with next offset | One ring for same identifiable occurrence/instant | Five-minute snooze delivered; exact collision covered by automated tests | Pending |
| Terminated Flutter process | Native delivery and actions work | Passed: actual Calendar alarms after `am kill` | Pending |
| Offline, no server changes | Downloaded alarms fire; completion queued | Alarm passed with no default network; real task completion pending | Pending |
| Remote moved/canceled meeting | Successful refresh cancels old alarms; failed refresh retains cache with error | Moved personal event passed; cancellation/failure covered by automated tests | Pending |
| Reboot before unlock | Future alarms restored according to OS restrictions; no expired backlog | Pending | Pending |
| Clock/timezone/DST changes | UTC instants preserved; local UI updated | Pending | Pending |
| Battery saving/background restrictions | Record delayed refresh and vendor-specific delivery restrictions | Pending | Pending |
| Silent/Focus/DND modes | Validate actual native behavior and alarm volume | Pending | Pending |
| Permission revocation/restoration | Visible failure; repair after grant; no claimed coverage while denied | Pending | Pending |
| OS alarm limit | Earliest accepted schedules and truthful partial coverage | Passed at 500 alarms, including quick-alarm slot recovery | Pending |
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

Formatting and static analysis pass. The application has 49 passing Flutter unit/widget tests plus four passing Android native tests after the September 5 phone fixes. Android debug and unsigned release bundles build. Both Android emulator integration checks passed (bridge/navigation and actual native ringing/cancellation). iOS release invocation exits with Xcode's license error (exit 69), before compiling application code. Production OAuth/signing and the remaining beta matrix require verification. The physical Android results above do not establish iOS or other manufacturers’ behavior.

## Android calendar E2E — September 5, 2026

Tested the connected phone using the development APK with the existing Google account preserved. Browser-created ordinary events named **Focus time** (personal primary) and **Planning** (work primary) were explicitly private, without guests, conference links or Google notifications. The personal account has only free/busy access to the watched work calendar; Nextbell correctly displayed an anonymous busy block without the private work title. No sharing permissions were changed.

Fixed and verified:

- Successful sign-in replaces the welcome route. Calendar setup has an agenda underneath it, so Back no longer reveals the welcome screen with a waiting sign-in button. Widget regressions cover first connection and restored accounts with unfinished onboarding. Real-device checks cover restoration, system/toolbar Back and settings navigation. Fresh OAuth consent was not repeated.
- Google FreeBusy’s 97-day refresh is split into contiguous windows of at most 30 days and batches of at most 50 calendars. Overlapping/adjacent blocks merge across boundaries. A source with any failed window retains its previous complete snapshot. The previously failing watched work sources now synchronize on the phone.
- Test alarms recover an earliest slot at the device’s 500-alarm capacity. A failed replacement restores the displaced reminder, or reports the unresolved restoration error. The user confirmed the quick alarm made sound.
- A sync lease now records its owning process, so termination/update cannot leave a new process blocked for ten minutes. Live workers in the same process retain their lease. Account/source/task changes request a fresh pass after an in-flight sync. Regression tests verify ownership and fresh-pass behavior.

Physical checks passed for personal event import, anonymous watched-event import, 10/5-minute scheduling, private-event rescheduling, adding a two-minute occurrence override and resetting to inherited defaults, immediate cancellation in Off/Show only modes, and successful refresh/rescheduling after re-enabling. The temporary override was removed and primary calendar alarms restored. Existing unrelated calendars and credentials were retained.

The work event’s 18:37 reminder fired after normal process termination; dismissing it preserved the 18:42 reminder. That reminder was snoozed to 18:47:38 and delivered again. The personal event was moved to 18:55–19:10, replacing its old schedules with 18:45 and 18:50. Its 18:45 alarm displayed native Snooze/Dismiss controls over the locked screen while the app process was stopped and Android reported no active default network. Wi-Fi/mobile data were restored immediately afterward. The retained 18:50 reminder also fired on the locked screen after the first was dismissed. All reminders belonging to these two E2E events are now handled; no temporary snooze or custom offset remains. Alarm delivery/actions were verified from native records; direct audio confirmation was supplied by the user for the quick alarm.

`./tool/check.sh` passes formatting, static analysis, 49 Flutter tests and four Android native tests. `flutter build apk --debug` and `flutter build apk --release` pass. A first release attempt with `--no-pub` retained the integration-test plugin registrant from prior testing; rerunning the standard build regenerated this disposable metadata successfully. No generated registrant is committed. Production signing is not configured.

No claims are made for real-device reboot, force-stop, permission revocation, DST/timezone changes, task writes, multiple independently connected accounts, background endurance, accessibility services, or iOS; keep those release-beta checks open. The related automated tests are useful but do not replace these device checks.

## Native alarm appearance — September 5, 2026

Replaced Android’s default gray/all-capital buttons with Nextbell’s rounded indigo Snooze action and outlined Dismiss action. The alarm uses the app’s bundled Manrope font with explicit variable weight axes, dark surface, bell artwork, scalable text and system/cutout insets. The 320ms bell gesture and 160ms press feedback are disabled when Android’s animator setting is off. Audio and actions remain native and independent of animation.

On the A001 phone, reviewed the actual lock-screen alarm, exercised both Snooze and Dismiss, and received the snoozed alarm. At system font scale 2.0 with animator duration scale 0, the title wrapped and both controls remained fully visible; Dismiss stopped the alarm. Restored font scale 1.0 and the original unset animator setting. No temporary test alarm remains.

Four Android native tests, Android lint, debug APK and unsigned release APK builds pass. Lint reports existing plugin warnings; no warning originates from the new activity/resources. Lint caught an API-27-only navigation-bar attribute, which was removed from the minimum-API-26 theme; the AndroidX window controller handles navigation-bar appearance.
