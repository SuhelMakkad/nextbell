"use client";
import { useState } from "react";
import { features } from "@/content/home";
import { Icon } from "./icon";
const choices = [
  { minutes: 10, time: "2:50 PM" },
  { minutes: 5, time: "2:55 PM" },
] as const;

export function ReminderDemo() {
  const [selected, setSelected] = useState<readonly number[]>([10, 5]);
  return (
    <div className="reminder-demo">
      <div className="demo-event">
        <span className="demo-event-dot" />
        <div>
          <strong>Design catch-up</strong>
          <span>Today, 3:00 PM</span>
        </div>
        <span className="demo-tag">Example</span>
      </div>
      <fieldset>
        <legend>A little heads-up</legend>
        <div className="reminder-choices">
          {choices.map((choice) => (
            <button
              type="button"
              key={choice.minutes}
              aria-pressed={selected.includes(choice.minutes)}
              onClick={() =>
                setSelected((current) =>
                  current.includes(choice.minutes)
                    ? current.filter((minute) => minute !== choice.minutes)
                    : [...current, choice.minutes],
                )
              }
            >
              <Icon
                name={selected.includes(choice.minutes) ? "check" : "plus"}
              />
              {choice.minutes} min before
            </button>
          ))}
        </div>
      </fieldset>
      <p className="demo-result" aria-live="polite" aria-atomic="true">
        <Icon name="bell" />
        {selected.length
          ? `A nudge at ${choices
              .filter((choice) => selected.includes(choice.minutes))
              .map((choice) => choice.time)
              .join(" and ")}.`
          : "Just on your agenda. No alarms."}
      </p>
      <p className="demo-caption">{features.reminders.note}</p>
    </div>
  );
}
