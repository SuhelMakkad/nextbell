import { z } from "zod";

export const idSchema = z
  .string()
  .min(1)
  .max(200)
  .regex(/^[A-Za-z0-9_-]+$/);
export const instantSchema = z.iso.datetime({ offset: true });
export const offsetsSchema = z
  .array(z.int().min(0).max(40320))
  .max(32)
  .transform((values) => [...new Set(values)].sort((a, b) => b - a));
export const sourceModeSchema = z.enum(["off", "showOnly", "alarm"]);
export const recordKindSchema = z.enum([
  "account",
  "source",
  "entry",
  "taskList",
  "task",
]);
export type RecordKind = z.infer<typeof recordKindSchema>;
export type Json = Record<string, unknown>;

export const rowSchema = z.object({
  id: idSchema,
  data: z.record(z.string(), z.unknown()),
});
export type Row = z.infer<typeof rowSchema>;
export const collectionSchema = z.object({
  key: idSchema,
  kind: recordKindSchema,
  owner: z.string().max(200),
  generation: idSchema,
  revision: z.int().nonnegative(),
  count: z.int().nonnegative(),
  selectionVersion: z.int().nonnegative(),
  deleted: z.boolean(),
  updatedAt: instantSchema,
  syncedAt: instantSchema.nullable(),
  error: z.string().nullable(),
});
export type Collection = z.infer<typeof collectionSchema>;

export const preferenceKindSchema = z.enum([
  "settings",
  "source",
  "taskList",
  "override",
  "taskAlarm",
]);
export type PreferenceKind = z.infer<typeof preferenceKindSchema>;
export const preferenceSchema = z.object({
  key: idSchema,
  kind: preferenceKindSchema,
  targetId: idSchema,
  owner: z.string(),
  value: z.record(z.string(), z.unknown()),
  version: z.int().nonnegative(),
  revision: z.int().nonnegative(),
  deleted: z.boolean(),
});
export type Preference = z.infer<typeof preferenceSchema>;
export const patchSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("settings"),
    targetId: z.literal("main"),
    value: z
      .object({
        minutes: offsetsSchema.optional(),
        snoozeMinutes: z.int().min(1).max(60).optional(),
        theme: z.enum(["system", "light", "dark"]).optional(),
        onboarded: z.boolean().optional(),
        urgentNotices: z.boolean().optional(),
      })
      .strict(),
  }),
  z.object({
    kind: z.literal("source"),
    targetId: idSchema,
    value: z
      .object({
        mode: sourceModeSchema.optional(),
        reminderMinutes: offsetsSchema.nullable().optional(),
      })
      .strict(),
  }),
  z.object({
    kind: z.literal("taskList"),
    targetId: idSchema,
    value: z.object({ selected: z.boolean() }).strict(),
  }),
  z.object({
    kind: z.literal("override"),
    targetId: idSchema,
    value: z
      .object({
        sourceId: idSchema,
        minutes: offsetsSchema,
      })
      .strict()
      .nullable(),
  }),
  z.object({
    kind: z.literal("taskAlarm"),
    targetId: idSchema,
    value: z.object({ alarmAt: instantSchema.nullable() }).strict(),
  }),
]);
export const mutationSchema = z
  .object({
    mutationId: z.uuid(),
    baseVersion: z.int().nonnegative(),
    patch: patchSchema,
  })
  .strict();
export type Mutation = z.infer<typeof mutationSchema>;
export const linkSchema = z
  .object({
    code: z.string().min(10).max(4096),
    expectedAccountId: z.string().regex(/^\d{5,100}$/),
    attemptId: z.uuid(),
  })
  .strict();
export const registrationSchema = z
  .object({
    id: z.uuid(),
    name: z.string().trim().min(1).max(80),
    platform: z.literal("android"),
    pushToken: z.string().min(10).max(4096).nullable(),
    appVersion: z.string().max(50),
  })
  .strict();
export const healthSchema = z
  .object({
    deviceVersion: z.int().nonnegative(),
    appliedRevision: z.int().nonnegative(),
    scheduledRevision: z.int().nonnegative(),
    scheduledCount: z.int().min(0).max(100000),
    earliestUnscheduled: instantSchema.nullable(),
    alarms: z.boolean(),
    notifications: z.boolean(),
    fullScreen: z.boolean(),
    error: z.enum(["permission", "capacity", "scheduling", "offline", "none"]),
  })
  .strict();
export type DeviceHealth = z.infer<typeof healthSchema>;
export const deviceSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  platform: z.literal("android"),
  appVersion: z.string(),
  alarmsEnabled: z.boolean(),
  version: z.int(),
  lastSeen: instantSchema,
  health: healthSchema.nullable(),
});
export type Device = z.infer<typeof deviceSchema>;
export const manifestSchema = z.object({
  revision: z.int().nonnegative(),
  collections: z.array(collectionSchema),
  preferences: z.array(preferenceSchema),
  devices: z.array(deviceSchema),
  serverTime: instantSchema,
});
export type Manifest = z.infer<typeof manifestSchema>;
export const pageSchema = z.object({
  rows: z.array(rowSchema),
  next: z.string().nullable(),
});
export type Page = z.infer<typeof pageSchema>;
export const errorSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    current: preferenceSchema.optional(),
  }),
});

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly current?: Preference;
  constructor(
    status: number,
    code: string,
    message: string,
    current?: Preference,
  ) {
    super(message);
    this.status = status;
    this.code = code;
    this.current = current;
  }
}
