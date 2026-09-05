import { z } from "zod";
import {
  ApiError,
  healthSchema,
  idSchema,
  linkSchema,
  mutationSchema,
  registrationSchema,
} from "./contracts.ts";
import { RetryJob } from "./google.ts";
import { runtime, type Job } from "./runtime.ts";
import { CloudService } from "./service.ts";

const headers = {
  "Cache-Control": "private, no-store",
  "X-Content-Type-Options": "nosniff",
};
async function json<T>(request: Request, schema: z.ZodType<T>): Promise<T> {
  if (!request.headers.get("content-type")?.startsWith("application/json"))
    throw new ApiError(415, "json_required", "Send a JSON request.");
  const reader = request.body?.getReader();
  if (!reader)
    throw new ApiError(400, "body_required", "A request body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const part = await reader.read();
    if (part.done) break;
    size += part.value.length;
    if (size > 16384) {
      await reader.cancel();
      throw new ApiError(413, "too_large", "This request is too large.");
    }
    chunks.push(part.value);
  }
  let body;
  try {
    body = JSON.parse(Buffer.concat(chunks).toString());
  } catch {
    throw new ApiError(400, "invalid_json", "Send valid JSON.");
  }
  return schema.parse(body);
}
export async function respond(action: () => Promise<unknown>) {
  try {
    return Response.json((await action()) ?? { ok: true }, { headers });
  } catch (error) {
    if (error instanceof RetryJob)
      return Response.json(
        { error: { code: "retry", message: "The job will continue shortly." } },
        { status: 503, headers: { ...headers, "Retry-After": "15" } },
      );
    if (error instanceof z.ZodError)
      return Response.json(
        {
          error: {
            code: "invalid_request",
            message: "Check the supplied values.",
          },
        },
        { status: 400, headers },
      );
    if (error instanceof ApiError)
      return Response.json(
        {
          error: {
            code: error.code,
            message: error.message,
            ...(error.current ? { current: error.current } : {}),
          },
        },
        { status: error.status, headers },
      );
    // OAuth/API errors can include credentials and private content. Never log
    // raw exceptions or request bodies, even on preview deployments.
    console.error(
      JSON.stringify({
        event: "nextbell_request_failed",
        at: new Date().toISOString(),
      }),
    );
    return Response.json(
      {
        error: {
          code: "unavailable",
          message: "Nextbell could not finish this request. Please try again.",
        },
      },
      { status: 503, headers },
    );
  }
}
export async function api(request: Request) {
  return respond(async () => {
    const url = new URL(request.url),
      route = url.pathname.replace(/^\/api\/v1\/?/, "").split("/");
    const rt = await runtime(),
      service = new CloudService(rt);
    const register = request.method === "POST" && route.join("/") === "devices";
    const user = await rt.user(request, !register);
    const uid = user.uid;
    if (request.method === "GET" && route.join("/") === "sync") {
      const since = z.coerce
        .number()
        .int()
        .nonnegative()
        .parse(url.searchParams.get("since") ?? "0");
      return rt.store.manifest(uid, since);
    }
    if (
      request.method === "GET" &&
      route[0] === "operations" &&
      route.length === 2
    ) {
      const operation = (
        await rt.store
          .user(uid)
          .collection("taskOperations")
          .doc(z.uuid().parse(route[1]))
          .get()
      ).data();
      return {
        state: operation?.state ?? "pending",
        message: operation?.message ?? null,
      };
    }
    if (
      request.method === "GET" &&
      route[0] === "collections" &&
      route.length === 3
    ) {
      return rt.store.page(
        uid,
        idSchema.parse(route[1]),
        idSchema.parse(route[2]),
        url.searchParams.get("after")
          ? idSchema.parse(url.searchParams.get("after"))
          : undefined,
      );
    }
    if (request.method === "DELETE" && route.join("/") === "devices/current") {
      await rt.store.revokeDevice(uid, user.deviceId!);
      return { ok: true };
    }
    if (register)
      return rt.store.registerDevice(
        uid,
        await json(request, registrationSchema),
      );
    if (
      request.method === "PATCH" &&
      route[0] === "devices" &&
      route.length === 2
    ) {
      const id = z.uuid().parse(route[1]);
      const input = await json(
        request,
        z
          .object({ alarmsEnabled: z.boolean(), version: z.int().positive() })
          .strict(),
      );
      await rt.store.setDevice(uid, id, input.alarmsEnabled, input.version);
      await rt.push(uid, (await rt.store.manifest(uid)).revision);
      return rt.store.publicDevice(await rt.store.device(uid, id));
    }
    if (request.method === "POST" && route.join("/") === "devices/health") {
      await rt.store.acknowledge(
        uid,
        user.deviceId!,
        await json(request, healthSchema),
      );
      return { ok: true };
    }
    if (request.method === "POST" && route.join("/") === "preferences")
      return service.mutate(uid, await json(request, mutationSchema));
    if (
      request.method === "POST" &&
      route.join("/") === "accounts/authorization"
    ) {
      const input = await json(
        request,
        z
          .object({ expectedAccountId: z.string().regex(/^\d{5,100}$/) })
          .strict(),
      );
      return service.beginLink(uid, input.expectedAccountId);
    }
    if (request.method === "POST" && route.join("/") === "accounts/link")
      return service.link(uid, await json(request, linkSchema));
    if (
      request.method === "DELETE" &&
      route[0] === "accounts" &&
      route.length === 2
    ) {
      await service.removeAccount(uid, idSchema.parse(route[1]));
      return { ok: true };
    }
    if (request.method === "POST" && route.join("/") === "sync") {
      await rt.store.rateLimit(uid, "refresh", 2);
      await service.requestSync(uid);
      return { queued: true };
    }
    if (
      request.method === "POST" &&
      route[0] === "tasks" &&
      route[2] === "complete" &&
      route.length === 3
    ) {
      const input = await json(
        request,
        z.object({ mutationId: z.uuid() }).strict(),
      );
      return service.complete(uid, idSchema.parse(route[1]), input.mutationId);
    }
    if (request.method === "DELETE" && route.join("/") === "me") {
      if (Date.now() / 1000 - user.authTime > 300)
        throw new ApiError(
          401,
          "reauthenticate",
          "Sign in again before deleting your account.",
        );
      await service.requestDelete(uid);
      return { deleting: true };
    }
    throw new ApiError(404, "not_found", "This endpoint does not exist.");
  });
}
export async function webhook(request: Request) {
  return respond(async () =>
    new CloudService(await runtime()).webhook(request),
  );
}
export async function jobs(request: Request) {
  return respond(async () => {
    const rt = await runtime();
    await rt.internal(request);
    const input = await json(
      request,
      z.union([
        z.object({ type: z.enum(["dispatch", "maintenance"]) }).strict(),
        z
          .object({
            id: idSchema,
            uid: idSchema,
            type: z.enum(["sync", "complete", "delete"]),
            accountId: idSchema.optional(),
            requestedAt: z.iso.datetime(),
            taskId: idSchema.optional(),
            mutationId: z.uuid().optional(),
          })
          .strict(),
      ]),
    );
    const service = new CloudService(rt);
    if (input.type === "dispatch") return service.dispatchDue();
    if (input.type === "maintenance") return service.maintenance();
    if (!("uid" in input))
      throw new ApiError(400, "invalid_job", "Invalid job.");
    if (input.type !== "delete" && !input.accountId)
      throw new ApiError(400, "missing_account", "An account is required.");
    if (input.type === "complete" && !input.taskId)
      throw new ApiError(400, "missing_task", "A task is required.");
    return service.run(input as Job);
  });
}
