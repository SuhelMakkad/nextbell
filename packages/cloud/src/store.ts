import { createHash, randomUUID } from "node:crypto";
import type {
  Firestore,
  DocumentReference,
  Transaction,
} from "firebase-admin/firestore";
import {
  ApiError,
  type Collection,
  type Device,
  type DeviceHealth,
  type Json,
  type Manifest,
  type Mutation,
  type Page,
  type Preference,
  type RecordKind,
  type Row,
} from "./contracts.ts";
import { collectionKey, preferenceKey } from "./domain.ts";

export type AccountGrant = {
  id: string;
  email: string;
  name: string;
  encryptedToken: string;
  scopes: string[];
  generation: string;
  state: "active" | "reconnect" | "removed";
  updatedAt: string;
};
export type Guard = {
  accountId: string;
  generation: string;
  preference?: { key: string; version: number };
};
export type StoredCollection = Collection & {
  checksum?: string;
  checkpoint?: Json;
  accessEpoch?: string;
  accountId?: string;
  accountGeneration?: string;
};

export class CloudStore {
  constructor(
    readonly db: Firestore,
    readonly now: () => Date = () => new Date(),
  ) {}
  user(uid: string) {
    return this.db.collection("users").doc(uid);
  }
  async ensureUser(uid: string, email: string) {
    const ref = this.user(uid);
    await this.db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (doc.exists) {
        if (doc.data()?.state !== "active")
          throw new ApiError(
            410,
            "account_deleted",
            "This Nextbell account has been deleted.",
          );
        return;
      }
      tx.create(ref, {
        state: "active",
        email,
        revision: 0,
        createdAt: this.now().toISOString(),
      });
    });
  }
  async active(uid: string) {
    if ((await this.user(uid).get()).data()?.state !== "active") {
      throw new ApiError(
        410,
        "account_deleted",
        "This Nextbell account is unavailable.",
      );
    }
  }
  async guard(tx: Transaction, uid: string, guard?: Guard) {
    const user = await tx.get(this.user(uid));
    if (user.data()?.state !== "active")
      throw new ApiError(
        410,
        "account_deleted",
        "This Nextbell account is unavailable.",
      );
    if (guard) {
      const grant = await tx.get(
        this.user(uid).collection("grants").doc(guard.accountId),
      );
      if (
        grant.data()?.state !== "active" ||
        grant.data()?.generation !== guard.generation
      ) {
        throw new ApiError(409, "stale_job", "This connection has changed.");
      }
      if (guard.preference) {
        const pref = await tx.get(
          this.user(uid).collection("preferences").doc(guard.preference.key),
        );
        if ((pref.data()?.version ?? 0) !== guard.preference.version)
          throw new ApiError(409, "stale_job", "This selection has changed.");
      }
    }
    return Number(user.data()?.revision ?? 0);
  }
  async rateLimit(uid: string, bucket: string, limit: number, seconds = 60) {
    const period = Math.floor(+this.now() / (seconds * 1000));
    const ref = this.user(uid).collection("limits").doc(`${bucket}-${period}`);
    await this.db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if ((current.data()?.count ?? 0) >= limit)
        throw new ApiError(
          429,
          "rate_limited",
          "Please wait a moment before trying again.",
        );
      tx.set(ref, {
        count: (current.data()?.count ?? 0) + 1,
        expiresAt: new Date((period + 2) * seconds * 1000),
      });
    });
  }
  async grants(uid: string): Promise<AccountGrant[]> {
    return (await this.user(uid).collection("grants").get()).docs.map(
      (d) => d.data() as AccountGrant,
    );
  }
  async grant(uid: string, id: string) {
    const data = (
      await this.user(uid).collection("grants").doc(id).get()
    ).data();
    return data as AccountGrant | undefined;
  }
  async saveGrant(uid: string, grant: AccountGrant) {
    await this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      tx.set(this.user(uid).collection("grants").doc(grant.id), grant);
    });
  }
  async collections(uid: string) {
    return (await this.user(uid).collection("collections").get()).docs.map(
      (d) => d.data() as StoredCollection,
    );
  }
  async collection(uid: string, kind: RecordKind, owner: string) {
    return (
      await this.user(uid)
        .collection("collections")
        .doc(collectionKey(kind, owner))
        .get()
    ).data() as StoredCollection | undefined;
  }
  async preferences(uid: string): Promise<Preference[]> {
    return (await this.user(uid).collection("preferences").get()).docs.map(
      (d) => d.data() as Preference,
    );
  }
  async manifest(uid: string, since = 0): Promise<Manifest> {
    return this.db.runTransaction(async (tx) => {
      const revision = await this.guard(tx, uid);
      if (since > revision)
        throw new ApiError(
          409,
          "reset_cursor",
          "Download a fresh copy of your settings.",
        );
      const [collections, preferences, devices] = await Promise.all([
        tx.get(
          this.user(uid)
            .collection("collections")
            .where("revision", ">", since),
        ),
        tx.get(
          this.user(uid)
            .collection("preferences")
            .where("revision", ">", since),
        ),
        tx.get(this.user(uid).collection("devices")),
      ]);
      return {
        revision,
        serverTime: this.now().toISOString(),
        collections: collections.docs.map((d) => {
          const {
            checksum: _checksum,
            checkpoint: _checkpoint,
            accessEpoch: _epoch,
            accountId: _account,
            accountGeneration: _generation,
            ...publicData
          } = d.data() as StoredCollection;
          void _checksum;
          void _checkpoint;
          void _epoch;
          void _account;
          void _generation;
          return publicData;
        }),
        preferences: preferences.docs.map((d) => d.data() as Preference),
        devices: devices.docs
          .filter((d) => !d.data().revoked)
          .map((d) => this.publicDevice(d.data())),
      };
    });
  }
  async page(
    uid: string,
    key: string,
    generation: string,
    after?: string,
  ): Promise<Page> {
    const collection = this.user(uid).collection("collections").doc(key);
    const ref = collection.collection("versions").doc(generation);
    return this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      const [current, version] = await Promise.all([
        tx.get(collection),
        tx.get(ref),
      ]);
      const data = current.data();
      if (
        !data ||
        data.deleted ||
        !version.exists ||
        version.data()?.accessEpoch !== data.accessEpoch
      ) {
        throw new ApiError(
          409,
          "snapshot_expired",
          "This download expired. Refresh to try again.",
        );
      }
      if (data.accountId) {
        const grant = await tx.get(
          this.user(uid).collection("grants").doc(data.accountId),
        );
        if (
          grant.data()?.state !== "active" ||
          grant.data()?.generation !== data.accountGeneration
        ) {
          throw new ApiError(
            409,
            "snapshot_expired",
            "This connection changed. Refresh to try again.",
          );
        }
      }
      let query = ref.collection("rows").orderBy("id").limit(201);
      if (after) query = query.startAfter(after);
      const docs = (await tx.get(query)).docs;
      return {
        rows: docs.slice(0, 200).map((d) => d.data() as Row),
        next: docs.length > 200 ? docs[199].id : null,
      };
    });
  }

  async rows(uid: string, kind: RecordKind, owner: string): Promise<Row[]> {
    const current = await this.collection(uid, kind, owner);
    if (!current || current.deleted) return [];
    const docs = await this.user(uid)
      .collection("collections")
      .doc(current.key)
      .collection("versions")
      .doc(current.generation)
      .collection("rows")
      .orderBy("id")
      .get();
    return docs.docs.map((d) => d.data() as Row);
  }
  async find(
    uid: string,
    kind: RecordKind,
    id: string,
  ): Promise<Row | undefined> {
    for (const c of (await this.collections(uid)).filter(
      (c) => c.kind === kind && !c.deleted,
    )) {
      const row = await this.user(uid)
        .collection("collections")
        .doc(c.key)
        .collection("versions")
        .doc(c.generation)
        .collection("rows")
        .doc(id)
        .get();
      if (row.exists) return row.data() as Row;
    }
  }
  // Upload immutable pages before swapping the manifest and cursor in one transaction.
  // Readers holding an older manifest can finish their download without mixed versions.
  async publish(
    uid: string,
    kind: RecordKind,
    owner: string,
    rows: Row[],
    options: {
      guard?: Guard;
      checkpoint?: Json;
      deleted?: boolean;
      error?: string | null;
      fetched?: boolean;
      invalidate?: boolean;
      urgentKeys?: string[];
    } = {},
  ): Promise<{ revision: number; changed: boolean }> {
    const unique = [...new Map(rows.map((row) => [row.id, row])).values()].sort(
      (a, b) => a.id.localeCompare(b.id),
    );
    const checksum = createHash("sha256")
      .update(JSON.stringify(unique))
      .digest("hex");
    const key = collectionKey(kind, owner);
    const ref = this.user(uid).collection("collections").doc(key);
    const previous = (await ref.get()).data() as StoredCollection | undefined;
    const changed =
      previous?.checksum !== checksum ||
      !!previous?.deleted !== !!options.deleted;
    const invalidate =
      options.invalidate ||
      (!unique.length && changed) ||
      (changed && ["account", "source", "taskList"].includes(kind));
    const accessEpoch =
      invalidate || !previous?.accessEpoch
        ? randomUUID()
        : previous.accessEpoch;
    const generation =
      changed || !previous || invalidate ? randomUUID() : previous.generation;
    if (changed || !previous || invalidate) {
      const version = ref.collection("versions").doc(generation);
      await this.db.runTransaction(async (tx) => {
        await this.guard(tx, uid, options.guard);
        tx.set(version, {
          createdAt: this.now(),
          count: unique.length,
          accessEpoch,
        });
      });
      for (let i = 0; i < unique.length; i += 400) {
        await this.db.runTransaction(async (tx) => {
          await this.guard(tx, uid, options.guard);
          for (const row of unique.slice(i, i + 400))
            tx.set(version.collection("rows").doc(row.id), row);
        });
      }
    }
    return this.db.runTransaction(async (tx) => {
      const revision = (await this.guard(tx, uid, options.guard)) + 1;
      const latest = await tx.get(ref);
      if (latest.data()?.generation !== previous?.generation)
        throw new ApiError(
          409,
          "stale_job",
          "A newer refresh completed first.",
        );
      const collection: StoredCollection = {
        key,
        kind,
        owner,
        generation,
        revision,
        accessEpoch,
        ...(options.guard
          ? {
              accountId: options.guard.accountId,
              accountGeneration: options.guard.generation,
            }
          : {}),
        count: unique.length,
        checksum,
        selectionVersion:
          options.guard?.preference?.version ?? previous?.selectionVersion ?? 0,
        deleted: options.deleted ?? false,
        updatedAt: this.now().toISOString(),
        error: options.error ?? null,
        syncedAt: options.fetched
          ? this.now().toISOString()
          : (previous?.syncedAt ?? null),
        checkpoint: options.checkpoint ?? previous?.checkpoint ?? {},
      };
      tx.set(ref, collection);
      for (const key of options.urgentKeys ?? [])
        tx.set(this.user(uid).collection("changeEvents").doc(key), {
          key,
          expiresAt: new Date(+this.now() + 3600000),
        });
      tx.update(this.user(uid), { revision });
      return { revision, changed };
    });
  }
  async mutate(
    uid: string,
    mutation: Mutation,
    owner: string,
    guard?: Guard,
  ): Promise<Preference> {
    const key = preferenceKey(mutation.patch.kind, mutation.patch.targetId);
    const ref = this.user(uid).collection("preferences").doc(key);
    const receipt = this.user(uid)
      .collection("mutations")
      .doc(mutation.mutationId);
    return this.db.runTransaction(async (tx) => {
      const revision = (await this.guard(tx, uid, guard)) + 1;
      const [prior, current] = await Promise.all([
        tx.get(receipt),
        tx.get(ref),
      ]);
      const digest = createHash("sha256")
        .update(JSON.stringify(mutation))
        .digest("hex");
      if (prior.exists) {
        if (prior.data()?.digest !== digest)
          throw new ApiError(
            409,
            "mutation_reused",
            "Use a new identifier for this change.",
          );
        return prior.data()?.result as Preference;
      }
      if ((current.data()?.version ?? 0) !== mutation.baseVersion) {
        throw new ApiError(
          409,
          "conflict",
          "This setting changed on another device.",
          current.data() as Preference,
        );
      }
      const value: Preference = {
        key,
        kind: mutation.patch.kind,
        targetId: mutation.patch.targetId,
        owner,
        value:
          mutation.patch.value === null
            ? {}
            : { ...current.data()?.value, ...mutation.patch.value },
        deleted: mutation.patch.value === null,
        version: mutation.baseVersion + 1,
        revision,
      };
      tx.set(ref, value);
      tx.set(receipt, {
        digest,
        result: value,
        expiresAt: new Date(+this.now() + 30 * 86400000),
      });
      tx.update(this.user(uid), { revision });
      return value;
    });
  }
  async removePreferences(uid: string, owners: Set<string>) {
    for (const pref of await this.preferences(uid)) {
      if (!owners.has(pref.owner) || pref.deleted) continue;
      await this.db.runTransaction(async (tx) => {
        const revision = (await this.guard(tx, uid)) + 1;
        const ref = this.user(uid).collection("preferences").doc(pref.key);
        const fresh = await tx.get(ref);
        tx.set(ref, {
          ...fresh.data(),
          value: {},
          deleted: true,
          version: Number(fresh.data()?.version ?? 0) + 1,
          revision,
        });
        tx.update(this.user(uid), { revision });
      });
    }
  }
  publicDevice(data: Json): Device {
    return {
      id: data.id as string,
      name: data.name as string,
      platform: "android",
      appVersion: data.appVersion as string,
      alarmsEnabled: data.alarmsEnabled as boolean,
      version: data.version as number,
      lastSeen: data.lastSeen as string,
      health: (data.health ?? null) as DeviceHealth | null,
    };
  }
  async device(uid: string, id: string) {
    const doc = await this.user(uid).collection("devices").doc(id).get();
    if (!doc.exists || doc.data()?.revoked)
      throw new ApiError(
        403,
        "device_removed",
        "Sign in again to register this device.",
      );
    return doc.data()!;
  }
  async registerDevice(uid: string, registration: Json) {
    const ref = this.user(uid)
      .collection("devices")
      .doc(String(registration.id));
    await this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      const old = await tx.get(ref);
      if (old.data()?.revoked)
        throw new ApiError(
          403,
          "device_removed",
          "Register this installation again.",
        );
      tx.set(ref, {
        ...registration,
        alarmsEnabled: old.data()?.alarmsEnabled ?? true,
        version: old.data()?.version ?? 1,
        health: old.data()?.health ?? null,
        lastSeen: this.now().toISOString(),
        revoked: false,
      });
    });
    return this.publicDevice(await this.device(uid, String(registration.id)));
  }
  async setDevice(uid: string, id: string, enabled: boolean, version: number) {
    const ref = this.user(uid).collection("devices").doc(id);
    await this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      const current = await tx.get(ref);
      if (!current.exists || current.data()?.revoked)
        throw new ApiError(
          404,
          "device_removed",
          "This device is unavailable.",
        );
      if (current.data()?.version !== version)
        throw new ApiError(
          409,
          "device_conflict",
          "Refresh this device before changing it.",
        );
      tx.update(ref, { alarmsEnabled: enabled, version: version + 1 });
    });
  }
  async revokeDevice(uid: string, id: string) {
    await this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      const ref = this.user(uid).collection("devices").doc(id);
      const doc = await tx.get(ref);
      if (doc.exists)
        tx.update(ref, {
          revoked: true,
          pushToken: null,
          alarmsEnabled: false,
        });
    });
  }
  async acknowledge(uid: string, id: string, health: DeviceHealth) {
    const ref = this.user(uid).collection("devices").doc(id);
    await this.db.runTransaction(async (tx) => {
      const revision = await this.guard(tx, uid);
      const current = await tx.get(ref);
      if (!current.exists || current.data()?.revoked)
        throw new ApiError(
          403,
          "device_removed",
          "This device is unavailable.",
        );
      if (
        health.scheduledRevision > health.appliedRevision ||
        health.appliedRevision > revision ||
        health.deviceVersion > Number(current.data()?.version)
      )
        throw new ApiError(
          400,
          "invalid_revision",
          "Invalid synchronization revision.",
        );
      tx.update(ref, { health, lastSeen: this.now().toISOString() });
    });
  }
  async acquireJob(uid: string, id: string, lease: string): Promise<boolean> {
    const ref = this.user(uid).collection("jobs").doc(id);
    return this.db.runTransaction(async (tx) => {
      await this.guard(tx, uid);
      const previous = await tx.get(ref);
      if (previous.data()?.done || previous.data()?.leaseUntil > +this.now())
        return false;
      tx.set(ref, {
        ...previous.data(),
        lease,
        leaseUntil: +this.now() + 240000,
        expiresAt: new Date(+this.now() + 7 * 86400000),
      });
      return true;
    });
  }
  async finishJob(uid: string, id: string, lease: string, done: boolean) {
    const ref = this.user(uid).collection("jobs").doc(id);
    await this.db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (current.data()?.lease !== lease) return;
      tx.update(ref, { done, leaseUntil: 0 });
    });
  }
  async deleteTree(ref: DocumentReference) {
    await this.db.recursiveDelete(ref);
  }
}
