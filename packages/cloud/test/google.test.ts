import { OAuth2Client } from "google-auth-library";
import type { Firestore } from "firebase-admin/firestore";
import { describe, expect, it, vi } from "vitest";
import {
  GoogleGateway,
  PageCache,
  GoogleFailure,
  eventRow,
} from "../src/google.ts";
import type { AccountGrant } from "../src/store.ts";

const account: AccountGrant = {
  id: "account",
  email: "owner@example.com",
  name: "",
  state: "active",
  generation: "g",
  scopes: [],
  encryptedToken: "",
  updatedAt: "",
};
const source = {
  id: "s",
  accountId: account.id,
  calendarId: "shared",
  name: "Shared",
};
const now = new Date("2026-09-05T10:00:00Z");
function gateway() {
  const cache = new PageCache({} as Firestore, "u", Date.now() + 180000);
  vi.spyOn(cache, "all").mockImplementation(async (_key, request) => {
    const items = [];
    let page: string | undefined, token: string | undefined;
    do {
      const result = await request(page);
      items.push(...(result.items ?? []));
      page = result.nextPageToken ?? undefined;
      token = result.nextSyncToken ?? undefined;
    } while (page);
    return { items, token };
  });
  return new GoogleGateway(new OAuth2Client(), cache, "job");
}
const meeting = {
  id: "meeting",
  summary: "Planning",
  start: { dateTime: "2026-09-06T15:00:00Z" },
  end: { dateTime: "2026-09-06T16:00:00Z" },
};
describe("Google source synchronization", () => {
  it("paginates hidden, shared and availability calendars with account provenance", async () => {
    const g = gateway();
    const list = vi
      .spyOn(g.calendar.calendarList, "list")
      .mockResolvedValueOnce({
        data: {
          items: [{ id: "shared", accessRole: "reader", hidden: true }],
          nextPageToken: "p2",
        },
      } as never)
      .mockResolvedValueOnce({
        data: {
          items: [
            { id: "busy", accessRole: "freeBusyReader" },
            { id: "lost", accessRole: "none" },
          ],
        },
      } as never);
    const rows = await g.calendars(account);
    expect(rows).toHaveLength(3);
    expect(list.mock.calls[0][0]).toMatchObject({ showHidden: true });
    expect(list.mock.calls[1][0]).toMatchObject({ pageToken: "p2" });
    expect(rows[0].data).toMatchObject({
      accountId: "account",
      hidden: true,
      accessRole: "reader",
      available: true,
    });
    expect(rows[2].data.available).toBe(false);
  });
  it("uses an unbounded non-expanded delta and removes canceled occurrences", async () => {
    const g = gateway(),
      old = eventRow(meeting, source, account.email)!;
    const list = vi
      .spyOn(g.calendar.events, "list")
      .mockResolvedValue({
        data: {
          items: [{ id: meeting.id, status: "cancelled" }],
          nextSyncToken: "next",
        },
      } as never);
    const result = await g.events(
      account,
      source,
      [old],
      { token: "old", day: "2026-09-05" },
      now,
    );
    expect(result.rows).toEqual([]);
    expect(result.checkpoint.token).toBe("next");
    expect(list.mock.calls[0][0]).toMatchObject({
      singleEvents: false,
      showDeleted: true,
      syncToken: "old",
    });
    expect(list.mock.calls[0][0]).not.toHaveProperty("timeMin");
    expect(list.mock.calls[0][0]).not.toHaveProperty("timeMax");
  });
  it("rebuilds an expired cursor before publishing a new snapshot", async () => {
    const g = gateway();
    const list = vi
      .spyOn(g.calendar.events, "list")
      .mockRejectedValueOnce(new GoogleFailure("cursor"))
      .mockResolvedValueOnce({
        data: { items: [{ id: "baseline" }], nextSyncToken: "fresh" },
      } as never)
      .mockResolvedValueOnce({ data: { items: [meeting] } } as never)
      .mockResolvedValueOnce({
        data: { items: [], nextSyncToken: "final" },
      } as never);
    const result = await g.events(
      account,
      source,
      [],
      { token: "expired", day: "2026-09-05" },
      now,
    );
    expect(result.rows).toHaveLength(1);
    expect(result.checkpoint.token).toBe("final");
    expect(list.mock.calls[2][0]).toMatchObject({
      singleEvents: true,
      timeZone: "UTC",
    });
  });
  it("does not refetch a canceled master referenced by an exception in the same delta", async () => {
    const g = gateway();
    const row = eventRow(
      { ...meeting, recurringEventId: "series" },
      source,
      account.email,
    )!;
    vi.spyOn(g.calendar.events, "list").mockResolvedValue({
      data: {
        items: [
          { id: "series", status: "cancelled" },
          { id: "exception", recurringEventId: "series", status: "cancelled" },
        ],
        nextSyncToken: "next",
      },
    } as never);
    const instances = vi.spyOn(g.calendar.events, "instances");
    expect(
      (
        await g.events(
          account,
          source,
          [row],
          { token: "old", day: "2026-09-05" },
          now,
        )
      ).rows,
    ).toEqual([]);
    expect(instances).not.toHaveBeenCalled();
  });
  it("splits availability requests at Google limits and isolates a failed calendar", async () => {
    const g = gateway(),
      sources = Array.from({ length: 51 }, (_, i) => ({
        ...source,
        id: `s${i}`,
        calendarId: `c${i}`,
      }));
    const query = vi
      .spyOn(g.calendar.freebusy, "query")
      .mockImplementation((async (args: {
        requestBody: {
          timeMin: string;
          timeMax: string;
          items: { id: string }[];
        };
      }) => {
        expect(args.requestBody.items.length).toBeLessThanOrEqual(50);
        expect(
          +new Date(args.requestBody.timeMax) -
            +new Date(args.requestBody.timeMin),
        ).toBeLessThanOrEqual(30 * 86400000);
        return {
          data: {
            calendars: Object.fromEntries(
              args.requestBody.items.map((item) => [
                item.id,
                item.id === "c0"
                  ? { errors: [{ reason: "internalError" }] }
                  : { busy: [] },
              ]),
            ),
          },
        };
      }) as never);
    const result = await g.busy(sources, now);
    expect(query).toHaveBeenCalledTimes(8);
    expect(result.get("s0")).toBeInstanceOf(GoogleFailure);
    expect(result.get("s50")).toEqual([]);
  });
});
