type FeatureCopy = {
  title: readonly [string, string];
  description: string;
  note: string;
};

export const features = {
  reminders: {
    title: ["Right on time.", "A little before, actually."],
    description:
      "Pick reminders in minutes, hours, or days. Set your usual rhythm, then make exceptions for a calendar, a recurring meeting, or just this one.",
    note: "Try the chips. This preview won’t set an alarm.",
  },
  calendars: {
    title: ["Different calendars.", "One calm place."],
    description:
      "Connect multiple Google accounts. Bring in the shared, subscribed, and imported calendars you can already access, and choose which ones ring.",
    note: "Your access. Your choices. No owner sign-in needed.",
  },
  travel: {
    title: ["A new timezone.", "The same moment."],
    description:
      "Travel without doing the maths. Event times follow your phone’s timezone, while your reminders stay anchored to the actual meeting.",
    note: "One meeting, shown in two places. Summer example.",
  },
  tasks: {
    title: ["A home for the", "little to-dos, too."],
    description:
      "Keep Google Tasks close to your calendar. Give a task its own alarm time, or leave it quietly on your list. Completions sync back to Google.",
    note: "Offline? Your completion waits until you reconnect.",
  },
} as const satisfies Record<string, FeatureCopy>;
