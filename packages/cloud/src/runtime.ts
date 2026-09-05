import { randomBytes } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { OAuth2Client } from "google-auth-library";
import {
  OAuth2Client as CloudOAuth2Client,
  ExternalAccountClient,
  GoogleAuth,
  type AuthClient,
} from "google-cloud-auth";
import { CloudTasksClient } from "@google-cloud/tasks";
import { KeyManagementServiceClient } from "@google-cloud/kms";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import { getVercelOidcToken } from "@vercel/oidc";
import { ApiError } from "./contracts.ts";
import { CloudStore } from "./store.ts";
import { stableId } from "./domain.ts";

export function required(name: string) {
  const value = process.env[name];
  if (!value)
    throw new ApiError(
      503,
      "configuration",
      "Nextbell cloud is not configured yet.",
    );
  return value;
}
export const emulator = () =>
  process.env.NODE_ENV !== "production" &&
  process.env.NEXTBELL_EMULATORS === "1";
export type Job = {
  id: string;
  uid: string;
  accountId?: string;
  type: "sync" | "complete" | "delete";
  requestedAt: string;
  taskId?: string;
  mutationId?: string;
};

export class Runtime {
  readonly projectId = required("GOOGLE_CLOUD_PROJECT");
  readonly origin = new URL(required("NEXTBELL_API_ORIGIN")).origin;
  readonly region = process.env.GOOGLE_CLOUD_REGION ?? "asia-south1";
  readonly auth = getAuth();
  readonly messaging = getMessaging();
  readonly store = new CloudStore(getFirestore());
  readonly tasks: CloudTasksClient;
  readonly kms: KeyManagementServiceClient;
  readonly secrets: SecretManagerServiceClient;
  private oauthSecret?: Promise<string>;
  constructor(authClient: AuthClient) {
    const options = { projectId: this.projectId, authClient };
    this.tasks = new CloudTasksClient(options);
    this.kms = new KeyManagementServiceClient(options);
    this.secrets = new SecretManagerServiceClient(options);
  }
  async oauth() {
    if (emulator())
      throw new ApiError(
        503,
        "emulator_google_disabled",
        "Live Google authorization is disabled in emulator mode.",
      );
    this.oauthSecret ??= this.secrets
      .accessSecretVersion({ name: required("GOOGLE_OAUTH_SECRET_VERSION") })
      .then(([response]) =>
        Buffer.from(response.payload?.data as Uint8Array).toString(),
      );
    return new OAuth2Client(
      required("GOOGLE_SERVER_CLIENT_ID"),
      await this.oauthSecret,
      "",
    );
  }
  async encrypt(token: string) {
    const [result] = await this.kms.encrypt({
      name: required("GOOGLE_TOKEN_KEY"),
      plaintext: Buffer.from(token),
    });
    return Buffer.from(result.ciphertext as Uint8Array).toString("base64");
  }
  async decrypt(cipher: string) {
    const [result] = await this.kms.decrypt({
      name: required("GOOGLE_TOKEN_KEY"),
      ciphertext: Buffer.from(cipher, "base64"),
    });
    return Buffer.from(result.plaintext as Uint8Array).toString();
  }
  async user(request: Request, requireDevice = true) {
    const bearer = request.headers.get("authorization");
    if (!bearer?.startsWith("Bearer ") || bearer.length > 16000)
      throw new ApiError(401, "sign_in", "Sign in to Nextbell.");
    let identity;
    try {
      identity = await this.auth.verifyIdToken(bearer.slice(7), true);
    } catch {
      // A signed, unexpired token may outlive account deletion. Validate its
      // signature before consulting the deletion marker; never trust decoded JWTs.
      try {
        const prior = await this.auth.verifyIdToken(bearer.slice(7));
        const state = (await this.store.user(prior.uid).get()).data()?.state;
        if (state === "deleting" || state === "deleted")
          throw new ApiError(
            410,
            "account_deleted",
            "This Nextbell account has been deleted.",
          );
      } catch (e) {
        if (e instanceof ApiError) throw e;
      }
      throw new ApiError(401, "sign_in", "Sign in to Nextbell again.");
    }
    if (
      !identity.email_verified ||
      identity.firebase.sign_in_provider !== "google.com"
    )
      throw new ApiError(
        403,
        "google_required",
        "Use your primary Google account to sign in.",
      );
    const allowed = required("NEXTBELL_BETA_EMAILS")
      .split(",")
      .map((s) => s.trim().toLowerCase());
    if (!identity.email || !allowed.includes(identity.email.toLowerCase()))
      throw new ApiError(
        403,
        "beta_closed",
        "This account is not in the Nextbell private beta yet.",
      );
    await this.store.ensureUser(identity.uid, identity.email);
    await this.store.rateLimit(identity.uid, "api", 120);
    const deviceId = request.headers.get("x-nextbell-device");
    if (requireDevice) {
      if (!deviceId || !/^[0-9a-f-]{36}$/.test(deviceId))
        throw new ApiError(
          403,
          "device_required",
          "Register this phone before syncing.",
        );
      await this.store.device(identity.uid, deviceId);
    }
    return {
      uid: identity.uid,
      email: identity.email,
      deviceId,
      authTime: identity.auth_time,
    };
  }
  async internal(request: Request) {
    const bearer = request.headers.get("authorization");
    if (!bearer?.startsWith("Bearer "))
      throw new ApiError(401, "unauthorized", "Authentication required.");
    try {
      const ticket = await new OAuth2Client().verifyIdToken({
        idToken: bearer.slice(7),
        audience: `${this.origin}/api/internal/jobs`,
      });
      const claims = ticket.getPayload();
      if (
        !claims?.email_verified ||
        claims.email !== required("GOOGLE_JOB_SERVICE_ACCOUNT")
      )
        throw new Error();
    } catch {
      throw new ApiError(403, "unauthorized", "Authentication failed.");
    }
  }
  async enqueue(job: Job) {
    const ref = this.store.db.collection("dispatches").doc(job.id);
    const persisted = await this.store.db.runTransaction(async (tx) => {
      await this.store.guard(tx, job.uid);
      const current = await tx.get(ref);
      if (current.exists) {
        const original = current.data() as Job;
        if (
          original.uid !== job.uid ||
          original.type !== job.type ||
          original.taskId !== job.taskId ||
          original.accountId !== job.accountId
        )
          throw new ApiError(
            409,
            "mutation_reused",
            "Use a new identifier for this operation.",
          );
        return original;
      }
      tx.create(ref, { ...job, state: "pending", nextAt: new Date() });
      return job;
    });
    await this.dispatch(persisted).catch(() => {
      /* The scheduler retries this persisted outbox. */
    });
  }
  async dispatch(input: Job) {
    const { id, uid, type, requestedAt, accountId, taskId, mutationId } = input;
    const job: Job = {
      id,
      uid,
      type,
      requestedAt,
      ...(accountId ? { accountId } : {}),
      ...(taskId ? { taskId } : {}),
      ...(mutationId ? { mutationId } : {}),
    };
    if (emulator()) return;
    const parent = this.tasks.queuePath(
      this.projectId,
      this.region,
      "nextbell-sync",
    );
    try {
      await this.tasks.createTask({
        parent,
        task: {
          name: `${parent}/tasks/${job.id}`,
          dispatchDeadline: { seconds: 240 },
          httpRequest: {
            httpMethod: "POST",
            url: `${this.origin}/api/internal/jobs`,
            headers: { "Content-Type": "application/json" },
            body: Buffer.from(JSON.stringify(job)).toString("base64"),
            oidcToken: {
              serviceAccountEmail: required("GOOGLE_JOB_SERVICE_ACCOUNT"),
              audience: `${this.origin}/api/internal/jobs`,
            },
          },
        },
      });
    } catch (e) {
      if ((e as { code?: number }).code !== 6) throw e;
    }
    await this.store.db
      .collection("dispatches")
      .doc(job.id)
      .update({ state: "queued" });
  }
  async push(uid: string, revision: number, urgentKeys: string[] = []) {
    const events = (
      await this.store.user(uid).collection("changeEvents").get()
    ).docs.filter((d) => d.data().expiresAt.toMillis() > Date.now());
    urgentKeys = [...new Set([...urgentKeys, ...events.map((d) => d.id)])];
    const devices = await this.store.user(uid).collection("devices").get();
    for (const device of devices.docs) {
      const data = device.data();
      if (!data.pushToken || data.revoked) continue;
      const notices = this.store.user(uid).collection("notices");
      if (data.alarmsEnabled && data.health?.notifications) {
        for (const key of urgentKeys) {
          try {
            await notices.doc(stableId([device.id, key])).create({
              deviceId: device.id,
              sent: false,
              expiresAt: new Date(Date.now() + 3600000),
            });
          } catch (e) {
            if ((e as { code?: number }).code !== 6) throw e;
          }
        }
      }
      const pending = (
        await notices
          .where("deviceId", "==", device.id)
          .where("sent", "==", false)
          .get()
      ).docs.filter((d) => d.data().expiresAt.toMillis() > Date.now());
      const settings = await this.store
        .user(uid)
        .collection("preferences")
        .doc(stableId(["settings", "main"]))
        .get();
      const urgent = !!(
        pending.length &&
        data.alarmsEnabled &&
        data.health?.notifications &&
        settings.data()?.value?.urgentNotices !== false
      );
      try {
        await this.messaging.send({
          token: data.pushToken,
          data: {
            type: urgent ? "urgent_change" : "sync",
            revision: String(revision),
            noticeId: randomBytes(12).toString("hex"),
          },
          android: {
            priority: urgent ? "high" : "normal",
            ttl: urgent ? 3600000 : 86400000,
            collapseKey: urgent ? "urgent-change" : "sync",
          },
        });
        for (const notice of pending) await notice.ref.update({ sent: true });
      } catch (e) {
        if (
          [
            "messaging/registration-token-not-registered",
            "messaging/invalid-registration-token",
          ].includes((e as { code: string }).code)
        )
          await device.ref.update({ pushToken: null });
        else throw e;
      }
    }
  }
}

