# Publishing website

The website lives in `apps/web`. It uses standard Next.js App Router with server-rendered publishing pages and a small client component for the reminder example. Content and shared site configuration are typed TypeScript modules. There is no external content service, web authentication, or database.

## Local commands

From the repository root, install Node 24.18.0 and pnpm 11.25.0, then run:

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm check:web
pnpm build
pnpm --filter @nextbell/web exec playwright install chromium webkit
pnpm test:web
```

Web checks include Prettier formatting, ESLint and TypeScript. Browser checks use Chromium desktop and WebKit mobile, with axe accessibility scans, 320px/200% text reflow, keyboard interaction, reduced motion, metadata, links and local media.

Browser tests start the production build on port 3100. Make a fresh `pnpm build` after changing source. `pnpm dev` uses port 3000. These processes do not deploy anything.

## Public URLs

| Purpose | URL |
| --- | --- |
| Homepage / marketing | https://www.nextbell.org/ |
| Privacy policy | https://www.nextbell.org/privacy |
| Support | https://www.nextbell.org/support |
| Terms | https://www.nextbell.org/terms |
| Data removal / privacy choices | https://www.nextbell.org/data-deletion |

Operator: Suhel Makkad. Public support/privacy contact: makadsuhel11@gmail.com. The app's existing privacy/about screen links to these routes; these pages are live.

Review the typed publishing content before each public deployment, including the review/effective date, support email monitoring, hosting disclosures, and actual mobile behavior. Native Google account connections are local to the phone; the web page must not promise remote erasure of those records. No Nextbell server account exists yet. Revisit these disclosures when introducing a dashboard or any new collection of data.

## Vercel deployment

The owner deployed the publishing website before the Android release. Production uses `www.nextbell.org`; the apex redirects to it. SEO updates are prepared on a separate release PR. Google Search Console ownership was verified on 7 September 2026 through one additive Cloudflare TXT record; retain that record.

1. Push the monorepo to the intended Git repository, then import it as a Vercel project.
2. Select the Next.js framework preset, **Root Directory `apps/web`**, and Node **24.x**. Keep access to files outside the root enabled so the workspace lockfile is available.
3. Use `pnpm install --frozen-lockfile` for installation, `pnpm build` for the build, and the default Next.js output directory. The root `packageManager` and lockfile select pnpm 11.25.0. Do not upload native OAuth or signing files as web environment variables.
4. Review the preview deployment. Preview builds send a `noindex` robots header; the production canonical origin is always https://www.nextbell.org. Keep production publishing pages publicly accessible without Vercel deployment protection, sign-in, or a challenge.
5. Add `nextbell.org` and `www.nextbell.org` to the Vercel project. Use the exact DNS records Vercel provides in Cloudflare, initially DNS-only; preserve unrelated records such as email. Redirect the apex to the canonical `www` domain in Vercel. Confirm HTTPS on both names.
6. Visit every public route and validate support links, sitemap, robots, canonical tags, and the production deployment's indexing behavior.
7. Verify domain ownership in Google Search Console with the Google account associated with project `nextbell-507711`. Add `nextbell.org` to Google's authorised domains and enter the homepage, privacy, and terms URLs. The native app audience is now External / In production, and branding is verified and published. Calendar/Tasks sensitive-scope verification is submitted and under review; this is not a web OAuth client or backend deployment.
8. Copy the support/privacy URLs into store metadata. Set real store listing URLs in the typed site config only once they exist. Never publish the development APK as the store download.

References: [Vercel monorepos](https://vercel.com/docs/monorepos), [Vercel domains](https://vercel.com/docs/domains/working-with-domains/add-a-domain), [Google brand verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification).

The project is ready to accept future dashboard routes without switching deployment adapters. Web authentication, additional OAuth scopes/clients, server data storage, and updated privacy/deletion behavior are separate future work.

## SEO release changes

Descriptive Android calendar-alarm metadata, canonical URLs matching the live www host, WebSite/MobileApplication structured data, image sitemap entries, descriptive image alternatives, and AVIF/WebP negotiation improve discoverability without inventing ratings or public availability. Store links stay hidden until a public listing exists. The existing production sitemap was submitted in Search Console; on 7 September 2026 it reported **Success**, with five pages discovered. This does not establish indexing or ranking. The enhanced sitemap and metadata in this branch take effect after its PR is merged and deployed.
