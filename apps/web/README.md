# Nextbell website

Publishing website built with Next.js 16.3.4, React, TypeScript, App Router and Tailwind CSS. Use pnpm 11.25.0 and Node 24.18.0 from the repository root.

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm check:web
pnpm build
pnpm test:web
```

The Playwright suite starts a production server on port 3100; build first. Development uses port 3000. Browser binaries: `pnpm --filter @nextbell/web exec playwright install chromium webkit`.

- `src/content`: typed site configuration, privacy, terms, data-removal and support content.
- `src/components`: shared shell, document layout and interactive reminder example.
- `src/app`: routes, metadata, local font, social artwork and responsive motion styles.
- `public`: bundled brand assets, Manrope license and actual Flutter demo screenshots.

Real store listings belong in `src/content/site.ts`; empty listings render no download buttons. Public origin is `https://nextbell.org`. There is no web OAuth client or sign-in flow.

See [website and deployment preparation](../../docs/WEB.md). Deployment and domain configuration are separate later steps.
