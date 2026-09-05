# nextbell_platform

Private Nextbell plugin. Pigeon provides one typed API for account authorization, credentials, alarm permissions, persistent native schedules and native action acknowledgement.

- Android: Google Identity AuthorizationClient, AlarmManager.setAlarmClock, direct-boot storage, native audio service and alarm activity.
- iOS 26: independently archived GoogleSignIn sessions in device-only Keychain, AlarmKit fixed schedules, native App Intents and an action ledger.
- Regenerate bindings from the application root with `dart run pigeon --input packages/nextbell_platform/pigeons/messages.dart`.
- Run native Android tests from `android/` in the application root with `./gradlew :nextbell_platform:testDebugUnitTest`.

See the application's docs for credentials, signing, physical-device limitations and release requirements. iOS code is not yet compiled locally because Xcode requires owner license acceptance.

## Android alarm presentation

The native lock-screen activity uses Nextbell’s dark surface, indigo primary action, outlined secondary action and bundled Manrope variable font. Android reads the font directly from Flutter’s packaged assets without creating an engine. Keep the colors and corner radii aligned with `lib/core/theme/app_theme.dart`. Alarm strings are Android resources.

Buttons use density-independent 56dp minimum targets and scalable text; long content can scroll. System bar/cutout insets are applied explicitly. A single 320ms bell gesture and 160ms press feedback follow Android’s animator setting. Sound and native Snooze/Dismiss actions are available independently of motion.
