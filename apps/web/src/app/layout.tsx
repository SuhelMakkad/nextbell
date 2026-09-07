import type { Metadata } from "next";
import localFont from "next/font/local";
import { Footer, Header } from "@/components/site-shell";
import { site } from "@/content/site";
import "./globals.css";
const manrope = localFont({
  src: "../../public/fonts/Manrope.ttf",
  variable: "--font-manrope",
  display: "swap",
  weight: "200 800",
});
export const metadata: Metadata = {
  metadataBase: new URL(site.origin),
  title: {
    default: "Nextbell — Calendar Alarms & Meeting Reminders",
    template: "%s · Nextbell",
  },
  description: site.description,
  applicationName: site.name,
  robots:
    process.env.VERCEL_ENV === "preview"
      ? { index: false, follow: false }
      : { index: true, follow: true },
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={manrope.variable}>
      <body className="flex min-h-screen flex-col">
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        <Header />
        <main id="main-content" className="flex-1" tabIndex={-1}>
          {children}
        </main>
        <Footer />
      </body>
    </html>
  );
}
