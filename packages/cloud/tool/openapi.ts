import { writeFileSync } from "node:fs";
import { z } from "zod";
import {
  manifestSchema,
  pageSchema,
  mutationSchema,
  preferenceSchema,
  registrationSchema,
  deviceSchema,
  healthSchema,
  linkSchema,
  errorSchema,
} from "../src/contracts.ts";

const json = (schema: z.ZodType) => z.toJSONSchema(schema, { io: "input" });
const schemas = {
  Manifest: manifestSchema,
  Page: pageSchema,
  Mutation: mutationSchema,
  Preference: preferenceSchema,
  Registration: registrationSchema,
  Device: deviceSchema,
  Health: healthSchema,
  Link: linkSchema,
  Error: errorSchema,
};
const content = (name: string) => ({
  "application/json": { schema: { $ref: `#/components/schemas/${name}` } },
});
const operation = (
  summary: string,
  response?: string,
  request?: string,
  parameters: unknown[] = [],
) => ({
  summary,
  security: [{ firebase: [] }],
  parameters,
  ...(request
    ? { requestBody: { required: true, content: content(request) } }
    : {}),
  responses: {
    "200": {
      description: "Success",
      ...(response ? { content: content(response) } : {}),
    },
    default: {
      description: "Safe error; 409 conflicts are never silently overwritten.",
      content: content("Error"),
    },
  },
});
const path = (name: string) => ({
  name,
  in: "path",
  required: true,
  schema: { type: "string" },
});
const spec = {
  openapi: "3.1.0",
  info: { title: "Nextbell private Android beta API", version: "1.0.0" },
  servers: [
    {
      url: "https://www.nextbell.org/api/v1",
      description: "Set the dedicated beta origin before deployment.",
    },
  ],
  components: {
    securitySchemes: {
      firebase: {
        type: "http",
        scheme: "bearer",
        bearerFormat: "Firebase ID token",
      },
    },
    schemas: Object.fromEntries(
      Object.entries(schemas).map(([name, schema]) => [name, json(schema)]),
    ),
  },
  paths: {
    "/sync": {
      get: operation(
        "Download changes since a committed cursor",
        "Manifest",
        undefined,
        [
          {
            name: "since",
            in: "query",
            schema: { type: "integer", minimum: 0, default: 0 },
          },
        ],
      ),
      post: operation("Queue a Google refresh"),
    },
    "/collections/{key}/{generation}": {
      get: operation(
        "Read an immutable, access-checked page",
        "Page",
        undefined,
        [
          path("key"),
          path("generation"),
          { name: "after", in: "query", schema: { type: "string" } },
        ],
      ),
    },
    "/preferences": {
      post: operation(
        "Apply an idempotent versioned preference",
        "Preference",
        "Mutation",
      ),
    },
    "/devices": {
      post: operation(
        "Register the authenticated phone",
        "Device",
        "Registration",
      ),
    },
    "/devices/{id}": {
      patch: {
        ...operation(
          "Change alarms on a phone; requires alarmsEnabled and version",
          "Device",
          undefined,
          [path("id")],
        ),
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: json(
                z
                  .object({
                    alarmsEnabled: z.boolean(),
                    version: z.int().positive(),
                  })
                  .strict(),
              ),
            },
          },
        },
      },
    },
    "/devices/health": {
      post: operation(
        "Report applied revisions and actual native scheduling coverage",
        undefined,
        "Health",
      ),
    },
    "/devices/current": {
      delete: operation("Unregister this phone and its push token"),
    },
    "/accounts/authorization": {
      post: {
        ...operation("Create a short-lived authorization attempt"),
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: json(
                z
                  .object({
                    expectedAccountId: z.string().regex(/^\d{5,100}$/),
                  })
                  .strict(),
              ),
            },
          },
        },
      },
    },
    "/accounts/link": {
      post: operation(
        "Exchange the account-bound offline Google authorization code",
        undefined,
        "Link",
      ),
    },
    "/accounts/{id}": {
      delete: operation(
        "Remove a connected Google source account",
        undefined,
        undefined,
        [path("id")],
      ),
    },
    "/tasks/{id}/complete": {
      post: {
        ...operation("Queue Google task completion", undefined, undefined, [
          path("id"),
        ]),
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: json(z.object({ mutationId: z.uuid() }).strict()),
            },
          },
        },
      },
    },
    "/operations/{id}": {
      get: operation(
        "Inspect pending, complete, or failed task completion",
        undefined,
        undefined,
        [path("id")],
      ),
    },
    "/me": {
      delete: operation(
        "Delete Nextbell account; requires authentication within five minutes",
      ),
    },
  },
};
writeFileSync(
  new URL("../openapi.json", import.meta.url),
  `${JSON.stringify(spec, null, 2)}\n`,
);
