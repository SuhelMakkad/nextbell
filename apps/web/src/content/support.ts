import { androidTest } from "./site";

export type HelpTopic = {
  id: string;
  question: string;
  answer: readonly string[];
  links?: readonly { label: string; href: string }[];
};

export const helpTopics: readonly HelpTopic[] = [
  {
    id: "android-test",
    question: "How do I join the Android test?",
    answer: [
      "Nextbell’s closed test is available for Android 8+ with Google Play services. Access is limited to invited Google accounts. Request access by emailing the Google-account address you use in Google Play; you must be added to the tester list before the invite link will work.",
      "Once invited, open the test link using that same Google account, opt in, and follow the Google Play installation link. If you see an unavailable message, check which Google account is selected. iOS is planned and is not included in this test.",
    ],
    links: [
      { label: androidTest.label, href: androidTest.href },
      { label: "Request test access", href: androidTest.requestAccessHref },
    ],
  },
  {
    id: "setup",
    question: "How do I get started?",
    answer: [
      "After installing from the Android test, connect your Google account, choose which calendars to show, then enable alarms for the calendars you want to hear. Nextbell suggests your primary calendar. Additional and newly discovered calendars stay off until you choose them.",
      "Allow the alarm permissions requested by your phone and test an alarm. You can add more Google accounts and change any choice later in Settings → Accounts & calendars. The sample-data tour does not schedule real alarms.",
    ],
  },
  {
    id: "shared",
    question: "Why is a shared or subscribed calendar missing?",
    answer: [
      "Check that the correct Google account can access it. Add or subscribe to the calendar in Google Calendar, then refresh discovery in Settings → Accounts & calendars. Sharing a calendar and adding it to your calendar list are separate steps in Google.",
      "Nextbell discovers hidden entries too, and shows the access level Google grants your account. The calendar owner never needs to sign in. New ICS or URL subscriptions must first be added in Google Calendar; Nextbell does not import them directly.",
    ],
  },
  {
    id: "modes",
    question: "What do the three calendar modes mean?",
    answer: [
      "Off hides a calendar, pauses its content synchronization and cancels its pending alarms while retaining your preferences. Show only adds events to your agenda without alarms. Show and alarm applies your reminder rules. Re-enabling refreshes the source before scheduling future reminders.",
      "If you have availability-only access, you can explicitly opt in to anonymous busy-block alarms. They are labelled “Busy — calendar name.” A block can contain several meetings and has no event title, join link or individual recurrence identity. Event and series overrides are not available for these blocks.",
    ],
  },
  {
    id: "timing",
    question: "Can I choose when a reminder rings?",
    answer: [
      "Yes. Timed events start with reminders 10 and 5 minutes before. Change app defaults in Settings → Alarms & reminders, set calendar defaults, or open an event for occurrence and series overrides. An occurrence rule takes priority over its series, then calendar, then app defaults. Reset a rule to inherit again.",
      "Choose offsets in minutes, hours or days, or turn reminders off. All-day events do not ring automatically. Canceled events and invitations you declined do not ring. Dismiss handles only the current reminder; Snooze defaults to five minutes and preserves later reminders.",
    ],
  },
  {
    id: "tasks",
    question: "How do Google Tasks reminders work?",
    answer: [
      "Select task lists in Settings → Accounts & calendars. Google’s API supplies task dates but not alarm times. Tasks stay silent until you choose a date and time in task details. That alarm keeps the instant you selected even if the Google task date later changes.",
      "Completing a task updates Google. If you are offline, the completion stays pending on your phone until synchronization succeeds. Removing its account discards unsent completions.",
    ],
  },
  {
    id: "alarm",
    question: "An alarm did not ring. What should I check?",
    answer: [
      "Open Settings → Alarms & reminders, review alarm permissions and scheduling coverage, and test an alarm. Confirm the calendar is in Show and alarm mode, the event is timed and not declined, and reminder offsets are enabled and still in the future. Reconnect Google if access has expired.",
      "On Android, check exact-alarm, notification and full-screen access, alarm volume and device power restrictions. Force stop can suppress alarms and background work until you open Nextbell again. Future schedules are restored after reboot where the device allows it, but manufacturer battery controls can interfere.",
      "On iOS, AlarmKit authorization is separate from ordinary notification permission. Check the app’s permission and your actual phone’s alarm behavior, including Silent and Focus modes. System alarm limits can leave partial scheduling coverage. Errors remain visible until resolved; expired reminders are skipped instead of ringing a backlog.",
    ],
  },
  {
    id: "offline",
    question: "Will alarms work without an internet connection?",
    answer: [
      "Already scheduled alarms can fire offline. Changes made to events elsewhere need a successful refresh before Nextbell knows about them. Open the app regularly, especially after important calendar changes.",
      "Nextbell refreshes on launch or resume, on manual refresh and every five minutes while active. Background refresh is requested at 15-minute intervals, but the operating system controls when it runs. Last-sync status and actual scheduling coverage are available in Settings.",
    ],
  },
  {
    id: "travel",
    question: "What happens when I travel or daylight saving changes?",
    answer: [
      "Event and busy-block times are stored as UTC instants and displayed in your phone’s current timezone. Reminder offsets count back from that same instant. Google expands recurring events, preserving the calendar’s daylight-saving rules. Date-only events and task dates stay date-only.",
      "After travel, use the correct phone timezone and open Nextbell to refresh and review scheduling coverage. A task alarm keeps the instant you originally chose; you can edit it if you want a different local time.",
    ],
  },
];
