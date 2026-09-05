import type { MetadataRoute } from "next";
import { publicPages, site } from "@/content/site";
export default function sitemap(): MetadataRoute.Sitemap {
  return publicPages.map((page) => ({
    url: `${site.origin}${page.href === "/" ? "" : page.href}`,
    changeFrequency: "monthly",
    priority: page.href === "/" ? 1 : 0.6,
  }));
}
