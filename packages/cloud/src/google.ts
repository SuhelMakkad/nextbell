import { calendar_v3 } from "googleapis/build/src/apis/calendar/v3.js";
import { tasks_v1 } from "googleapis/build/src/apis/tasks/v1.js";
import { OAuth2Client } from "google-auth-library";
import type { Firestore } from "firebase-admin/firestore";
import { ApiError, type Json, type Row } from "./contracts.ts";
import { iso, mergeBlocks, stableId, windowAt } from "./domain.ts";
import { CloudStore, type AccountGrant, type Guard } from "./store.ts";

export class RetryJob extends Error {}
export class GoogleFailure extends Error {
  constructor(
    public reason: "transient" | "access" | "reconnect" | "cursor" | "other",
  ) {
    super(
      reason === "reconnect"
        ? "Reconnect this Google account."
        : reason === "access"
          ? "Access to this source is no longer available."
          : "Google could not finish this refresh.",
    );
  }
}
export function googleFailure(error: unknown): GoogleFailure {
  if (error instanceof GoogleFailure) return error;
  const e = error as {
    response?: {
      status?: number;
      data?: { error?: { errors?: { reason?: string }[] } | string };
    };
    code?: number;
  };
  const status = e.response?.status ?? e.code;
  const body = e.response?.data?.error;
  const reasons =
    typeof body === "object" ? (body.errors?.map((e) => e.reason) ?? []) : [];
  if (body === "invalid_grant" || status === 401)
    return new GoogleFailure("reconnect");
  if (status === 410) return new GoogleFailure("cursor");
  if (
    status === 429 ||
    (typeof status === "number" && status >= 500) ||
    reasons.some((r) => r?.toLowerCase().includes("ratelimit"))
  )
    return new GoogleFailure("transient");
  if (status === 404 || (status === 403 && reasons.includes("forbidden")))
    return new GoogleFailure("access");
  return new GoogleFailure("other");
}

// Each Google page and its next cursor commit together. A timed-out worker can
// continue pagination without exposing an incomplete collection to a phone.
export class PageCache {
  constructor(
    readonly db: Firestore,
    readonly uid: string,
    readonly deadline: number,
    readonly guard?: Guard,
  ) {}
  async all<T extends { id?: string | null }>(
    key: unknown[],
    request: (page?: string) => Promise<{
      items?: T[] | null;
      nextPageToken?: string | null;
      nextSyncToken?: string | null;
    }>,
  ): Promise<{ items: T[]; token?: string }> {
    const ref = this.db
      .collection("users")
      .doc(this.uid)
      .collection("staging")
      .doc(stableId(key));
    let state = (await ref.get()).data() ?? {
      index: 0,
      page: null,
      complete: false,
    };
    while (!state.complete) {
      if (Date.now() > this.deadline - 35000)
        throw new RetryJob("Continue this collection in another execution.");
      let result;
      try {
        result = await request(state.page ?? undefined);
      } catch (e) {
        throw googleFailure(e);
      }
      const writes: { ref: FirebaseFirestore.DocumentReference; data: Json }[] =
        [];
      let rows: T[] = [],
        bytes = 0,
        index = Number(state.index);
      const flush = () => {
        if (!rows.length) return;
        writes.push({
          ref: ref.collection("pages").doc(String(index).padStart(8, "0")),
          data: { index, rows },
        });
        index++;
        rows = [];
        bytes = 0;
      };
      for (const item of result.items ?? []) {
        const length = Buffer.byteLength(JSON.stringify(item));
        if (bytes + length > 200000) flush();
        if (length > 800000)
          throw new ApiError(
            502,
            "item_too_large",
            "Google returned an item too large to synchronize.",
          );
        rows.push(item);
        bytes += length;
      }
      flush();
      state = {
        index,
        page: result.nextPageToken ?? null,
        complete: !result.nextPageToken,
        token: result.nextSyncToken ?? null,
        createdAt: new Date(),
      };
      await this.db.runTransaction(async (tx) => {
        await new CloudStore(this.db).guard(tx, this.uid, this.guard);
        for (const write of writes) tx.set(write.ref, write.data);
        tx.set(ref, state);
      });
    }
    const pages = await ref.collection("pages").orderBy("index").get();
    return {
      items: pages.docs.flatMap((d) => d.data().rows as T[]),
      token: state.token ?? undefined,
    };
  }
}

