import type { Metadata } from "next";

export const site = {
  name: "Nextbell",
  origin: "https://nextbell.org",
  operator: "Suhel Makkad",
  email: "makadsuhel11@gmail.com",
  description:
    "A little ahead. A lot more present. Nextbell turns your Google Calendar plans into customizable alarms, with Google Tasks and shared calendars in one calm app.",
  reviewedOn: "September 5, 2026",
} as const;

type StoreListing = { label: string; href: `https://${string}` };
// Add only real, published store listings. An empty list keeps download links hidden.
export const storeListings: readonly StoreListing[] = [];

export const publicPages = [
  { href: "/", label: "Home" },
  { href: "/privacy", label: "Privacy" },
  { href: "/support", label: "Support" },
  { href: "/terms", label: "Terms" },
  { href: "/data-deletion", label: "Remove your data" },
] as const;

export function pageMetadata(
  title: string,
  description: string,
  path: string,
): Metadata {
  return {
    title: { absolute: `${title} · ${site.name}` },
    description,
    alternates: { canonical: path },
    openGraph: {
      title: `${title} · ${site.name}`,
      description,
      url: `${site.origin}${path}`,
      siteName: site.name,
      type: "website",
      images: [
        {
          url: "/opengraph-image",
          width: 1200,
          height: 630,
          alt: "Nextbell. A little ahead. A lot more present.",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: ["/opengraph-image"],
    },
  };
}

export const supportEmail = `mailto:${site.email}?subject=Nextbell%20support`;
