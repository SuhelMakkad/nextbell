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
    "The Android private beta synchronizes selected Google data and reminder settings through Nextbell cloud. Downloaded alarms work on your phone. We do not include advertising or analytics.",
  sections: [
    {
      id: "who-we-are",
      title: "Who operates Nextbell",
      paragraphs: [
        `Nextbell is a calendar and task reminder app operated by ${site.operator}. This policy covers the mobile app and nextbell.org. For privacy questions, contact ${site.email}. The app is in development and is not publicly available in app stores. These cloud practices apply to the Android private beta. Earlier development builds and the current iOS prototype use direct Google access on the device.`,
      ],
    },
    {
      id: "google-data",
      title: "The Google data you allow us to access",
      paragraphs: [
        "When you connect a Google account, Nextbell uses your account identity to keep each connection separate. With your permission, it reads your calendar list, calendar names, colors and access levels, and event details returned by Google, including titles, times, recurrence information, attendance status, locations and meeting links. It also reads your selected Google task lists and tasks, including their titles, dates and completion status.",
        "Shared and subscribed calendars use your existing Google permissions. The owner does not need to connect their account. Private event details are limited to what Google returns. Availability-only calendars expose anonymous busy periods rather than event titles or links.",
        "Calendar access is read-only. Nextbell settings do not change Google events, visibility, subscriptions, sharing, or Google reminders. The Google Tasks permission allows task updates because completing a task in Nextbell sends its completion status to Google. Offline completions are queued on your device, then processed by the backend and marked pending until Google accepts them.",
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
      title: "Cloud sync and your phone",
      paragraphs: [
        "Your primary Google identity is your Nextbell account. Connected account identities, selected calendar events and busy blocks, task lists and selected tasks, reminder settings, task alarm times, device names, push tokens and synchronization health are stored by Nextbell cloud to keep your phones up to date. We download seven past days and 90 future days of calendar occurrences. Successful refreshes replace cached data. Your phone also keeps a local copy, queued edits and native alarm schedules. Snooze and Dismiss remain specific to that phone. App storage is excluded from backups where configured by the platform.",
        "Firebase Authentication manages Android beta sign-in. Google refresh tokens for ongoing calendar and task access are encrypted with Google Cloud KMS before storage; the server OAuth secret is held in Secret Manager. Credentials are excluded from SQLite and application logs. Native iOS prototype credentials stay in the device Keychain. Google receives authorization, refresh and task-completion requests.",
        "The backend uses Google Cloud/Firebase for authentication, storage, jobs, encryption and push delivery, and Vercel for API hosting. Primary database, key, secret and worker regions are configured in Mumbai; authentication, push delivery, provider logs and support may be processed elsewhere. Push messages contain a revision and a generic change type, not meeting titles or Google credentials. We collect scheduling coverage and permission status to show whether each phone has applied changes.",
        "Superseded snapshots and temporary refresh pages are removed by maintenance after 24 hours; retry and deduplication records expire within 7–30 days. Cloud backups and point-in-time recovery retain data for up to seven days. Account deletion removes active cloud data asynchronously. Minimal account-deletion markers remain to reject late requests and prevent deleted data returning. Backup copies expire with their retention period. No support staff access to Google content is permitted except as allowed by Google’s Limited Use policy and with the necessary user authorization.",
        "Scheduled alarms can work offline. On Android, scheduled alarm content is kept in device-protected app storage to restore future alarms after reboot. Alarm titles may appear on your lock screen. Your phone’s notification privacy settings control what others may see. Someone using your unlocked phone may be able to view downloaded plans.",
      ],
    },
    {
      id: "website-support",
      title: "Website visits and support",
      paragraphs: [
        "This website does not offer account sign-in, analytics, advertising, tracking cookies, a waitlist, or a contact form. Fonts and artwork are bundled with the site. The website uses Vercel hosting, with its domain managed through Cloudflare. Hosting and domain providers may process technical request information such as IP addresses, requested URLs, device or browser information and timestamps to deliver and protect their services. Their own policies govern that processing and retention.",
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
        "Remove a connected Google account in Settings → Accounts & calendars to remove its content, preferences, queued changes and stored authorization from Nextbell. Local alarms are canceled immediately; cloud removal and changes on other phones require a connection. Use Settings → Devices & sync → Delete Nextbell account to delete the whole cloud account. Uninstalling alone does not delete cloud data. This does not delete your Google account, events or tasks, and cannot undo completions already sent to Google. You can also revoke Nextbell’s access in your Google Account.",
        "Signing out of an Android beta phone unregisters it, clears local data and cancels its alarms while keeping your cloud account. Other offline phones apply removal when they reconnect; until then they may retain downloaded information and ring previously scheduled alarms. On iOS, remove connected accounts before uninstalling to clear their Keychain sessions; iOS can retain Keychain items across reinstalls. This website cannot remotely erase data held only on your device. Our removal guide explains the available steps.",
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
        "Alarm delivery depends on your permissions, device, operating system, audio settings, system limits and power restrictions. Cloud sync uses Google change notifications and periodic refresh. Push delivery and phone background work are controlled by Google and the operating system and may be delayed or missed. Updates made elsewhere are reflected only after a successful refresh. Previously scheduled alarms can fire offline, but new or changed events cannot be downloaded without a connection.",
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
    "Delete your Nextbell cloud account from the Android beta or request help by email. You can also remove individual connected Google accounts or clear just one phone.",
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
        "Confirm removal. Nextbell cancels this phone’s alarms and queues removal of the account’s cloud content, preferences and Google authorization. Removal reaches the backend and other phones when they connect. Task completions already accepted by Google cannot be reversed.",
        "Review Settings for any unresolved cancellation error and retry if the operating system could not cancel an alarm.",
      ],
    },
    {
      id: "delete-cloud-account",
      title: "Delete your entire Nextbell cloud account",
      paragraphs: [
        "Open Settings → Devices & sync → Delete Nextbell account. Confirm and sign in again with your primary Google account. This queues deletion of your connected Google data, credentials, devices and reminder preferences. Keep a connection until the request is accepted. Your Google account, events and tasks are not deleted.",
        "Active cloud data is removed asynchronously. Reachable phones cancel schedules and clear local data on their next refresh. Offline phones may ring old alarms until they reconnect or you clear them locally. Superseded temporary copies are cleaned up after 24 hours; backups expire within seven days. Minimal deletion markers prevent late jobs from recreating data.",
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
        "In the Android beta, use Settings → Devices & sync → Sign out of this phone while online to unregister the phone, cancel its alarms and clear its cache. Your cloud account remains. To remove cloud data too, choose Delete Nextbell account and confirm with Google before uninstalling. You can also clear Android app storage; that alone does not delete the cloud account. Menu names vary by device.",
        "On iOS, Keychain sessions can survive an uninstall. Remove connected accounts in Nextbell before uninstalling so these sessions are cleared. If you already uninstalled, reinstall the app and remove any restored accounts, then uninstall again. Google access can also be revoked using the link above.",
      ],
    },
    {
      id: "help",
      title: "Need a hand?",
      paragraphs: [
        `Email ${site.email} for removal assistance or to request deletion of email support correspondence. Include the platform and app version, but no passwords, authorization tokens or private meeting details.`,
        "To request deletion without the app, email us from your Nextbell sign-in address with the subject “Nextbell account deletion.” We verify control of that address before processing the cloud deletion and reply when it is complete. This website cannot remotely erase device-only data or delete your Google account. If you no longer have your phone, use your device provider’s lost-device controls and revoke access in your Google Account.",
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
