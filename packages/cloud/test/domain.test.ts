import { describe, expect, it } from "vitest";
import {
  effectiveOffsets,
  mergeBlocks,
  stableId,
  urgentChanges,
} from "../src/domain.ts";
import { eventRow, googleFailure } from "../src/google.ts";
import {
  mutationSchema,
  type Json,
  type Preference,
  type Row,
} from "../src/contracts.ts";

const source: Json = {
  id: "source",
  available: true,
  calendarId: "shared",
  name: "Shared calendar",
};
const pref = (
  kind: Preference["kind"],
  targetId: string,
  value: Json,
): Preference => ({
  key: stableId([kind, targetId]),
  kind,
  targetId,
  value,
  owner: "source",
  version: 1,
  revision: 1,
  deleted: false,
});
const entry: Json = {
  id: "occurrence",
  kind: "event",
  sourceId: "source",
  providerId: "event",
  seriesId: "series",
  start: "2026-09-05T15:00:00.000Z",
  end: "2026-09-05T15:30:00.000Z",
};

describe("reminder rules used by urgent cloud changes", () => {
  it("a 3 PM meeting has 2:50 and 2:55 reminders", () => {
    const minutes = effectiveOffsets(entry, source, [
      pref("source", "source", { mode: "alarm" }),
    ]);
    expect(
      minutes.map((m) =>
        new Date(+new Date(String(entry.start)) - m * 60000).toISOString(),
      ),
    ).toEqual(["2026-09-05T14:50:00.000Z", "2026-09-05T14:55:00.000Z"]);
  });
  it("resolves occurrence, series, calendar, app and explicit disable", () => {
    const rules = [
      pref("settings", "main", { minutes: [20] }),
      pref("source", "source", { mode: "alarm", reminderMinutes: [15] }),
      pref("override", stableId(["source", "series"]), { minutes: [10] }),
      pref("override", "occurrence", { minutes: [] }),
    ];
    expect(effectiveOffsets(entry, source, rules)).toEqual([]);
    expect(effectiveOffsets(entry, source, rules.slice(0, 3))).toEqual([10]);
    expect(effectiveOffsets(entry, source, rules.slice(0, 2))).toEqual([15]);
    expect(
      effectiveOffsets(entry, source, [
        rules[0],
        pref("source", "source", { mode: "alarm" }),
      ]),
    ).toEqual([20]);
    expect(
      effectiveOffsets(entry, source, [
        pref("source", "source", { mode: "showOnly" }),
      ]),
    ).toEqual([]);
  });
  it("busy blocks ignore occurrence overrides and all-day/declined events stay silent", () => {
    const rules = [
      pref("source", "source", { mode: "alarm" }),
      pref("override", "occurrence", { minutes: [1] }),
    ];
    expect(effectiveOffsets({ ...entry, kind: "busy" }, source, rules)).toEqual(
      [10, 5],
    );
    expect(
      effectiveOffsets({ ...entry, allDayDate: "2026-09-05" }, source, rules),
    ).toEqual([]);
    expect(
      effectiveOffsets({ ...entry, declined: true }, source, rules),
    ).toEqual([]);
  });
  it("travel and a DST boundary preserve UTC instants", () => {
    const event = eventRow(
      {
        id: "meeting",
        start: { dateTime: "2026-11-01T01:30:00-05:00" },
        end: { dateTime: "2026-11-01T02:00:00-05:00" },
      },
      source,
      "watcher@example.com",
    )!;
    expect(event.data.start).toBe("2026-11-01T06:30:00.000Z");
    expect(
      new Date(+new Date(String(event.data.start)) - 10 * 60000).toISOString(),
    ).toBe("2026-11-01T06:20:00.000Z");
  });
  it("only moved/canceled timed events with upcoming alarms produce generic notices", () => {
    const before: Row[] = [{ id: "occurrence", data: entry }];
    const rules = [pref("source", "source", { mode: "alarm" })];
    expect(
      urgentChanges(
        before,
        [],
        source,
        rules,
        new Date("2026-09-05T14:00:00Z"),
      ),
    ).toHaveLength(1);
    expect(
      urgentChanges(
        before,
        before,
        source,
        rules,
        new Date("2026-09-05T14:00:00Z"),
      ),
    ).toHaveLength(0);
    expect(
      urgentChanges(
        before,
        [],
        source,
        rules,
        new Date("2026-09-05T10:00:00Z"),
      ),
    ).toHaveLength(0);
    expect(
      urgentChanges(
        before,
        [],
        source,
        [...rules, pref("settings", "main", { urgentNotices: false })],
        new Date("2026-09-05T14:00:00Z"),
      ),
    ).toHaveLength(0);
  });
});

describe("Google visibility and availability", () => {
  it("keeps a private watched event when the user is absent from attendees", () => {
    const row = eventRow(
      {
        id: "event",
        start: { dateTime: "2026-09-05T15:00:00Z" },
        end: { dateTime: "2026-09-05T16:00:00Z" },
        attendees: [
          {
            email: "owner@example.com",
            self: true,
            responseStatus: "declined",
          },
        ],
      },
      source,
      "watcher@example.com",
    )!;
    expect(row.data.title).toBe("Private event");
    expect(row.data.declined).toBe(false);
    expect(row.data.joinUrl).toBeNull();
  });
  it("merges overlapping and adjacent busy windows without inventing meeting identities", () => {
    expect(
      mergeBlocks([
        { start: "2026-09-05T10:00:00Z", end: "2026-09-05T11:00:00Z" },
        { start: "2026-09-05T10:30:00Z", end: "2026-09-05T12:00:00Z" },
        { start: "2026-09-05T12:00:00Z", end: "2026-09-05T12:30:00Z" },
      ]),
    ).toEqual([
      { start: "2026-09-05T10:00:00.000Z", end: "2026-09-05T12:30:00.000Z" },
    ]);
  });
  it("does not treat rate limits as loss of access", () => {
    expect(
      googleFailure({
        response: {
          status: 403,
          data: { error: { errors: [{ reason: "rateLimitExceeded" }] } },
        },
      }).reason,
    ).toBe("transient");
    expect(googleFailure({ response: { status: 410 } }).reason).toBe("cursor");
  });
  it("rejects excessive offsets and unexpected preference fields", () => {
    expect(
      mutationSchema.safeParse({
        mutationId: "69c54174-7ae1-420c-9d52-91695566a24f",
        baseVersion: 0,
        patch: {
          kind: "settings",
          targetId: "main",
          value: { minutes: [40321] },
        },
      }).success,
    ).toBe(false);
    expect(
      mutationSchema.safeParse({
        mutationId: "69c54174-7ae1-420c-9d52-91695566a24f",
        baseVersion: 0,
        patch: { kind: "settings", targetId: "main", value: { admin: true } },
      }).success,
    ).toBe(false);
  });
});
