import { createHash } from "node:crypto";
import type { Json, Preference, Row } from "./contracts.ts";

export function stableId(parts: unknown[]): string {
  const h = createHash("sha256").update(JSON.stringify(parts)).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}
export const preferenceKey = (kind: string, id: string) => stableId([kind, id]);
export const collectionKey = (kind: string, owner: string) =>
  stableId([kind, owner]);
export const iso = (value: string | number | Date) =>
  new Date(value).toISOString();
export function windowAt(now: Date) {
  return {
    from: new Date(+now - 7 * 86400000),
    to: new Date(+now + 90 * 86400000),
  };
}
export function effectiveOffsets(
  entry: Json,
  source: Json,
  preferences: Preference[],
): number[] {
  const get = (kind: string, id: string) =>
    preferences.find((p) => !p.deleted && p.kind === kind && p.targetId === id)
      ?.value;
  const sourceDefaults = get("source", String(source.id)) ?? {};
  if (
    !source.available ||
    sourceDefaults.mode !== "alarm" ||
    entry.allDayDate ||
    entry.declined
  )
    return [];
  const app = get("settings", "main");
  if (entry.kind === "busy")
    return (sourceDefaults.reminderMinutes ??
      app?.minutes ?? [10, 5]) as number[];
  const occurrence = get("override", String(entry.id));
  const series = entry.seriesId
    ? get("override", stableId([entry.sourceId, entry.seriesId]))
    : undefined;
  return (occurrence?.minutes ??
    series?.minutes ??
    sourceDefaults.reminderMinutes ??
    app?.minutes ?? [10, 5]) as number[];
}
export function urgentChanges(
  before: Row[],
  after: Row[],
  source: Json,
  preferences: Preference[],
  now: Date,
): string[] {
  if (
    preferences.find((p) => p.kind === "settings" && !p.deleted)?.value
      .urgentNotices === false
  )
    return [];
  const changed = new Map(after.map((row) => [row.id, row.data]));
  const keys = new Set<string>();
  for (const { id, data: old } of before) {
    if (old.kind !== "event") continue;
    const current = changed.get(id);
    if (
      current &&
      current.start === old.start &&
      current.end === old.end &&
      current.declined === old.declined
    )
      continue;
    const candidates = [old, ...(current ? [current] : [])];
    if (
      candidates.some((entry) =>
        effectiveOffsets(entry, source, preferences).some((minutes) => {
          const fire = +new Date(String(entry.start)) - minutes * 60000;
          return fire > +now && fire <= +now + 3600000;
        }),
      )
    ) {
      keys.add(
        stableId([
          "change",
          old.iCalUid ?? `${old.calendarId}/${old.providerId}`,
          old.originalStart ?? old.start,
          current?.start ?? "cancelled",
          current?.end ?? null,
        ]),
      );
    }
  }
  return [...keys];
}
export function mergeBlocks(blocks: { start: string; end: string }[]) {
  const merged: { start: string; end: string }[] = [];
  for (const block of blocks
    .filter((b) => +new Date(b.end) > +new Date(b.start))
    .sort((a, b) => +new Date(a.start) - +new Date(b.start))) {
    const previous = merged.at(-1);
    if (previous && +new Date(block.start) <= +new Date(previous.end)) {
      if (+new Date(block.end) > +new Date(previous.end))
        previous.end = iso(block.end);
    } else merged.push({ start: iso(block.start), end: iso(block.end) });
  }
  return merged;
}
