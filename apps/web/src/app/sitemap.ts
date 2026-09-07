import type { MetadataRoute } from "next";
import { publicPages, site } from "@/content/site";
export default function sitemap(): MetadataRoute.Sitemap {
  return publicPages.map((page) => ({
    url: `${site.origin}${page.href === "/" ? "" : page.href}`,
    lastModified: site.updatedAt,
    ...(page.href === "/"
      ? {
          images: [
            `${site.origin}/previews/agenda.png`,
            `${site.origin}/previews/tasks.png`,
          ],
        }
      : {}),
    changeFrequency: "monthly",
    priority: page.href === "/" ? 1 : 0.6,
  }));
}
