import {
  createHash,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";
import {
  ApiError,
  type Json,
  type Mutation,
  type Preference,
  type Row,
} from "./contracts.ts";
import { preferenceKey, stableId, urgentChanges } from "./domain.ts";
import {
  GoogleFailure,
  GoogleGateway,
  PageCache,
  RetryJob,
  googleFailure,
} from "./google.ts";
import { required, type Job, type Runtime } from "./runtime.ts";
import type { AccountGrant, Guard } from "./store.ts";

export class CloudService {
  constructor(readonly rt: Runtime) {}
  get store() {
    return this.rt.store;
  }
  async requestSync(
    uid: string,
    accountId?: string,
    id: string = randomUUID(),
  ) {
    const grants = accountId
      ? [await this.store.grant(uid, accountId)]
      : await this.store.grants(uid);
    for (const grant of grants)
      if (grant?.state === "active")
        await this.rt.enqueue({
          id: stableId([id, grant.id]),
          uid,
          accountId: grant.id,
          type: "sync",
          requestedAt: new Date().toISOString(),
        });
  }
  async beginLink(uid: string, expectedAccountId: string) {
    await this.store.rateLimit(uid, "authorization", 10, 3600);
    const attemptId = randomUUID();
    await this.store
      .user(uid)
      .collection("authorizations")
      .doc(attemptId)
      .create({
        expectedAccountId,
        expiresAt: new Date(Date.now() + 10 * 60000),
        state: "ready",
      });
    return { attemptId };
  }
  async link(
    uid: string,
    input: { code: string; expectedAccountId: string; attemptId: string },
  ) {
    const ref = this.store
      .user(uid)
      .collection("authorizations")
      .doc(input.attemptId);
    const completed = await this.store.db.runTransaction(async (tx) => {
      await this.store.guard(tx, uid);
      const attempt = (await tx.get(ref)).data();
      if (
        !attempt ||
        attempt.expectedAccountId !== input.expectedAccountId ||
        attempt.expiresAt.toMillis() < Date.now()
      )
        throw new ApiError(
          400,
          "authorization_expired",
          "Start Google authorization again.",
        );
      if (attempt.state === "complete") return true;
      if (attempt.state !== "ready")
        throw new ApiError(
          409,
          "authorization_used",
          "Start Google authorization again.",
        );
      tx.update(ref, { state: "processing" });
      return false;
    });
    if (completed) return { accountId: input.expectedAccountId };
    const oauth = await this.rt.oauth();
    let tokens;
    try {
      tokens = (await oauth.getToken(input.code)).tokens;
    } catch {
      throw new ApiError(
        400,
        "authorization_failed",
        "Google authorization expired. Connect this account again.",
      );
    }
    oauth.setCredentials(tokens);
    const response = await oauth.request<{
      sub: string;
      email: string;
      name?: string;
      email_verified?: boolean;
    }>({
      url: "https://www.googleapis.com/oauth2/v3/userinfo",
      timeout: 30000,
    });
    const user = response.data;
    if (user.sub !== input.expectedAccountId || !user.email_verified)
      throw new ApiError(
        403,
        "account_mismatch",
        "Choose the same Google account when connecting.",
      );
    const previous = await this.store.grant(uid, user.sub);
    const refresh = tokens.refresh_token;
    if (!refresh && (!previous?.encryptedToken || previous.state !== "active"))
      throw new ApiError(
        400,
        "offline_access_required",
        "Reconnect and allow ongoing access to synchronize this account.",
      );
    const scopes =
      tokens.scope?.split(" ") ??
      (tokens.access_token
        ? (await oauth.getTokenInfo(tokens.access_token)).scopes
        : []);
    if (
      !scopes.includes("https://www.googleapis.com/auth/calendar.readonly") &&
      !scopes.includes("https://www.googleapis.com/auth/tasks")
    )
      throw new ApiError(
        400,
        "scope_required",
        "Allow Calendar or Tasks access to connect this account.",
      );
    const grant: AccountGrant = {
      id: user.sub,
      email: user.email,
      name: user.name ?? user.email,
      encryptedToken: refresh
        ? await this.rt.encrypt(refresh)
        : previous!.encryptedToken,
      scopes,
      generation: randomUUID(),
      state: "active",
      updatedAt: new Date().toISOString(),
    };
    await this.store.saveGrant(uid, grant);
    await ref.update({ state: "complete" });
    await this.publishAccounts(uid);
    await this.requestSync(uid, grant.id);
    return { accountId: grant.id };
  }
  async publishAccounts(uid: string) {
    const accounts = (await this.store.grants(uid)).filter(
      (g) => g.state !== "removed",
    );
    const rows = await Promise.all(
      accounts.map(async (g) => {
        const health = (
          await this.store.user(uid).collection("syncHealth").doc(g.id).get()
        ).data();
        return {
          id: g.id,
          data: {
            id: g.id,
            email: g.email,
            name: g.name,
            error:
              g.state === "reconnect"
                ? "Reconnect this Google account."
                : (health?.lastError ?? null),
            lastServerSync: health?.lastAttempt ?? null,
          },
        };
      }),
    );
    await this.store.publish(uid, "account", "main", rows);
  }
  async accountGuard(uid: string, accountId: string): Promise<Guard> {
    const grant = await this.store.grant(uid, accountId);
    if (!grant || grant.state !== "active")
      throw new ApiError(
        409,
        "account_unavailable",
        "Reconnect this Google account first.",
      );
    return { accountId, generation: grant.generation };
  }
  async mutate(uid: string, mutation: Mutation) {
    const patch = mutation.patch;
    let owner = "main",
      guard: Guard | undefined;
    if (patch.kind !== "settings") {
      let row: Row | undefined;
      if (patch.kind === "source")
        row = await this.store.find(uid, "source", patch.targetId);
      if (patch.kind === "taskList")
        row = await this.store.find(uid, "taskList", patch.targetId);
      if (patch.kind === "taskAlarm") {
        const task = await this.store.find(uid, "task", patch.targetId);
        if (task)
          row = await this.store.find(
            uid,
            "taskList",
            String(task.data.listId),
          );
      }
      if (patch.kind === "override") {
        const existing = (await this.store.preferences(uid)).find(
          (p) => p.key === preferenceKey("override", patch.targetId),
        );
        const sourceId = patch.value?.sourceId ?? existing?.owner;
        if (sourceId) row = await this.store.find(uid, "source", sourceId);
        if (row) {
          if (row.data.accessRole === "freeBusyReader")
            throw new ApiError(
              400,
              "busy_override",
              "Busy blocks use calendar defaults.",
            );
          const entries = await this.store.rows(uid, "entry", row.id);
          if (
            patch.value &&
            !entries.some(
              (e) =>
                e.id === patch.targetId ||
                (e.data.seriesId &&
                  stableId([row!.id, e.data.seriesId]) === patch.targetId),
            )
          )
            throw new ApiError(
              404,
              "event_missing",
              "Refresh before changing this event.",
            );
        }
      }
      if (!row)
        throw new ApiError(
          404,
          "source_missing",
          "This source is no longer available.",
        );
      owner = row.id;
      guard = await this.accountGuard(uid, String(row.data.accountId));
      if (
        patch.kind === "source" &&
        patch.value.mode !== undefined &&
        patch.value.mode !== "off" &&
        !row.data.available
      )
        throw new ApiError(
          409,
          "source_unavailable",
          "Restore calendar access first.",
        );
    }
    const result = await this.store.mutate(uid, mutation, owner, guard);
    const latest = (await this.store.preferences(uid)).find(
      (p) => p.key === result.key,
    );
    if (latest?.version !== result.version) return result;
    if (patch.kind === "source" && patch.value.mode !== undefined) {
      // A mode switch invalidates the previous fetched content; an in-flight
      // worker holding an older preference version cannot publish it again.
      await this.store.publish(uid, "entry", patch.targetId, [], {
        guard: {
          ...guard!,
          preference: { key: result.key, version: result.version },
        },
      });
    }
    if (patch.kind === "taskList" && !patch.value.selected) {
      await this.store.publish(uid, "task", patch.targetId, [], {
        guard: {
          ...guard!,
          preference: { key: result.key, version: result.version },
        },
      });
    }
    if (guard && patch.kind === "source" && patch.value.mode === "off")
      await this.stopWatches(uid, guard.accountId, patch.targetId);
    if (guard)
      await this.requestSync(uid, guard.accountId, mutation.mutationId);
    await this.rt.push(uid, (await this.store.manifest(uid)).revision);
    return result;
  }
  async removeAccount(uid: string, id: string) {
    const grant = await this.store.grant(uid, id);
    if (!grant) return;
    await this.store.saveGrant(uid, {
      ...grant,
      state: "removed",
      generation: randomUUID(),
      encryptedToken: "",
      email: "",
      name: "",
    });
    const sources = [
      ...(await this.store.rows(uid, "source", id)),
      ...(await this.store.rows(uid, "taskList", id)),
    ];
    for (const source of sources) {
      await this.store.publish(
        uid,
        source.data.calendarId ? "entry" : "task",
        source.id,
        [],
        { deleted: true },
      );
    }
    await this.store.publish(uid, "source", id, [], { deleted: true });
    await this.store.publish(uid, "taskList", id, [], { deleted: true });
    await this.store.removePreferences(uid, new Set(sources.map((s) => s.id)));
    await this.stopWatches(uid, id, undefined, grant);
    if (grant.encryptedToken) {
      try {
        await (
          await this.rt.oauth()
        ).revokeToken(await this.rt.decrypt(grant.encryptedToken));
      } catch {
        /* Revocation may already have happened. */
      }
    }
    await this.publishAccounts(uid);
    await this.rt.push(uid, (await this.store.manifest(uid)).revision);
  }
  async complete(uid: string, taskId: string, mutationId: string) {
    const task = await this.store.find(uid, "task", taskId);
    if (!task)
      throw new ApiError(
        404,
        "task_missing",
        "This task is no longer available.",
      );
    const list = await this.store.find(
      uid,
      "taskList",
      String(task.data.listId),
    );
    if (!list)
      throw new ApiError(
        404,
        "list_missing",
        "This task list is no longer available.",
      );
    await this.accountGuard(uid, String(list.data.accountId));
    await this.rt.enqueue({
      id: mutationId,
      uid,
      accountId: String(list.data.accountId),
      taskId,
      mutationId,
      type: "complete",
      requestedAt: new Date().toISOString(),
    });
    return { pending: true };
  }
  async stopWatches(
    uid: string,
    accountId?: string,
    sourceId?: string,
    previousGrant?: AccountGrant,
  ) {
    let query = this.store.db.collection("watches").where("uid", "==", uid);
    if (accountId) query = query.where("accountId", "==", accountId);
    if (sourceId) query = query.where("sourceId", "==", sourceId);
    for (const watch of (await query.get()).docs) {
      const data = watch.data();
      const grant =
        previousGrant ?? (await this.store.grant(uid, data.accountId));
      try {
        if (grant?.encryptedToken) {
          const oauth = await this.rt.oauth();
          oauth.setCredentials({
            refresh_token: await this.rt.decrypt(grant.encryptedToken),
          });
          await new GoogleGateway(
            oauth,
            new PageCache(this.store.db, uid, Date.now() + 180000),
            randomUUID(),
          ).calendar.channels.stop(
            { requestBody: { id: watch.id, resourceId: data.resourceId } },
            { timeout: 10000 },
          );
        }
      } catch {
        /* Reject any remaining callbacks locally until Google's channel expires. */
      }
      await watch.ref.delete();
    }
  }
  async watch(
    uid: string,
    grant: AccountGrant,
    gateway: GoogleGateway,
    source?: Json,
  ) {
    const key = stableId([uid, grant.id, source?.id ?? "calendarList"]);
    const existing = await this.store.db
      .collection("watches")
      .where("key", "==", key)
      .get();
    if (
      existing.docs.some(
        (d) =>
          d.data().expires > Date.now() + 86400000 &&
          d.data().generation === grant.generation,
      )
    )
      return;
    const id = randomUUID(),
      token = randomBytes(32).toString("hex");
    const ref = this.store.db.collection("watches").doc(id);
    await ref.create({
      key,
      uid,
      accountId: grant.id,
      generation: grant.generation,
      sourceId: source?.id ?? null,
      tokenHash: createHash("sha256").update(token).digest("hex"),
      resourceId: null,
      expires: Date.now() + 300000,
    });
    try {
      const requestBody = {
        id,
        token,
        type: "web_hook",
        address: `${this.rt.origin}/api/webhooks/google/calendar`,
        params: { ttl: "604800" },
      };
      const response = source
        ? await gateway.calendar.events.watch(
            { calendarId: String(source.calendarId), requestBody },
            { timeout: 30000 },
          )
        : await gateway.calendar.calendarList.watch(
            { requestBody },
            { timeout: 30000 },
          );
      if (!response.data.resourceId || !response.data.expiration)
        throw new GoogleFailure("other");
      await ref.update({
        resourceId: response.data.resourceId,
        expires: Number(response.data.expiration),
      });
    } catch (e) {
      await ref.delete();
      throw e;
    }
  }
  async webhook(request: Request) {
    const id = request.headers.get("x-goog-channel-id") ?? "";
    if (!/^[a-f0-9-]{36}$/.test(id))
      throw new ApiError(403, "invalid_channel", "Invalid notification.");
    const channel = (
      await this.store.db.collection("watches").doc(id).get()
    ).data();
    const token = request.headers.get("x-goog-channel-token") ?? "";
    const received = createHash("sha256").update(token).digest();
    if (
      !channel ||
      !timingSafeEqual(received, Buffer.from(channel.tokenHash, "hex")) ||
      channel.expires < Date.now()
    )
      throw new ApiError(403, "invalid_channel", "Invalid notification.");
    if (
      channel.resourceId &&
      channel.resourceId !== request.headers.get("x-goog-resource-id")
    )
      throw new ApiError(403, "invalid_resource", "Invalid notification.");
    if (
      !channel.resourceId &&
      request.headers.get("x-goog-resource-state") !== "sync"
    )
      throw new ApiError(
        403,
        "channel_pending",
        "Notification channel is still being registered.",
      );
    const grant = await this.store.grant(channel.uid, channel.accountId);
    if (
      !grant ||
      grant.generation !== channel.generation ||
      grant.state !== "active"
    )
      return;
    const message = request.headers.get("x-goog-message-number");
    if (!message || !/^\d{1,30}$/.test(message))
      throw new ApiError(400, "invalid_message", "Invalid notification.");
    await this.requestSync(
      channel.uid,
      channel.accountId,
      stableId([id, message]),
    );
  }
  async run(job: Job) {
    if (job.type === "delete") return this.deleteUser(job.uid);
    if ((await this.store.user(job.uid).get()).data()?.state !== "active")
      return;
    const lease = randomUUID();
    if (!(await this.store.acquireJob(job.uid, job.id, lease))) {
      const state = (
        await this.store.user(job.uid).collection("jobs").doc(job.id).get()
      ).data();
      if (state?.done) return;
      throw new RetryJob();
    }
    const lock = `account-${job.accountId}`,
      accountLease = randomUUID();
    let acquired = false,
      done = false;
    try {
      acquired = await this.store.acquireJob(job.uid, lock, accountLease);
      if (!acquired) throw new RetryJob();
      const grant = await this.store.grant(job.uid, job.accountId!);
      if (!grant || grant.state !== "active") {
        done = true;
        return;
      }
      const oauth = await this.rt.oauth();
      oauth.setCredentials({
        refresh_token: await this.rt.decrypt(grant.encryptedToken),
      });
      const gateway = new GoogleGateway(
        oauth,
        new PageCache(this.store.db, job.uid, Date.now() + 180000, {
          accountId: grant.id,
          generation: grant.generation,
        }),
        `${job.id}-${grant.generation}`,
      );
      if (job.type === "complete") await this.applyCompletion(job, gateway);
      await this.syncAccount(job, grant, gateway);
      done = true;
    } catch (e) {
      if (e instanceof GoogleFailure && e.reason === "reconnect") {
        const grant = await this.store.grant(job.uid, job.accountId!);
        if (grant?.state === "active") {
          await this.store.saveGrant(job.uid, { ...grant, state: "reconnect" });
          for (const source of await this.store.rows(
            job.uid,
            "source",
            grant.id,
          ))
            await this.store.publish(job.uid, "entry", source.id, [], {
              invalidate: true,
              error: "Reconnect this Google account.",
            });
          for (const list of await this.store.rows(
            job.uid,
            "taskList",
            grant.id,
          ))
            await this.store.publish(job.uid, "task", list.id, [], {
              invalidate: true,
              error: "Reconnect this Google account.",
            });
          await this.publishAccounts(job.uid);
          await this.rt.push(
            job.uid,
            (await this.store.manifest(job.uid)).revision,
          );
        }
        done = true;
      } else if (
        e instanceof ApiError &&
        ["account_deleted", "stale_job"].includes(e.code)
      )
        done = true;
      else throw e;
    } finally {
      if (acquired)
        await this.store.finishJob(job.uid, lock, accountLease, false);
      await this.store.finishJob(job.uid, job.id, lease, done);
      if (done)
        await this.store.db
          .collection("dispatches")
          .doc(job.id)
          .set(
            { state: "done", expiresAt: new Date(Date.now() + 7 * 86400000) },
            { merge: true },
          );
    }
  }
  async applyCompletion(job: Job, gateway: GoogleGateway) {
    const ref = this.store
      .user(job.uid)
      .collection("taskOperations")
      .doc(job.id);
    let operation = (await ref.get()).data();
    if (operation?.state === "complete" || operation?.state === "failed")
      return;
    const task = await this.store.find(job.uid, "task", job.taskId!);
    const list =
      task &&
      (await this.store.find(job.uid, "taskList", String(task.data.listId)));
    const save = async (state: Json) =>
      this.store.db.runTransaction(async (tx) => {
        await this.store.guard(
          tx,
          job.uid,
          await this.accountGuard(job.uid, job.accountId!),
        );
        tx.set(
          ref,
          { ...state, expiresAt: new Date(Date.now() + 30 * 86400000) },
          { merge: true },
        );
      });
    if (!task || !list) {
      await save({
        state: "failed",
        message: "This task is no longer available.",
      });
      return;
    }
    const args = {
      tasklist: String(list.data.providerId),
      task: String(task.data.providerId),
    };
    try {
      const current = (await gateway.tasks.tasks.get(args, { timeout: 30000 }))
        .data;
      if (current.status === "completed") {
        await save({ state: "complete" });
        return;
      }
      if (!operation) {
        if (!current.etag) throw new GoogleFailure("other");
        operation = { state: "pending", etag: current.etag };
        await save(operation);
      }
      // A replay uses the original ETag. It cannot re-complete a task that a
      // user edited or reopened after an earlier attempt reached Google.
      await gateway.tasks.tasks.patch(
        { ...args, requestBody: { status: "completed" } },
        { timeout: 30000, headers: { "If-Match": String(operation.etag) } },
      );
      await save({ state: "complete" });
    } catch (error) {
      const status = (error as { response?: { status?: number } }).response
        ?.status;
      if (status === 412 || status === 404) {
        await save({
          state: "failed",
          message:
            status === 412
              ? "This task changed in Google. Refresh and try completing it again."
              : "This task is no longer available.",
        });
      } else throw googleFailure(error);
    }
  }
  async maintenance(deadline = Date.now() + 150000) {
    // TTL does not delete child collections. Explicitly remove superseded
    // snapshots and resumable pages after 24 hours, including abandoned writes.
    for (const user of (await this.store.db.collection("users").get()).docs) {
      for (const stage of (await user.ref.collection("staging").get()).docs) {
        if (Date.now() > deadline) throw new RetryJob();
        if (stage.data().createdAt?.toMillis() < Date.now() - 86400000)
          await this.store.deleteTree(stage.ref);
      }
      for (const collection of (await user.ref.collection("collections").get())
        .docs) {
        for (const version of (
          await collection.ref.collection("versions").get()
        ).docs) {
          if (Date.now() > deadline) throw new RetryJob();
          if (
            version.id !== collection.data().generation &&
            version.data().createdAt?.toMillis() < Date.now() - 86400000
          )
            await this.store.deleteTree(version.ref);
        }
      }
    }
    for (const watch of (
      await this.store.db
        .collection("watches")
        .where("expires", "<", Date.now())
        .get()
    ).docs)
      await watch.ref.delete();
  }
  async syncAccount(job: Job, grant: AccountGrant, gateway: GoogleGateway) {
    const uid = job.uid,
      now = new Date(job.requestedAt);
    const guard: Guard = { accountId: grant.id, generation: grant.generation };
    let preferences = await this.store.preferences(uid);
    const pref = (kind: string, id: string) =>
      preferences.find((p) => p.key === preferenceKey(kind, id) && !p.deleted);
    const errors: string[] = [],
      urgent: string[] = [];
    const fail = async (e: unknown, kind: "entry" | "task", owner: string) => {
      if (e instanceof RetryJob || e instanceof ApiError) throw e;
      const error = googleFailure(e);
      if (error.reason === "reconnect") throw error;
      errors.push(error.message);
      await this.store.publish(
        uid,
        kind,
        owner,
        error.reason === "access"
          ? []
          : await this.store.rows(uid, kind, owner),
        {
          guard: {
            ...guard,
            ...(pref(kind === "entry" ? "source" : "taskList", owner)
              ? {
                  preference: {
                    key: pref(kind === "entry" ? "source" : "taskList", owner)!
                      .key,
                    version: pref(
                      kind === "entry" ? "source" : "taskList",
                      owner,
                    )!.version,
                  },
                }
              : {}),
          },
          invalidate: error.reason === "access",
          error: error.message,
        },
      );
    };
    if (
      grant.scopes.includes("https://www.googleapis.com/auth/calendar.readonly")
    ) {
      try {
        const sources = await gateway.calendars(grant);
        const previous = await this.store.rows(uid, "source", grant.id);
        for (const old of previous) {
          const fresh = sources.find((s) => s.id === old.id);
          const lost = !fresh || fresh.data.accessRole === "none";
          const downgraded =
            fresh?.data.accessRole === "freeBusyReader" &&
            old.data.accessRole !== "freeBusyReader";
          if (lost || downgraded) {
            const existing = pref("source", old.id);
            if (existing?.value.mode !== "off")
              await this.store.mutate(
                uid,
                {
                  mutationId: randomUUID(),
                  baseVersion: existing?.version ?? 0,
                  patch: {
                    kind: "source",
                    targetId: old.id,
                    value: { mode: "off" },
                  },
                },
                old.id,
                guard,
              );
            await this.store.publish(uid, "entry", old.id, [], {
              guard,
              deleted: lost,
            });
          }
        }
        await this.store.publish(uid, "source", grant.id, sources, {
          guard,
          fetched: true,
        });
        preferences = await this.store.preferences(uid);
        const enabled = sources.filter((s) =>
          ["showOnly", "alarm"].includes(
            String(pref("source", s.id)?.value.mode),
          ),
        );
        for (const source of enabled.filter(
          (s) => s.data.accessRole !== "freeBusyReader",
        )) {
          const selection = pref("source", source.id)!;
          const sourceGuard = {
            ...guard,
            preference: { key: selection.key, version: selection.version },
          };
          try {
            const current = await this.store.collection(
              uid,
              "entry",
              source.id,
            );
            const before = await this.store.rows(uid, "entry", source.id);
            const result = await gateway.events(
              grant,
              source.data,
              before,
              current?.checkpoint ?? {},
              now,
            );
            const published = await this.store.publish(
              uid,
              "entry",
              source.id,
              result.rows,
              {
                guard: sourceGuard,
                checkpoint: result.checkpoint,
                fetched: true,
                urgentKeys: urgentChanges(
                  before,
                  result.rows,
                  source.data,
                  preferences,
                  new Date(),
                ),
              },
            );
            if (published.changed)
              urgent.push(
                ...urgentChanges(
                  before,
                  result.rows,
                  source.data,
                  preferences,
                  new Date(),
                ),
              );
            await this.watch(uid, grant, gateway, source.data);
          } catch (e) {
            await fail(e, "entry", source.id);
          }
        }
        const busy = enabled.filter(
          (s) => s.data.accessRole === "freeBusyReader",
        );
        if (busy.length) {
          const blocks = await gateway.busy(
            busy.map((s) => s.data),
            now,
          );
          for (const source of busy) {
            const result = blocks.get(source.id)!;
            if (result instanceof GoogleFailure) {
              await fail(result, "entry", source.id);
              continue;
            }
            const selection = pref("source", source.id)!;
            await this.store.publish(uid, "entry", source.id, result, {
              fetched: true,
              guard: {
                ...guard,
                preference: { key: selection.key, version: selection.version },
              },
            });
          }
        }
        await this.watch(uid, grant, gateway);
      } catch (e) {
        if (
          e instanceof RetryJob ||
          e instanceof ApiError ||
          (e instanceof GoogleFailure && e.reason === "reconnect")
        )
          throw e;
        errors.push("Calendar discovery needs another refresh.");
      }
    }
    if (grant.scopes.includes("https://www.googleapis.com/auth/tasks")) {
      try {
        const lists = await gateway.taskLists(grant);
        for (const old of await this.store.rows(uid, "taskList", grant.id))
          if (!lists.some((l) => l.id === old.id))
            await this.store.publish(uid, "task", old.id, [], {
              guard,
              deleted: true,
            });
        await this.store.publish(uid, "taskList", grant.id, lists, {
          guard,
          fetched: true,
        });
        for (const list of lists.filter(
          (l) => pref("taskList", l.id)?.value.selected,
        )) {
          try {
            const selection = pref("taskList", list.id)!;
            await this.store.publish(
              uid,
              "task",
              list.id,
              await gateway.taskItems(list.data, now),
              {
                fetched: true,
                guard: {
                  ...guard,
                  preference: {
                    key: selection.key,
                    version: selection.version,
                  },
                },
              },
            );
          } catch (e) {
            await fail(e, "task", list.id);
          }
        }
      } catch (e) {
        if (
          e instanceof RetryJob ||
          e instanceof ApiError ||
          (e instanceof GoogleFailure && e.reason === "reconnect")
        )
          throw e;
        errors.push("Task discovery needs another refresh.");
      }
    }
    await this.store.db.runTransaction(async (tx) => {
      await this.store.guard(tx, uid, guard);
      const ref = this.store.user(uid).collection("syncHealth").doc(grant.id);
      const old = await tx.get(ref);
      const failures = errors.length
        ? Number(old.data()?.failures ?? 0) + 1
        : 0;
      tx.set(ref, {
        lastAttempt: new Date().toISOString(),
        lastError: errors[0] ?? null,
        failures,
        nextAt: new Date(
          Date.now() +
            (failures ? Math.min(60, 5 * 2 ** Math.min(failures - 1, 4)) : 15) *
              60000,
        ),
        accountId: grant.id,
        uid,
      });
    });
    await this.publishAccounts(uid);
    await this.rt.push(uid, (await this.store.manifest(uid)).revision, urgent);
  }
  async dispatchDue() {
    if (process.env.NEXTBELL_SYNC_PAUSED === "true") return;
    const pending = await this.store.db
      .collection("dispatches")
      .where("state", "==", "pending")
      .limit(100)
      .get();
    for (const doc of pending.docs) await this.rt.dispatch(doc.data() as Job);
    const users = await this.store.db
      .collection("users")
      .where("state", "==", "active")
      .get();
    for (const user of users.docs)
      for (const grant of await this.store.grants(user.id)) {
        if (grant.state !== "active") continue;
        const health = (
          await user.ref.collection("syncHealth").doc(grant.id).get()
        ).data();
        if (!health?.nextAt || health.nextAt.toMillis() <= Date.now())
          await this.requestSync(
            user.id,
            grant.id,
            stableId([
              "poll",
              user.id,
              grant.id,
              Math.floor(Date.now() / 300000),
            ]),
          );
      }
  }
  async requestDelete(uid: string) {
    const id = randomUUID();
    // The deletion marker and durable job are atomic. Every data publisher checks
    // this marker, so a late refresh cannot recreate a deleted user's content.
    const job: Job = {
      id,
      uid,
      type: "delete",
      requestedAt: new Date().toISOString(),
    };
    await this.store.db.runTransaction(async (tx) => {
      await this.store.guard(tx, uid);
      tx.update(this.store.user(uid), {
        state: "deleting",
        deletedAt: new Date(),
      });
      tx.create(this.store.db.collection("dispatches").doc(id), {
        ...job,
        state: "pending",
        nextAt: new Date(),
      });
    });
    await this.rt.auth.revokeRefreshTokens(uid);
    await this.rt.dispatch(job).catch(() => {});
  }
  async deleteUser(uid: string) {
    const deadline = Date.now() + 150000;
    const state = (await this.store.user(uid).get()).data();
    if (state?.state !== "deleting") return;
    await this.stopWatches(uid);
    for (const grant of await this.store.grants(uid))
      if (grant.encryptedToken) {
        try {
          await (
            await this.rt.oauth()
          ).revokeToken(await this.rt.decrypt(grant.encryptedToken));
        } catch {
          /* Drop unusable credentials too. */
        }
      }
    await this.rt.push(uid, Number(state.revision ?? 0));
    for (const collection of await this.store.user(uid).listCollections()) {
      for (const doc of (await collection.get()).docs) {
        if (Date.now() > deadline) throw new RetryJob();
        await this.store.deleteTree(doc.ref);
      }
    }
    await this.store
      .user(uid)
      .set({ state: "deleted", revision: 0, deletedAt: new Date() });
    try {
      await this.rt.auth.deleteUser(uid);
    } catch (e) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    }
    for (const doc of (
      await this.store.db.collection("dispatches").where("uid", "==", uid).get()
    ).docs)
      await doc.ref.delete();
  }
}
