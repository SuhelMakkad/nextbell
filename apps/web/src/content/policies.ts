import { site } from "./site";

export type ContentSection = {
  id: string;
  title: string;
  paragraphs: readonly string[];
  steps?: readonly string[];
  links?: readonly { label: string; href: string }[];
};
export type PolicyContent = {
  title: string;
  description: string;
  summary: string;
  sections: readonly ContentSection[];
};

export const privacy: PolicyContent = {
  title: "Your plans stay personal.",
  description: "Privacy policy",
  summary:
    "Your calendars and reminder settings live on your device. Nextbell has no advertising, analytics, or backend that collects your calendar and task data.",
  sections: [
    {
      id: "who-we-are",
      title: "Who operates Nextbell",
      paragraphs: [
        `Nextbell is a calendar and task reminder app operated by ${site.operator}. This policy covers the mobile app and nextbell.org. For privacy questions, contact ${site.email}. The app is currently in development and is not yet publicly available in app stores.`,
      ],
    },
    {
      id: "google-data",
      title: "The Google data you allow us to access",
      paragraphs: [
        "When you connect a Google account, Nextbell uses your account identity to keep each connection separate. With your permission, it reads your calendar list, calendar names, colors and access levels, and event details returned by Google, including titles, times, recurrence information, attendance status, locations and meeting links. It also reads your selected Google task lists and tasks, including their titles, dates and completion status.",
        "Shared and subscribed calendars use your existing Google permissions. The owner does not need to connect their account. Private event details are limited to what Google returns. Availability-only calendars expose anonymous busy periods rather than event titles or links.",
        "Calendar access is read-only. Nextbell settings do not change Google events, visibility, subscriptions, sharing, or Google reminders. The Google Tasks permission allows task updates because completing a task in Nextbell sends its completion status to Google. Offline completions are queued on your device and marked pending until Google accepts them.",
        "Nextbell uses Google data to display your plans, synchronize changes, and schedule the reminders you choose. Nextbell’s use and transfer of information received from Google APIs adheres to the Google API Services User Data Policy, including its Limited Use requirements. Google data is not sold, used for advertising, or used to train generalized AI models.",
      ],
      links: [
        {
          label: "Google API Services User Data Policy",
          href: "https://developers.google.com/terms/api-services-user-data-policy",
        },
        {
          label: "Google Privacy Policy",
          href: "https://policies.google.com/privacy",
        },
      ],
    },
    {
      id: "on-device",
      title: "What stays on your device",
      paragraphs: [
        "Downloaded events, busy blocks and tasks, calendar selections, reminder defaults and overrides, task alarm times, handled alarms, queued completions and synchronization status are stored locally. No Nextbell backend receives this calendar or task content. Data remains until it is replaced during synchronization, removed when access is lost, or deleted by you. App storage is excluded from backups where configured by the platform.",
        "Google credentials use native authorization storage on Android and secured, device-only Keychain storage on iOS. They are kept outside the app’s SQLite database and application logs. Google still receives the requests needed to authorize your account, refresh data and complete tasks.",
        "Scheduled alarms can work offline. On Android, scheduled alarm content is kept in device-protected app storage to restore future alarms after reboot. Alarm titles may appear on your lock screen. Your phone’s notification privacy settings control what others may see. Someone using your unlocked phone may be able to view downloaded plans.",
      ],
    },
    {
      id: "website-support",
      title: "Website visits and support",
      paragraphs: [
        "This website does not offer account sign-in, analytics, advertising, tracking cookies, a waitlist, or a contact form. Fonts and artwork are bundled with the site. The website is prepared for Vercel hosting, with its domain managed through Cloudflare. Hosting and domain providers may process technical request information such as IP addresses, requested URLs, device or browser information and timestamps to deliver and protect their services. Their own policies govern that processing and retention.",
        `If you email ${site.email}, your email address, message and any attachments are processed through the operator’s email provider, Gmail, to respond to your request. Correspondence is kept as needed to provide support and resolve the request; you can ask for its deletion. Please do not send passwords, authorization tokens or private event details.`,
        "Opening a meeting link, Google event link, email link or other external link takes you to another app or service with its own privacy practices.",
      ],
      links: [
        {
          label: "Vercel Privacy Notice",
          href: "https://vercel.com/legal/privacy-policy",
        },
        {
          label: "Cloudflare Privacy Policy",
          href: "https://www.cloudflare.com/privacypolicy/",
        },
      ],
    },
    {
      id: "deletion",
      title: "Your choices and deletion",
      paragraphs: [
        "You can change connected accounts, selected calendars, task lists and reminder rules in Settings. Turning a calendar off cancels its pending alarms but keeps its custom preferences so you can use them again.",
        "Remove an account in Settings → Accounts & calendars to delete its cached content, preferences, queued changes, stored authorization and pending alarms. This does not delete your Google account, events or tasks, and cannot undo completions already sent to Google. You can also revoke Nextbell’s access in your Google Account.",
        "On iOS, remove connected accounts before uninstalling to clear their Keychain sessions; iOS can retain Keychain items across reinstalls. This website cannot remotely erase data held only on your device. Our removal guide explains the available steps.",
      ],
      links: [{ label: "How to remove your data", href: "/data-deletion" }],
    },
    {
      id: "changes",
      title: "Changes and contact",
      paragraphs: [
        `We will update this page when data practices change. This version was reviewed on ${site.reviewedOn}. Contact ${site.operator} at ${site.email} with questions or to request deletion of support correspondence.`,
      ],
    },
  ],
};

