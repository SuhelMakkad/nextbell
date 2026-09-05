# Development setup

> Android cloud-beta setup now lives in [CLOUD_BETA.md](CLOUD_BETA.md). The direct-Google instructions below apply to the iOS prototype and earlier development builds. Preserve existing native OAuth registrations.

The Flutter project is in `apps/mobile`; run Flutter and native commands below from that directory. Root pnpm wrappers are listed in README. Website setup is in [WEB.md](WEB.md).

## Tooling

The repository pins Flutter **3.47.2 stable** in `.fvmrc`, exact direct Dart dependency versions in `pubspec.yaml`, and resolved Dart dependencies in both lockfiles. Android app/plugin dependency graphs also have Gradle lockfiles; Flutter ABI artifacts are excluded because the pinned Flutter SDK selects them per target. Use this SDK (Dart 3.13.2), Java 17, Android SDK/target 36, NDK 28.2.13676358 and CMake 3.22.1. Android minimum is 26. The pinned Workmanager dependency currently requires Flutter's AGP compatibility flags; keep them until that dependency supports AGP's built-in Kotlin path.

On this Mac Flutter and Android tooling are installed; Android debug builds work. Xcode 26.6 is installed but its license has not been accepted and Command Line Tools is the selected developer directory. The owner must review/accept the license (`sudo xcodebuild -license` with Xcode selected), complete Xcode first launch, and install an iOS 26 simulator runtime. Select `/Applications/Xcode.app/Contents/Developer` using Xcode settings or `xcode-select`, then run `flutter doctor -v`.

```sh
cd /Users/suhel/code/me/apps/mobile
flutter pub get --enforce-lockfile
flutter run --dart-define=NEXTBELL_DEMO=true
```

No OAuth credentials are needed for demo mode. It uses a separate in-memory database and no-op alarm adapter. Exit the demo from its banner or Settings to connect real accounts.

## Google Cloud and consent

This Mac now has testing OAuth configured in project `nextbell-507711` under `makadsuhel11@gmail.com`, including both native clients and the local iOS configuration files. See [the configuration record](OAUTH_CONFIGURATION.md) for client IDs, the registered debug certificate, the allowed test account, and remaining release requirements. The steps below describe setting up another environment or finishing production configuration.

1. Create your own Google Cloud project; enable **Google Calendar API** and **Google Tasks API**.
2. Configure an External OAuth consent screen. Add the developer identity, a controlled domain, public homepage, privacy policy and support details. While testing, add every test account.
3. Request `openid`, `email`, `profile`, `https://www.googleapis.com/auth/calendar.readonly` and `https://www.googleapis.com/auth/tasks`. The Tasks scope enables completing tasks. There is no narrower completion-only Google scope; this app issues only a status patch.
4. Create Android and iOS native OAuth clients. **Do not put a client secret in this app.** The iOS prototype does not use the cloud token-exchange backend.
5. Complete Google's sensitive-scope verification before a broad public release. Provide a consent/scope-use demonstration, domain verification and a justification for Calendar reading and Tasks completion. Test-mode sessions may expire; reconnect when prompted. Do not market a testing consent project as production-ready.

References: [OAuth native apps](https://developers.google.com/identity/protocols/oauth2/native-app), [Calendar scopes](https://developers.google.com/workspace/calendar/api/auth), [Tasks authorization](https://developers.google.com/workspace/tasks/auth).

### Android

The provisional package is `com.suhel.nextbell`. Create OAuth Android clients for that package and each signing certificate's SHA-1 (debug, upload where applicable, and Play App Signing). Get fingerprints with `(cd android && ./gradlew signingReport)`. Authorization uses Google Play services' account-specific AuthorizationClient; there is no Android client secret or web server ID to embed. Devices need Google Play services.

Create `android/key.properties` from its example only when production signing is ready. Keep the upload keystore and passwords out of Git. Release builds without this file remain **unsigned**. Debug APKs use the development certificate; register that fingerprint for real sign-in testing.

### iOS

Create an iOS OAuth client for the app bundle ID. Copy `ios/Flutter/OAuth.xcconfig.example` to the ignored `OAuth.xcconfig`, and set the actual client ID and reversed URL scheme. Copy `config.example.json` to ignored `config.local.json` with the matching client ID.

```sh
flutter run --dart-define-from-file=config.local.json
flutter build ios --release --no-codesign --dart-define-from-file=config.local.json
```

The native plugin pins GoogleSignIn-iOS 10.0.0 with Swift Package Manager. After the first successful Xcode resolution, commit the app's `Package.resolved` (it cannot be generated on the current unlicensed Xcode toolchain). Configure the development team, bundle IDs, signing and distribution in Xcode. Verify the AlarmKit usage description, native intent discovery, URL callbacks and background task identifier in the actual signed app.

Each connected `GIDGoogleUser` authorization archive is stored separately in Keychain with `AfterFirstUnlockThisDeviceOnly`. The Android Google SDK owns authorization credentials; Nextbell stores only account metadata. Removing an account clears local credentials/metadata and cached content. Users can also revoke the app's Google grant in their Google Account.

## Code generation and assets

```sh
dart run build_runner build --delete-conflicting-outputs
dart run pigeon --input packages/nextbell_platform/pigeons/messages.dart
flutter gen-l10n
flutter test tool/generate_brand_assets.dart
```

Generated Drift, Pigeon and localization files are included with the source. Domain models have no Flutter dependency. English is the only shipped locale; navigation/headlines have ARB keys. Finish extracting remaining English copy and add native string catalogs before introducing another language.

`flutter test test/features/app_widget_test.dart --dart-define=CAPTURE_PREVIEWS=true` writes rendered demo previews to `build/previews/`. These are UI previews, not claims of physical-device testing or final store screenshots.

To intentionally refresh Android dependency locks, run `(cd android && ./gradlew :app:dependencies :nextbell_platform:dependencies --write-locks)`. Use `flutter build` for app builds so Flutter regenerates its native plugin registrant for the selected debug/release target.
