# Nextbell OAuth configuration

Updated in Google Cloud Console on 2026-09-07 using `makadsuhel11@gmail.com`.

## Project and consent

- Project: **Nextbell** — `nextbell-507711` (number `483596257075`).
- [Manage OAuth clients](https://console.cloud.google.com/auth/clients?project=nextbell-507711).
- Google Calendar API (`calendar-json.googleapis.com`) and Google Tasks API (`tasks.googleapis.com`) are enabled.
- Consent app name: Nextbell; the original bell icon is uploaded.
- Support and developer contact: `makadsuhel11@gmail.com`.
- Audience: **External / In production**.
- Branding: verified and published; `nextbell.org` domain ownership verified in Search Console.
- Homepage: https://www.nextbell.org/; privacy: https://www.nextbell.org/privacy; terms: https://www.nextbell.org/terms.
- Calendar/Tasks sensitive scopes were submitted on 7 September 2026 and are **under review**. Approval is pending; the 100-user lifetime cap for unapproved sensitive scopes still applies.
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

**Retired iOS registration — Nextbell iOS**

```text
Client ID: 483596257075-737r108t0g9dbc4128fiv3gin5iva5ul.apps.googleusercontent.com
Bundle ID: com.suhel.nextbell
URL scheme: com.googleusercontent.apps.483596257075-737r108t0g9dbc4128fiv3gin5iva5ul
```

The owner explicitly approved removing this unused client for the Android-only release on 7 September 2026. It is deleted and cannot authorize requests. The identifiers above are a historical record, not active configuration. Before future iOS testing, create a new iOS registration and update the local client ID and callback scheme together, then provide the required iOS verification evidence. App Store ID and Apple Team ID were never configured.

## Local app configuration

The local files `apps/mobile/config.local.json` and `apps/mobile/ios/Flutter/OAuth.xcconfig` remain ignored by Git. They still contain the now-retired iOS client ID and callback scheme; replace both before attempting iOS sign-in. The Android release does not use that client ID. No client secret was downloaded or embedded.

```sh
cd /Users/suhel/code/me/apps/mobile
flutter run --dart-define-from-file=config.local.json
```

On Android, AuthorizationClient resolves each native OAuth registration from the package and signing certificate. A web OAuth client is not needed. The signed main-branch build is on the owner-only internal Play track, and the same bundle is in review for the closed Alpha track. See [the Android release record](play-store/README.md).

## Android release clients

All registrations use package `com.suhel.nextbell`. Public certificate fingerprints are not secrets. The original debug client remains unchanged. The unused iOS client was deleted with the owner’s explicit approval, as recorded above.

| Registration | SHA-1 | Client ID |
| --- | --- | --- |
| Upload-signed local release | CA:13:DE:BA:20:18:1E:FB:2C:35:3C:97:C8:B2:8D:1E:0A:B8:74:BA | 483596257075-015m8noa2mvr3705jns2nvmal1r4knfd.apps.googleusercontent.com |
| Google Play original signing | 9A:C5:3D:97:B8:8E:3A:2E:BF:05:6C:0E:9E:6D:D5:75:EB:C4:38:DE | 483596257075-ir1ev4pvnjtgkkrfc5qohmu2kf4mm656.apps.googleusercontent.com |
| Google Play classical signing | B2:79:6A:E9:C1:CE:05:DF:B2:21:7B:F4:7B:2B:87:AB:80:49:05:DA | 483596257075-avpia3i8r7s7iihnfgujjpl05no4m2gi.apps.googleusercontent.com |
| Google Play PQ signing | 8A:D1:30:E0:7D:4C:3B:77:F1:22:FF:71:13:71:EC:0E:6E:D5:D1:E5 | 483596257075-v8bh91m6kdn2oldv5ummov2ks5i57ejs.apps.googleusercontent.com |

Play selected its quantum-ready signing configuration. The three Play certificate fingerprints were checked against the public DER certificates downloaded from App integrity. The upload certificate was checked against the local signed artifact. Keep every applicable fingerprint registered so Google login works across signing variants.

## Remaining verification

Branding and domain ownership passed. The Calendar/Tasks scope justification and [unlisted Android demonstration](https://youtu.be/-zGvuykleL8) are saved in Google Auth Platform. The video shows Google consent, selected calendars, event reminders, task reading and completion, native alarm permissions, a locked-emulator alarm, Snooze, and Dismiss. It has no audio track. Android authorization and task completion were tested with a dedicated reviewer account on the upload-signed APK.

Sensitive-scope verification was submitted on 7 September 2026. Google Auth Platform confirms **Your app’s data access is under review**. The unused iOS client was removed with the owner’s explicit approval before submission, resolving the missing-client demonstration issue. All five active clients are Android registrations for the same package and consent implementation; their signing variants are explained in the submission. No approval is implied until Google completes its review. The existing local Xcode blocker remains a future iOS release concern.

All Android client registrations refer to the same package and consent implementation; their certificates distinguish debug, upload-signed, and Play-signed installations. No web OAuth client, backend, or new Google scopes were added.

Google sign-in and alarm behavior must still be checked on a physical device installed through Play. A valid client registration alone does not prove end-to-end authorization. Retain secure, separate reviewer test credentials in Play Console, never in this repository.