let pending: Promise<Runtime> | undefined;
export function runtime(): Promise<Runtime> {
  return (pending ??= (async () => {
    const projectId = required("GOOGLE_CLOUD_PROJECT");
    let client: AuthClient;
    if (emulator()) {
      const local = new CloudOAuth2Client();
      local.setCredentials({ access_token: "owner" });
      client = local;
    } else if (process.env.VERCEL) {
      client = ExternalAccountClient.fromJSON({
        type: "external_account",
        audience: required("GOOGLE_WORKLOAD_AUDIENCE"),
        subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
        token_url: "https://sts.googleapis.com/v1/token",
        service_account_impersonation_url: `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${required("GOOGLE_RUNTIME_SERVICE_ACCOUNT")}:generateAccessToken`,
        subject_token_supplier: { getSubjectToken: getVercelOidcToken },
      })!;
    } else
      client = await new GoogleAuth({
        projectId,
        scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      }).getClient();
    if (!getApps().length)
      initializeApp({
        projectId,
        credential: {
          getAccessToken: async () => {
            if (emulator()) return { access_token: "owner", expires_in: 3600 };
            const token = await client.getAccessToken();
            if (!token.token)
              throw new Error("Google authentication unavailable.");
            return { access_token: token.token, expires_in: 3000 };
          },
        },
      });
    return new Runtime(client);
  })().catch((e) => {
    pending = undefined;
    throw e;
  }));
}
