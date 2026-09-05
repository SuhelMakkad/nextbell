import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  serverExternalPackages: [
    "@google-cloud/tasks",
    "@google-cloud/kms",
    "@google-cloud/secret-manager",
    "googleapis",
    "google-auth-library",
    "google-cloud-auth",
    "firebase-admin",
  ],
  transpilePackages: ["@nextbell/cloud"],
  async headers() {
    return process.env.VERCEL_ENV === "preview"
      ? [
          {
            source: "/:path*",
            headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }],
          },
        ]
      : [];
  },
};

export default nextConfig;
