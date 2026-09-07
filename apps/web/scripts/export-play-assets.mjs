import { createRequire } from "node:module";
import { mkdir, copyFile, stat } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const require = createRequire(import.meta.url);
const sharp = createRequire(require.resolve("next/package.json"))("sharp");
const output = resolve(root, "docs/play-store/assets");
await mkdir(output, { recursive: true });
const assets = [
  ["store-graphics/icon-512.png", "nextbell-icon-512.png"],
  [
    "store-graphics/feature-graphic.png",
    "nextbell-calendar-alarms-feature.png",
  ],
  ["store-screens/today.png", "01-google-calendar-alarms.png"],
  ["store-screens/reminders.png", "02-custom-meeting-reminders.png"],
  ["store-screens/calendars-dark.png", "03-shared-google-calendars.png"],
  ["store-screens/tasks.png", "04-google-tasks-reminders.png"],
  ["store-screens/today-dark.png", "05-calendar-agenda-dark-mode.png"],
];
for (const [source, name] of assets) {
  const dest = resolve(output, name);
  await sharp(resolve(root, "apps/mobile/build", source))
    .removeAlpha()
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(dest);
  const m = await sharp(dest).metadata();
  if (m.hasAlpha || m.width < 512) throw new Error(`Invalid image: ${name}`);
  console.log(
    `${name}: ${m.width}x${m.height}, ${(await stat(dest)).size} bytes`,
  );
}
if (process.env.NEXTBELL_ASSET_OUTPUT) {
  await mkdir(process.env.NEXTBELL_ASSET_OUTPUT, { recursive: true });
  for (const [, name] of assets)
    await copyFile(
      resolve(output, name),
      resolve(process.env.NEXTBELL_ASSET_OUTPUT, name),
    );
}