export const terms: PolicyContent = {
  title: "A few things to know.",
  description: "Terms of use",
  summary:
    "Nextbell is designed to help you arrive a little earlier and feel a little calmer. These terms explain how to use the app and what to expect.",
  sections: [
    {
      id: "using-nextbell",
      title: "Using Nextbell",
      paragraphs: [
        `Nextbell is provided by ${site.operator}. These terms apply to the Nextbell mobile app and nextbell.org. By using them, you agree to these terms. The mobile app is currently coming soon; no public store availability is implied by this website.`,
        "Use Nextbell lawfully and only with accounts and calendars you are authorized to access. You are responsible for the accounts you connect, your reminder choices, and keeping your device and Google account secure. Do not misuse the service or interfere with its operation.",
      ],
    },
    {
      id: "google",
      title: "Your Google connection",
      paragraphs: [
        "Google’s services, permissions, terms and availability apply independently. Access to a shared calendar may change or be revoked by its owner or administrator. Nextbell cannot grant access that Google does not allow.",
        "Calendar content is read-only in Nextbell. Completing a task updates Google Tasks; a completion made offline may be sent later when synchronization succeeds. Removing an account discards unsent changes for that account. Your content remains yours.",
      ],
      links: [
        {
          label: "Google Terms of Service",
          href: "https://policies.google.com/terms",
        },
        { label: "Nextbell Privacy Policy", href: "/privacy" },
      ],
    },
    {
      id: "alarms",
      title: "Alarms have practical limits",
      paragraphs: [
        "Alarm delivery depends on your permissions, device, operating system, audio settings, system limits and power restrictions. Background refresh is controlled by the operating system. Updates made elsewhere are reflected only after a successful refresh. Previously scheduled alarms can fire offline, but new or changed events cannot be downloaded without a connection.",
        "Check scheduling coverage and test alarms on your own device. Android force-stop can prevent alarms until you reopen the app. Nextbell does not guarantee that every reminder will be delivered and is not intended for emergency, medical or other safety-critical use. Use an appropriate backup for essential commitments.",
      ],
    },
    {
      id: "ownership",
      title: "Content and ownership",
      paragraphs: [
        "You retain ownership of your calendar and task content. Google and other third parties retain their respective trademarks and services. Nextbell is an independent app and is not affiliated with or endorsed by Google, Apple or their app stores.",
        "The Nextbell name, original artwork and site content belong to their respective rights holders. Software and bundled fonts may be subject to separate open-source licenses; those licenses continue to apply.",
      ],
    },
    {
      id: "availability",
      title: "Availability and responsibility",
      paragraphs: [
        "Nextbell is planned as a free app without advertising or subscriptions. Features may change as the app develops. It is provided as available, without a promise of uninterrupted or error-free operation, to the extent permitted by applicable law. Nothing in these terms excludes rights or responsibilities that cannot legally be excluded.",
        "You can stop using Nextbell at any time. Remove connected accounts before uninstalling to clear stored sessions and queued operations. Changes to these terms will appear on this page with a revised review date.",
      ],
      links: [{ label: "Remove your data", href: "/data-deletion" }],
    },
    {
      id: "contact",
      title: "Get in touch",
      paragraphs: [
        `For questions about these terms, contact ${site.operator} at ${site.email}. Reviewed ${site.reviewedOn}.`,
      ],
    },
  ],
};