const eventFields =
  "nextPageToken,nextSyncToken,items(id,status,summary,start,end,recurrence,recurringEventId,originalStartTime,iCalUID,description,location,htmlLink,hangoutLink,conferenceData(entryPoints),attendees(email,responseStatus))";
export function eventRow(
  event: calendar_v3.Schema$Event,
  source: Json,
  email: string,
): Row | null {
  if (!event.id || event.status === "cancelled" || !event.start || !event.end)
    return null;
  const start =
    event.start.dateTime ??
    (event.start.date ? `${event.start.date}T00:00:00Z` : null);
  const end =
    event.end.dateTime ??
    (event.end.date ? `${event.end.date}T00:00:00Z` : null);
  if (!start || !end) return null;
  const id = stableId([source.id, event.id]);
  return {
    id,
    data: {
      kind: "event",
      id,
      sourceId: source.id,
      providerId: event.id,
      calendarId: source.calendarId,
      start: iso(start),
      end: iso(end),
      title: event.summary ?? "Private event",
      iCalUid: event.iCalUID ?? null,
      seriesId: event.recurringEventId ?? null,
      originalStart: event.originalStartTime?.dateTime
        ? iso(event.originalStartTime.dateTime)
        : event.originalStartTime?.date
          ? iso(`${event.originalStartTime.date}T00:00:00Z`)
          : null,
      allDayDate: event.start.date ?? null,
      endDate: event.end.date ?? null,
      timeZone: event.start.timeZone ?? null,
      description: event.description ?? null,
      location: event.location ?? null,
      webUrl: event.htmlLink ?? null,
      joinUrl:
        event.conferenceData?.entryPoints?.find(
          (p) => p.entryPointType === "video",
        )?.uri ??
        event.hangoutLink ??
        null,
      declined:
        event.attendees?.some(
          (a) =>
            a.email?.toLowerCase() === email.toLowerCase() &&
            a.responseStatus === "declined",
        ) ?? false,
    },
  };
}

