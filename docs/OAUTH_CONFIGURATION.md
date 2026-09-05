# Nextbell OAuth configuration

Configured in Google Cloud Console on 2026-09-05 using `makadsuhel11@gmail.com`.

## Project and consent

- Project: **Nextbell** — `nextbell-507711` (number `483596257075`).
- [Manage OAuth clients](https://console.cloud.google.com/auth/clients?project=nextbell-507711).
- Google Calendar API (`calendar-json.googleapis.com`) and Google Tasks API (`tasks.googleapis.com`) are enabled.
- Consent app name: Nextbell; the original bell icon is uploaded.
- Support and developer contact: `makadsuhel11@gmail.com`.
- Audience: **External / Testing**.
- Allowed test user: `makadsuhel11@gmail.com`.
- Scopes: `openid`, `https://www.googleapis.com/auth/userinfo.email`, `https://www.googleapis.com/auth/userinfo.profile`, `https://www.googleapis.com/auth/calendar.readonly`, `https://www.googleapis.com/auth/tasks`.

The console displays the canonical identity scope URLs; the Android SDK requests their `email` and `profile` aliases. Tasks access allows more operations than completion, but Nextbell only patches task completion status. Calendar data remains read-only.

## Native clients

**Android — Nextbell Android — local debug**

```text
Client ID: 483596257075-kh8qlc94ne4p7mr9i72jps3vpu8j5p1s.apps.googleusercontent.com
Package: com.suhel.nextbell
SHA-1: AB:F3:C1:E8:6B:E1:29:3A:A2:DE:5B:0F:AE:FE:8B:AB:A0:29:47:96
```

The fingerprint was checked against both this Mac's debug keystore and the delivered `Nextbell-development.apk` using `apksigner verify --print-certs`. The existing APK matches this registration; rebuilding is unnecessary for this console change. The Android AuthorizationClient resolves registration from package and certificate; no client ID or secret is embedded for Android.

**iOS — Nextbell iOS**

```text
Client ID: 483596257075-737r108t0g9dbc4128fiv3gin5iva5ul.apps.googleusercontent.com
Bundle ID: com.suhel.nextbell
URL scheme: com.googleusercontent.apps.483596257075-737r108t0g9dbc4128fiv3gin5iva5ul
```

App Store ID and Apple Team ID are unset because distribution has not been configured.

## Local app configuration

The real iOS client ID is saved in `apps/mobile/config.local.json` and `apps/mobile/ios/Flutter/OAuth.xcconfig`. Both files are ignored by Git. Their client IDs and reversed URL scheme were checked against each other and the existing Info.plist references. No client secret was downloaded or embedded.

```sh
cd /Users/suhel/code/me/apps/mobile
flutter run --dart-define-from-file=config.local.json
```

On Android, install the existing development APK and connect the allowed Gmail account from onboarding or Settings → Accounts & Calendars. Google says configuration changes may take five minutes to a few hours to take effect. Other Google accounts must be added under [Audience → Test users](https://console.cloud.google.com/auth/audience?project=nextbell-507711) before they can connect during testing.

## Remaining validation and release work

Console creation and local configuration checks passed. Actual device sign-in, token refresh, multi-account restoration, and Calendar/Tasks sync have **not** been exercised with these new credentials. The local iOS build remains blocked by the existing Xcode license/setup issue.

Google shows that verification is not required while the app is in Testing. The audience page also reports incomplete branding for publishing. The owner has since supplied `nextbell.org`. Local publishing pages are prepared; console URLs and authorised domains remain blank until the website is deployed. See `WEB.md`. Do not use the unrelated nextbell.app or nextbell.com domains.

Before public release, resolve branding ownership, publish the required app URLs, register release/Play signing fingerprints, configure Apple distribution details, and complete Google's applicable branding/sensitive-scope verification. Testing configuration is not public-release approval. See `RELEASE.md` for the remaining release gates.
