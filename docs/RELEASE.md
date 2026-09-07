# Release preparation

## Android release status — 7 September 2026

The device-only `main` build (680ca1e), version 1.0.0 (1), is published to the owner-only internal Play track. The same bundle and completed listing are **in review** for closed testing in all available countries. The cloud branch is excluded. See [the release record](play-store/README.md) for signing, artifacts, store assets, validation, and remaining production gates. Public production is not yet available.

## Working name needs clearance

A public search on 2026-09-05 found an existing [NextBell timer PWA](https://nextbell.app/) and a business at [nextbell.com](https://www.nextbell.com/). This is a concrete naming overlap; **Nextbell branding availability is not confirmed**. Public store searches did not establish name reservation or trademark clearance. Keep this as the working project name until the release owner clears it or chooses another name. Do not use those existing domains as this project's privacy/support URLs.

The owner controls `nextbell.org`, now the intended website domain. Owning that domain does not resolve the naming-overlap check above. The publishing website is live at https://www.nextbell.org/; see [WEB.md](WEB.md).

## Earlier cross-platform copy draft

The Android listing uses the current [English store copy](play-store/en-GB/listing.json). The following is retained as an earlier cross-platform draft; iOS is not part of this release.

**Working title:** Nextbell

**Subtitle:** A little ahead of what's next

**Short description:** Google Calendar and Tasks, with personal alarms that fit your day.

**Full description:**

Make room for what matters. Nextbell brings your Google calendars and tasks into a focused agenda and gives you a personal heads-up before your next meeting.

Connect multiple Google accounts and choose the calendars you want to see—including calendars shared with you. Keep a calendar quiet, or give it a bell. Choose reminders in minutes, hours or days, with defaults for your app, a calendar, a recurring series or a single meeting. Anonymous availability-only calendars can ring too, when you explicitly enable them.

Google tasks stay quiet until you choose an alarm time. Complete them from Nextbell, with offline completion queued for your next connection. Event times follow your phone's timezone, and scheduled alarms remain on your device for offline use.

A clean agenda, light and dark themes, and small, playful animations help you stay a little ahead. Reduced Motion and large text are supported. No ads, analytics or subscriptions.

Requires a Google account and Android 8+ with Google Play services or iOS 26+. Alarm permissions are required for ringing. Background refresh depends on the operating system; meeting changes arrive after a successful sync. Android force-stop and device restrictions can prevent delivery. Nextbell does not edit Google calendar events. Google's Tasks API provides dates but not times, so task alarms are set separately in Nextbell.

## Assets

- Original bell icon source renderer: `apps/mobile/tool/generate_brand_assets.dart`; 1024px master in `apps/mobile/assets/brand/icon-1024.png` and native Android/iOS icon sets.
- Bundled Manrope font and OFL license in `apps/mobile/assets/fonts/`.
- Rendered agenda/tasks/settings/reminder previews: regenerate with `CAPTURE_PREVIEWS=true` as described in SETUP. Capture final signed builds on required store devices/resolutions before upload; generated UI previews are drafts.
- Typed website content supplies privacy, terms, support, and data-removal pages with Suhel Makkad and makadsuhel11@gmail.com as the public contact. Final URLs use nextbell.org. The pages are live at https://www.nextbell.org; keep their behavior descriptions current.

## Permission review notes

Android core functionality is user-selected calendar/task alarm delivery. The app requests `SCHEDULE_EXACT_ALARM` special access and uses `setAlarmClock()`; it does not declare `USE_EXACT_ALARM`. `USE_FULL_SCREEN_INTENT` provides the lock-screen alarm UI; notification and media-playback foreground service permissions support the audible alarm. Prepare a screencast showing explicit calendar selection, multiple offsets, lock-screen delivery, Snooze/Dismiss and cancellation when a source is turned off. Explain reboot restoration and the visible permission/coverage checks. Review current Google Play alarm/full-screen eligibility and declarations before submission; approval is not assumed.

iOS uses AlarmKit with `NSAlarmKitUsageDescription` and fixed-date schedules. GoogleSignIn/Nextbell privacy manifests must be reviewed with the actual archive, including required-reason APIs and transitive dependencies. Demonstrate native alarm actions while the Flutter process is not active. Review the resulting privacy report and App Store Connect disclosure answers against actual network behavior.

Primary references: [Android exact alarms](https://developer.android.com/develop/background-work/services/alarms/schedule), [Full-screen intent policy](https://support.google.com/googleplay/android-developer/answer/13392821), [Apple AlarmKit](https://developer.apple.com/documentation/alarmkit), [Google OAuth verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification).

## Release gates (not yet completed)

- [ ] Resolve working-name overlap, package/bundle IDs and ownership.
- [x] Configure testing Google Cloud clients, consent, local Android debug fingerprint and the initial Gmail tester. See `OAUTH_CONFIGURATION.md`.
- [x] Register Android upload and Play signing fingerprints.
- [ ] Receive public OAuth sensitive-scope approval; Android verification is submitted and under review, and branding is verified.
- [x] Publish operator-owned HTTPS homepage/privacy/support URLs and contact details; link these from store metadata.
- [ ] Finish Xcode setup; resolve/commit SwiftPM lockfile; compile and run native iOS tests.
- [x] Configure Android upload signing and Play App Signing.
- [ ] Configure Apple team/distribution signing.
- [ ] Run every physical-device scenario in VALIDATION on both platforms, including iOS native intent discovery and independent multi-account session restoration.
- [ ] Profile scrolling/transitions in profile mode on representative phones, and capture final store screenshots.
- [x] Submit Android store listing, privacy/Data safety, reviewer access, and alarm permission declarations for review.
- [ ] Complete closed-test distribution, 12 testers for 14 days, feedback, and production-access review.
- [ ] Verify release artifacts and remove any test-only consent configuration. Publish only after these gates pass.

Project `nextbell-507711` now has External / In production OAuth audience and verified, published branding. Native release signing clients are registered. The Android demonstration and sensitive-scope justification were submitted after the owner approved deleting the unused iOS client. Data access is under review; all Android clients remain active. No paid service or enhanced cloud deployment was created for the Android release.