export class GoogleGateway {
  readonly calendar: calendar_v3.Calendar;
  readonly tasks: tasks_v1.Tasks;
  constructor(
    readonly auth: OAuth2Client,
    readonly cache: PageCache,
    readonly jobId: string,
  ) {
    this.calendar = new calendar_v3.Calendar({ auth });
    this.tasks = new tasks_v1.Tasks({ auth });
  }
  async calendars(account: AccountGrant): Promise<Row[]> {
    const result = await this.cache.all(
      ["calendars", account.id, this.jobId],
      async (pageToken) =>
        (
          await this.calendar.calendarList.list(
            { showHidden: true, maxResults: 250, pageToken },
            { timeout: 30000 },
          )
        ).data,
    );
    return result.items
      .filter((c) => c.id && !c.deleted)
      .map((c) => {
        const id = stableId([account.id, c.id]);
        return {
          id,
          data: {
            id,
            accountId: account.id,
            calendarId: c.id!,
            name: c.summaryOverride ?? c.summary ?? "Calendar",
            accessRole: c.accessRole ?? "none",
            color: parseInt(
              (c.backgroundColor ?? "#6658d9").replace("#", "ff"),
              16,
            ),
            primary: c.primary ?? false,
            hidden: c.hidden ?? false,
            available: ["owner", "writer", "reader", "freeBusyReader"].includes(
              c.accessRole ?? "",
            ),
          },
        };
      });
  }
  async events(
    account: AccountGrant,
    source: Json,
    before: Row[],
    checkpoint: Json,
    now: Date,
  ): Promise<{ rows: Row[]; checkpoint: Json }> {
    const window = windowAt(now);
    const calendarId = String(source.calendarId);
    let token = checkpoint.token as string | undefined;
    const reset = !token || checkpoint.day !== now.toISOString().slice(0, 10);
    let rows = before;
    if (!token) {
      // Only metadata is scanned for the initial non-expanded cursor; historical
      // event content is not downloaded or retained outside the agenda window.
      const baseline = await this.cache.all(
        ["baseline", source.id, this.jobId],
        async (pageToken) =>
          (
            await this.calendar.events.list(
              {
                calendarId,
                singleEvents: false,
                showDeleted: true,
                maxResults: 2500,
                pageToken,
                fields: "nextPageToken,nextSyncToken,items(id)",
              },
              { timeout: 30000 },
            )
          ).data,
      );
      token = baseline.token;
      if (!token) throw new GoogleFailure("other");
    }
    if (reset) rows = await this.snapshot(account, source, now);
    let delta;
    try {
      delta = await this.cache.all(
        ["delta", source.id, this.jobId, token],
        async (pageToken) =>
          (
            await this.calendar.events.list(
              {
                calendarId,
                singleEvents: false,
                showDeleted: true,
                syncToken: token,
                maxResults: 2500,
                pageToken,
                fields: eventFields,
              },
              { timeout: 30000 },
            )
          ).data,
      );
    } catch (e) {
      if (
        e instanceof GoogleFailure &&
        e.reason === "cursor" &&
        checkpoint.token
      ) {
        return this.events(account, source, before, {}, now);
      }
      throw e;
    }
    const result = new Map(rows.map((row) => [row.id, row]));
    const series = new Set<string>();
    const canceledMasters = new Set(
      delta.items
        .filter((e) => e.status === "cancelled" && !e.recurringEventId)
        .map((e) => e.id),
    );
    for (const event of delta.items) {
      if (!event.id) continue;
      if (event.recurrence?.length) {
        series.add(event.id);
        continue;
      }
      if (event.recurringEventId) {
        series.add(event.recurringEventId);
        continue;
      }
      // Series cancellation may contain only its id. Remove both the master id
      // and any occurrences belonging to it, including moved exceptions.
      if (event.status === "cancelled") {
        for (const [id, row] of result)
          if (
            row.data.providerId === event.id ||
            row.data.seriesId === event.id
          )
            result.delete(id);
      } else {
        const row = eventRow(event, source, account.email);
        if (row) result.set(row.id, row);
      }
    }
    for (const seriesId of series) {
      if (canceledMasters.has(seriesId)) continue;
      const instances = await this.cache.all(
        ["instances", source.id, seriesId, this.jobId],
        async (pageToken) =>
          (
            await this.calendar.events.instances(
              {
                calendarId,
                eventId: seriesId,
                showDeleted: true,
                timeMin: window.from.toISOString(),
                timeMax: window.to.toISOString(),
                timeZone: "UTC",
                maxResults: 2500,
                pageToken,
                fields: eventFields,
              },
              { timeout: 30000 },
            )
          ).data,
      );
      for (const [id, row] of result)
        if (row.data.seriesId === seriesId) result.delete(id);
      for (const event of instances.items) {
        const row = eventRow(event, source, account.email);
        if (row) result.set(row.id, row);
      }
    }
    return {
      rows: [...result.values()].filter(
        (row) =>
          +new Date(String(row.data.end)) > +window.from &&
          +new Date(String(row.data.start)) < +window.to,
      ),
      checkpoint: {
        token: delta.token ?? token,
        day: now.toISOString().slice(0, 10),
      },
    };
  }
  async snapshot(account: AccountGrant, source: Json, now: Date) {
    const { from, to } = windowAt(now);
    const result = await this.cache.all(
      ["snapshot", source.id, this.jobId],
      async (pageToken) =>
        (
          await this.calendar.events.list(
            {
              calendarId: String(source.calendarId),
              singleEvents: true,
              showDeleted: true,
              timeMin: from.toISOString(),
              timeMax: to.toISOString(),
              timeZone: "UTC",
              maxResults: 2500,
              pageToken,
              fields: eventFields,
            },
            { timeout: 30000 },
          )
        ).data,
    );
    return result.items
      .map((event) => eventRow(event, source, account.email))
      .filter((row): row is Row => !!row);
  }
  async busy(
    sources: Json[],
    now: Date,
  ): Promise<Map<string, Row[] | GoogleFailure>> {
    const { from, to } = windowAt(now);
    const result = new Map<string, Row[] | GoogleFailure>();
    const blocks = new Map(
      sources.map((source) => [
        String(source.id),
        [] as { start: string; end: string }[],
      ]),
    );
    for (let batch = 0; batch < sources.length; batch += 50) {
      const group = sources.slice(batch, batch + 50);
      for (let start = +from; start < +to; start += 30 * 86400000) {
        if (Date.now() > this.cache.deadline - 35000) throw new RetryJob();
        // Cache each successful window as a page; retry retains finished windows.
        const response = await this.cache.all(
          ["busy", group.map((s) => s.id), start, this.jobId],
          async () => {
            const data = (
              await this.calendar.freebusy.query(
                {
                  requestBody: {
                    timeMin: iso(start),
                    timeMax: iso(Math.min(start + 30 * 86400000, +to)),
                    timeZone: "UTC",
                    calendarExpansionMax: 50,
                    items: group.map((s) => ({ id: String(s.calendarId) })),
                  },
                },
                { timeout: 30000 },
              )
            ).data;
            return {
              items: group.map((source) => ({
                id: String(source.id),
                value: data.calendars?.[String(source.calendarId)],
              })),
            };
          },
        );
        for (const source of group) {
          const value = response.items.find((r) => r.id === source.id)?.value;
          if (!value || value.errors?.length) {
            const denied = value?.errors?.some((e) =>
              ["notFound", "forbidden"].includes(e.reason ?? ""),
            );
            result.set(
              String(source.id),
              new GoogleFailure(denied ? "access" : "other"),
            );
          } else
            for (const block of value.busy ?? [])
              if (block.start && block.end)
                blocks
                  .get(String(source.id))!
                  .push({ start: block.start, end: block.end });
        }
      }
    }
    for (const source of sources) {
      if (result.has(String(source.id))) continue;
      result.set(
        String(source.id),
        mergeBlocks(blocks.get(String(source.id))!).map((block) => {
          const id = stableId([source.id, block.start, block.end]);
          return {
            id,
            data: {
              id,
              kind: "busy",
              sourceId: source.id,
              calendarId: source.calendarId,
              calendarName: source.name,
              ...block,
            },
          };
        }),
      );
    }
    return result;
  }
  async taskLists(account: AccountGrant): Promise<Row[]> {
    const result = await this.cache.all(
      ["taskLists", account.id, this.jobId],
      async (pageToken) =>
        (
          await this.tasks.tasklists.list(
            { maxResults: 100, pageToken },
            { timeout: 30000 },
          )
        ).data,
    );
    return result.items
      .filter((list) => list.id)
      .map((list) => {
        const id = stableId([account.id, "tasks", list.id]);
        return {
          id,
          data: {
            id,
            accountId: account.id,
            providerId: list.id!,
            title: list.title ?? "Tasks",
          },
        };
      });
  }
  async taskItems(list: Json, now: Date): Promise<Row[]> {
    const result = await this.cache.all(
      ["tasks", list.id, this.jobId],
      async (pageToken) =>
        (
          await this.tasks.tasks.list(
            {
              tasklist: String(list.providerId),
              maxResults: 100,
              pageToken,
              showCompleted: true,
              showHidden: true,
              showDeleted: true,
            },
            { timeout: 30000 },
          )
        ).data,
    );
    return result.items
      .filter(
        (task) =>
          task.id &&
          !task.deleted &&
          (task.status !== "completed" ||
            (task.completed &&
              +new Date(task.completed) >= +now - 7 * 86400000)),
      )
      .map((task) => {
        const id = stableId([list.id, task.id]);
        return {
          id,
          data: {
            id,
            listId: list.id,
            providerId: task.id!,
            title: task.title ?? "Task",
            notes: task.notes ?? null,
            dueDate: task.due?.slice(0, 10) ?? null,
            completed: task.status === "completed",
            pendingCompletion: false,
          },
        };
      });
  }
}
