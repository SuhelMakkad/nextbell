import { site } from "./site";

// Describe the real product without inventing ratings, reviews or a download URL.
export const homeStructuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${site.origin}/#website`,
      url: site.origin,
      name: site.name,
      inLanguage: "en",
    },
    {
      "@type": "MobileApplication",
      "@id": `${site.origin}/#app`,
      name: site.name,
      url: site.origin,
      description: site.description,
      applicationCategory: "ProductivityApplication",
      operatingSystem: "Android 8.0 or later",
      image: `${site.origin}/brand/icon.png`,
      screenshot: [
        `${site.origin}/previews/agenda.png`,
        `${site.origin}/previews/tasks.png`,
      ],
      featureList: [
        "Custom Google Calendar meeting alarms",
        "Shared calendars and multiple Google accounts",
        "Google Tasks with separate alarm times",
        "Timezone-aware reminders",
        "On-device storage and offline scheduled alarms",
      ],
      author: { "@type": "Person", name: site.operator },
    },
  ],
} as const;
