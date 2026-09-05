# Nextbell

Google Calendar and Tasks, with personal alarms and a little more headspace.

This monorepo contains the Flutter mobile app and the Next.js publishing website for **nextbell.org**. The website is prepared for Vercel; the domain is managed through Cloudflare. Neither hosting nor DNS is changed by the local setup.

## Projects

| Location | Purpose | Toolchain |
| --- | --- | --- |
| `apps/mobile` | Android/iOS app, local native plugin, and mobile tests | Flutter 3.47.2 / Dart 3.13.2 |
| `apps/web` | Public homepage, privacy, support, terms, and data removal | Next.js 16.3.4 / React 19.2.8 / TypeScript |
| `docs` | Architecture, setup, OAuth configuration, and release records | Markdown |

Node **24.18.0** and pnpm **11.25.0** are pinned at the root. Use pnpm for workspace commands and web packages; Flutter continues to own Dart dependencies. The native plugin stays inside the mobile project so its Pigeon and native build paths stay relative to the app.

## Start locally

```sh
pnpm install --frozen-lockfile
pnpm dev                  # Website: http://localhost:3000
pnpm demo:mobile          # Flutter sample data, no alarms
pnpm dev:mobile           # Real Google connection; requires local config below
```

The existing local OAuth configuration was moved to `apps/mobile/config.local.json` and `apps/mobile/ios/Flutter/OAuth.xcconfig`, both ignored by Git. On another checkout, follow [Google setup](docs/SETUP.md); never copy credentials into the web app. The initial allowed tester is documented in [the OAuth record](docs/OAUTH_CONFIGURATION.md).

## Check and build

```sh
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

The app and website are **not publicly released**. The website says “Coming soon”; store buttons are hidden until their URLs are set in the web site configuration. No dashboard, web OAuth, database, analytics, or contact-form backend is included. Future dashboard routes can use the same standard Next.js App Router project.

The mobile privacy/about screen contains the final website links. Their public availability depends on the later Vercel deployment. Native Google OAuth remains in External / Testing. Real device Google sign-in and physical-device alarm acceptance still need validation. iOS compilation was previously blocked by this Mac's Xcode license/setup; see the validation record for current results.

## Guides

- [Mobile setup](docs/SETUP.md)
- [Website and Vercel setup](docs/WEB.md)
- [Google OAuth configuration](docs/OAUTH_CONFIGURATION.md)
- [Mobile architecture](docs/ARCHITECTURE.md)
- [Validation and device acceptance](docs/VALIDATION.md)
- [Release checklist](docs/RELEASE.md)

CI validates the web, Android, and iOS apps independently. Owning `nextbell.org` establishes the intended domain; it does not by itself establish trademark or store-name clearance.