export const deletion: PolicyContent = {
  title: "Your data. Your choice.",
  description: "Remove your data",
  summary:
    "Nextbell stores your plans and preferences on your device. You can remove a connected account and its local data directly in the app.",
  sections: [
    {
      id: "remove-account",
      title: "1. Remove a connected account",
      paragraphs: [
        "Use the phone on which Nextbell is installed. Repeat these steps for each account you want to remove.",
      ],
      steps: [
        "Open Nextbell → Settings → Accounts & calendars.",
        "Choose the connected account and select Remove account.",
        "Confirm removal. Nextbell removes that account’s downloaded calendars, events, busy blocks and tasks, account preferences, reminder overrides, stored authorization, pending alarms and queued task completions.",
        "Review Settings for any unresolved cancellation error and retry if the operating system could not cancel an alarm.",
      ],
    },
    {
      id: "what-remains",
      title: "2. Understand what this changes",
      paragraphs: [
        "Removing an account from Nextbell does not delete your Google account, Google Calendar events, calendar subscriptions or Google Tasks. Task completions already sent to Google are not reversed. Unsent completions are discarded. Other accounts connected to Nextbell and app-wide preferences remain.",
        "Turning a calendar off is different: it stops synchronization, hides it from the agenda and cancels its alarms while retaining your custom preferences. Use account removal when you want its data and preferences deleted.",
      ],
    },
    {
      id: "revoke-access",
      title: "3. Revoke access at Google, if you wish",
      paragraphs: [
        "Open your Google Account’s third-party connections page, select Nextbell and remove its access. Repeat for each Google account. Revoking Google access prevents future authorized access; it does not remotely erase downloaded data from your phone. Remove the account inside Nextbell as well.",
      ],
      links: [
        {
          label: "Manage your Google connections",
          href: "https://myaccount.google.com/connections",
        },
      ],
    },
    {
      id: "all-local-data",
      title: "4. Remove all local app data",
      paragraphs: [
        "Remove every connected account first, then uninstall Nextbell. On Android, you can also clear Nextbell’s storage in your phone’s app settings to reset local app preferences. Menu names vary by device.",
        "On iOS, Keychain sessions can survive an uninstall. Remove connected accounts in Nextbell before uninstalling so these sessions are cleared. If you already uninstalled, reinstall the app and remove any restored accounts, then uninstall again. Google access can also be revoked using the link above.",
      ],
    },
    {
      id: "help",
      title: "Need a hand?",
      paragraphs: [
        `Email ${site.email} for removal assistance or to request deletion of email support correspondence. Include the platform and app version, but no passwords, authorization tokens or private meeting details.`,
        "There is no separate Nextbell web account or server copy of your calendar data to delete. This website and its operator cannot remotely erase device-only data or delete your Google account. If you no longer have your phone, use your device provider’s lost-device controls and revoke access in your Google Account.",
      ],
      links: [
        {
          label: "Contact support",
          href: `mailto:${site.email}?subject=Nextbell%20data%20removal`,
        },
      ],
    },
  ],
};
