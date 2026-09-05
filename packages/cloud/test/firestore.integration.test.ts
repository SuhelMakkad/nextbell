import { CloudService } from "../src/service.ts";
import type { Runtime } from "../src/runtime.ts";
import type { GoogleGateway } from "../src/google.ts";
import { randomUUID } from "node:crypto";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { CloudStore, type AccountGrant } from "../src/store.ts";
import { collectionKey } from "../src/domain.ts";
import { PageCache, RetryJob } from "../src/google.ts";

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
describe.skipIf(!enabled)("Firestore transactions and isolation", () => {
  let store: CloudStore;
  beforeAll(() => {
    if (!getApps().length) initializeApp({ projectId: "demo-nextbell" });
    store = new CloudStore(getFirestore());
  });
  async function user() {
    const uid = randomUUID();
    await store.ensureUser(uid, "beta@example.com");
    return uid;
  }
  it("does not expose one user’s collection through another user", async () => {
    const a = await user(),
      b = await user();
    await store.publish(a, "source", "account", [
      { id: "source", data: { id: "source", title: "Private" } },
    ]);
    expect((await store.manifest(b)).collections).toEqual([]);
    const collection = await store.collection(a, "source", "account");
    await expect(
      store.page(b, collection!.key, collection!.generation),
    ).rejects.toMatchObject({ code: "snapshot_expired" });
  });
  it("keeps old snapshots readable and publishes large collections atomically", async () => {
    const uid = await user();
    await store.publish(uid, "entry", "source", [
      { id: "old", data: { id: "old" } },
    ]);
    const before = await store.collection(uid, "entry", "source");
    await store.publish(
      uid,
      "entry",
      "source",
      Array.from({ length: 550 }, (_, i) => ({
        id: `item-${i}`,
        data: { id: `item-${i}` },
      })),
    );
    expect(
      (await store.page(uid, before!.key, before!.generation)).rows[0].id,
    ).toBe("old");
    const after = await store.collection(uid, "entry", "source");
    expect(after!.count).toBe(550);
    expect(after!.generation).not.toBe(before!.generation);
    const page = await store.page(uid, after!.key, after!.generation);
    expect(page.rows).toHaveLength(200);
    expect(page.next).not.toBeNull();
  });
  it("prevents a worker from resurrecting content after removal or a selection change", async () => {
    const uid = await user();
    const grant: AccountGrant = {
      id: "account",
      email: "",
      name: "",
      encryptedToken: "",
      scopes: [],
      generation: "generation",
      state: "active",
      updatedAt: new Date().toISOString(),
    };
    await store.saveGrant(uid, grant);
    const guard = { accountId: grant.id, generation: grant.generation };
    await store.saveGrant(uid, { ...grant, state: "removed" });
    await expect(
      store.publish(
        uid,
        "entry",
        "source",
        [{ id: "event", data: { id: "event" } }],
        { guard },
      ),
    ).rejects.toMatchObject({ code: "stale_job" });
    expect(await store.collection(uid, "entry", "source")).toBeUndefined();
    await store.user(uid).update({ state: "deleting" });
    await expect(
      store.publish(uid, "entry", "source", []),
    ).rejects.toMatchObject({ code: "account_deleted" });
  });
  it("deduplicates mutations and rejects stale edits without losing other fields", async () => {
    const uid = await user(),
      mutationId = randomUUID();
    const mutation = {
      mutationId,
      baseVersion: 0,
      patch: {
        kind: "settings" as const,
        targetId: "main" as const,
        value: { theme: "dark" as const },
      },
    };
    const first = await store.mutate(uid, mutation, "main");
    expect(await store.mutate(uid, mutation, "main")).toEqual(first);
    await expect(
      store.mutate(uid, { ...mutation, mutationId: randomUUID() }, "main"),
    ).rejects.toMatchObject({ code: "conflict", current: { version: 1 } });
    const next = await store.mutate(
      uid,
      {
        mutationId: randomUUID(),
        baseVersion: 1,
        patch: { kind: "settings", targetId: "main", value: { minutes: [5] } },
      },
      "main",
    );
    expect(next.value).toEqual({ theme: "dark", minutes: [5] });
  });
  it("checkpoints Google pages and resumes after a worker deadline", async () => {
    const uid = await user();
    let calls = 0;
    const key = ["google-pages", randomUUID()];
    const cache = new PageCache(store.db, uid, Date.now() + 40000);
    const result = await cache.all(key, async (page) => {
      calls++;
      return page
        ? { items: [{ id: "second" }], nextSyncToken: "cursor" }
        : { items: [{ id: "first" }], nextPageToken: "page2" };
    });
    expect(result.items).toHaveLength(2);
    expect(calls).toBe(2);
    expect(
      (
        await cache.all(key, async () => {
          throw new Error("Should use completed pages");
        })
      ).token,
    ).toBe("cursor");
    await expect(
      new PageCache(store.db, uid, Date.now()).all(
        ["expired", randomUUID()],
        async () => ({ items: [] }),
      ),
    ).rejects.toBeInstanceOf(RetryJob);
  });
  it("publishes tombstones so a disconnected device removes cached sources", async () => {
    const uid = await user();
    const old = await store.publish(uid, "entry", "source", [
      { id: "event", data: { id: "event" } },
    ]);
    await store.publish(uid, "entry", "source", [], { deleted: true });
    const delta = await store.manifest(uid, old.revision);
    expect(delta.collections).toMatchObject([
      { key: collectionKey("entry", "source"), deleted: true, count: 0 },
    ]);
  });
  it("invalidates old pages immediately after access is lost", async () => {
    const uid = await user();
    await store.publish(uid, "entry", "shared", [
      { id: "private", data: { title: "Private" } },
    ]);
    const old = (await store.collection(uid, "entry", "shared"))!;
    await store.publish(uid, "entry", "shared", [], { invalidate: true });
    await expect(
      store.page(uid, old.key, old.generation),
    ).rejects.toMatchObject({ code: "snapshot_expired" });
  });
  it("does not write staged Google data after account deletion begins", async () => {
    const uid = await user();
    const cache = new PageCache(store.db, uid, Date.now() + 40000);
    await expect(
      cache.all(["late-google"], async () => {
        await store.user(uid).update({ state: "deleting" });
        return { items: [{ id: "private" }] };
      }),
    ).rejects.toMatchObject({ code: "account_deleted" });
    expect((await store.user(uid).collection("staging").get()).empty).toBe(
      true,
    );
  });
  it("guards page downloads against account reauthorization", async () => {
    const uid = await user();
    const grant: AccountGrant = {
      id: "a",
      email: "",
      name: "",
      encryptedToken: "",
      scopes: [],
      generation: "first",
      state: "active",
      updatedAt: new Date().toISOString(),
    };
    await store.saveGrant(uid, grant);
    await store.publish(uid, "entry", "s", [{ id: "e", data: {} }], {
      guard: { accountId: "a", generation: "first" },
    });
    const old = (await store.collection(uid, "entry", "s"))!;
    await store.saveGrant(uid, { ...grant, generation: "second" });
    await expect(
      store.page(uid, old.key, old.generation),
    ).rejects.toMatchObject({ code: "snapshot_expired" });
  });
  it("keeps device switches versioned and refuses invented scheduling coverage", async () => {
    const uid = await user(),
      id = randomUUID();
    await store.registerDevice(uid, {
      id,
      name: "Phone",
      platform: "android",
      pushToken: null,
      appVersion: "beta",
    });
    await store.setDevice(uid, id, false, 1);
    await expect(store.setDevice(uid, id, true, 1)).rejects.toMatchObject({
      code: "device_conflict",
    });
    const health = {
      deviceVersion: 2,
      appliedRevision: 0,
      scheduledRevision: 0,
      scheduledCount: 0,
      earliestUnscheduled: null,
      alarms: true,
      notifications: true,
      fullScreen: true,
      error: "none" as const,
    };
    await store.acknowledge(uid, id, health);
    await expect(
      store.acknowledge(uid, id, { ...health, deviceVersion: 3 }),
    ).rejects.toMatchObject({ code: "invalid_revision" });
    await store.revokeDevice(uid, id);
    await expect(store.device(uid, id)).rejects.toMatchObject({
      code: "device_removed",
    });
  });
  it("persists the original task ETag so retries cannot overwrite a later Google edit", async () => {
    const uid = await user();
    await store.saveGrant(uid, {
      id: "a",
      email: "",
      name: "",
      scopes: [],
      encryptedToken: "",
      generation: "g",
      state: "active",
      updatedAt: "",
    });
    await store.publish(uid, "taskList", "a", [
      {
        id: "list",
        data: { id: "list", accountId: "a", providerId: "google-list" },
      },
    ]);
    await store.publish(uid, "task", "list", [
      {
        id: "task",
        data: { id: "task", listId: "list", providerId: "google-task" },
      },
    ]);
    const get = vi
      .fn()
      .mockResolvedValue({ data: { etag: "original", status: "needsAction" } });
    const patch = vi
      .fn()
      .mockRejectedValueOnce({ response: { status: 503 } })
      .mockRejectedValueOnce({ response: { status: 412 } });
    const gateway = {
      tasks: { tasks: { get, patch } },
    } as unknown as GoogleGateway;
    const service = new CloudService({ store } as Runtime);
    const job = {
      id: randomUUID(),
      uid,
      accountId: "a",
      taskId: "task",
      type: "complete" as const,
      requestedAt: new Date().toISOString(),
    };
    await expect(service.applyCompletion(job, gateway)).rejects.toMatchObject({
      reason: "transient",
    });
    get.mockResolvedValue({
      data: { etag: "edited-after-first-attempt", status: "needsAction" },
    });
    await service.applyCompletion(job, gateway);
    expect(patch.mock.calls[1][1].headers["If-Match"]).toBe("original");
    expect(
      (
        await store.user(uid).collection("taskOperations").doc(job.id).get()
      ).data()?.state,
    ).toBe("failed");
    await service.applyCompletion(job, gateway);
    expect(patch).toHaveBeenCalledTimes(2);
  });
});
