# Nextbell

Google Calendar and Tasks, with personal alarms and a little more headspace.

This monorepo contains the Flutter app, the live Next.js publishing website for **nextbell.org**, and the Android cloud-beta foundation. Vercel hosts the website; Cloudflare manages the domain. Private beta activation is documented separately and does not change the existing production project.

## Projects

| Location | Purpose | Toolchain |
| --- | --- | --- |
| `apps/mobile` | Android/iOS app, local native plugin, and mobile tests | Flutter 3.47.2 / Dart 3.13.2 |
| `apps/web` | Public homepage, privacy, support, terms, and data removal | Next.js 16.3.4 / React 19.2.8 / TypeScript |
| `packages/cloud` | Versioned mobile API, Google synchronization and Firestore jobs | TypeScript / Firebase Admin |
| `infra/cloud` | Private beta infrastructure, identities, budgets and backups | OpenTofu 1.12.6 |
| `docs` | Architecture, setup, OAuth configuration, and release records | Markdown |

Node **24.18.0** and pnpm **11.25.0** are pinned at the root. Use pnpm for workspace commands and web packages; Flutter continues to own Dart dependencies. The native plugin stays inside the mobile project so its Pigeon and native build paths stay relative to the app.

## Start locally

```sh
pnpm install --frozen-lockfile
pnpm dev                  # Website: http://localhost:3000
pnpm demo:mobile          # Flutter sample data, no alarms
pnpm dev:mobile           # Real Google connection; requires local config below
```

The existing local OAuth configuration was moved to `apps/mobile/config.local.json` and `apps/mobile/ios/Flutter/OAuth.xcconfig`, both ignored by Git. On another checkout, follow [Google setup](docs/SETUP.md); never copy native credentials into the web app. Android cloud-beta builds use the separate ignored `cloud.local.json` described in [Cloud beta setup](docs/CLOUD_BETA.md). The initial allowed tester is documented in [the OAuth record](docs/OAUTH_CONFIGURATION.md).

## Check and build

```sh
pnpm check:cloud          # Backend TypeScript
pnpm test:cloud:emulator  # Backend tests; Java 21+ on PATH
pnpm check:web            # ESLint, Next route types, TypeScript
pnpm build                # Production Next.js build
pnpm --filter @nextbell/web exec playwright install chromium webkit
pnpm test:web             # Browser checks against the production build
pnpm check:mobile         # Dart formatting, analysis, Flutter/native Android tests
pnpm build:android:debug  # Debug APK
pnpm build:android        # Unsigned release AAB without signing config
pnpm build:ios            # Unsigned iOS build; local OAuth config required
```

Mobile commands run from `apps/mobile`. Execute mobile tests and builds sequentially: Flutter's generated native plugin registrant differs between test and release configurations. Web checks can run independently. Do not manually retain generated absolute-path metadata when moving the checkout; `flutter clean` and `flutter pub get --enforce-lockfile` regenerate it.

## Publishing status

The website is live at **https://www.nextbell.org/**. The app remains **coming soon**, with no public store listings. This branch adds an authenticated cloud backend for an allowlisted Android private beta. It does not add a dashboard, analytics, advertisements or a contact-form backend.

Hosted beta activation, new server OAuth/Firebase configuration, physical-device cloud testing and the 48-hour soak remain release gates. The user is creating a separate Google billing account; do not attach the existing OSS CRM billing account. Native Google clients are preserved. Earlier direct-Google phone tests remain in the validation history; they do not establish cloud-beta behavior. Local iOS verification is blocked by incomplete Xcode setup.

## Guides

- [Android cloud beta and deployment](docs/CLOUD_BETA.md)
- [Mobile setup](docs/SETUP.md)
- [Website and Vercel setup](docs/WEB.md)
- [Google OAuth configuration](docs/OAUTH_CONFIGURATION.md)
- [Mobile architecture](docs/ARCHITECTURE.md)
- [Validation and device acceptance](docs/VALIDATION.md)
- [Release checklist](docs/RELEASE.md)

CI validates the backend, web, Android, and iOS apps independently. Owning `nextbell.org` establishes the intended domain; it does not by itself establish trademark or store-name clearance.
