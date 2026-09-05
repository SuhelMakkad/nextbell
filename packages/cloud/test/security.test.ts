import { createHash } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Runtime } from "../src/runtime.ts";
import { CloudService } from "../src/service.ts";
import { respond } from "../src/http.ts";

afterEach(() => vi.restoreAllMocks());
describe("API boundaries", () => {
  it("rejects missing identity before touching data", async () => {
    const rt = Object.create(Runtime.prototype) as Runtime;
    await expect(
      rt.user(new Request("https://beta.example/api/v1/sync")),
    ).rejects.toMatchObject({ status: 401 });
  });
  it("rejects unverified identities and accounts outside the beta", async () => {
    const rt = Object.create(Runtime.prototype) as Runtime;
    const claims = {
      uid: "u",
      email: "other@example.com",
      email_verified: false,
      firebase: { sign_in_provider: "google.com" },
    };
    Object.assign(rt, { auth: { verifyIdToken: vi.fn(async () => claims) } });
    const request = new Request("https://beta.example/api/v1/sync", {
      headers: { authorization: "Bearer signed" },
    });
    await expect(rt.user(request)).rejects.toMatchObject({
      code: "google_required",
    });
    claims.email_verified = true;
    vi.stubEnv("NEXTBELL_BETA_EMAILS", "owner@example.com");
    await expect(rt.user(request)).rejects.toMatchObject({
      code: "beta_closed",
    });
    vi.unstubAllEnvs();
  });
  it("returns no raw exception, OAuth credential, or Google content", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const result = await respond(async () => {
      throw new Error("private-title refresh_token=secret");
    });
    expect(result.status).toBe(503);
    expect(await result.text()).not.toContain("secret");
    expect(JSON.stringify(log.mock.calls)).not.toMatch(/secret|private-title/);
    expect(result.headers.get("cache-control")).toContain("no-store");
  });
});
describe("Google webhooks", () => {
  const id = "12345678-1234-1234-1234-123456789abc";
  const channel = {
    uid: "u",
    accountId: "a",
    generation: "g",
    resourceId: "resource",
    expires: Date.now() + 60000,
    tokenHash: createHash("sha256").update("correct").digest("hex"),
  };
  function service() {
    return new CloudService({
      store: {
        db: {
          collection: () => ({
            doc: () => ({ get: async () => ({ data: () => channel }) }),
          }),
        },
        grant: async () => ({ state: "active", generation: "g" }),
      },
    } as unknown as Runtime);
  }
  function request(token: string, resource = "resource") {
    return new Request("https://beta.example/api/webhooks/google/calendar", {
      headers: {
        "x-goog-channel-id": id,
        "x-goog-channel-token": token,
        "x-goog-resource-id": resource,
        "x-goog-message-number": "8",
      },
    });
  }
  it("requires a matching token and resource before enqueueing", async () => {
    const app = service(),
      enqueue = vi.spyOn(app, "requestSync").mockResolvedValue();
    await expect(app.webhook(request("forged"))).rejects.toMatchObject({
      status: 403,
    });
    await expect(
      app.webhook(request("correct", "other")),
    ).rejects.toMatchObject({ status: 403 });
    expect(enqueue).not.toHaveBeenCalled();
    await app.webhook(request("correct"));
    expect(enqueue).toHaveBeenCalledTimes(1);
  });
  it("ignores an old account generation", async () => {
    const app = service(),
      enqueue = vi.spyOn(app, "requestSync").mockResolvedValue();
    vi.spyOn(app.store, "grant").mockResolvedValue({
      state: "active",
      generation: "new",
    } as never);
    await app.webhook(request("correct"));
    expect(enqueue).not.toHaveBeenCalled();
  });
});
