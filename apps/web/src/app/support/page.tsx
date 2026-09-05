import Link from "next/link";
import { Icon } from "@/components/icon";
import { helpTopics } from "@/content/support";
import { pageMetadata, site, supportEmail } from "@/content/site";
export const metadata = pageMetadata(
  "Support",
  "A little help with Nextbell. Set up calendars, customize reminders, troubleshoot alarms, and contact Suhel Makkad.",
  "/support",
);
export default function Support() {
  return (
    <div className="container support-page">
      <div className="document-heading entrance">
        <p className="eyebrow">A little help</p>
        <h1>
          Let’s get you
          <br />
          <span className="accent-text">back on time.</span>
        </h1>
        <p className="lede">
          From your first calendar to your next timezone.
          <br />
          Find a quick answer, or say hello.
        </p>
      </div>
      <div className="support-grid">
        <aside className="support-contact">
          <span className="icon-badge">
            <Icon name="bell" />
          </span>
          <h2>
            A human, on the
            <br />
            other end.
          </h2>
          <p>Can’t find what you need? Tell Suhel what’s happening.</p>
          <a className="text-link" href={supportEmail}>
            Email support
            <Icon name="arrow" />
          </a>
          <span className="support-address">{site.email}</span>
          <p className="small-copy">
            Include your app and OS versions and a non-private example. Please
            keep passwords and private meeting details to yourself.
          </p>
          <Link href="/data-deletion">Looking to remove your data?</Link>
        </aside>
        <div className="faq-list">
          {helpTopics.map((topic, index) => (
            <details id={topic.id} key={topic.id}>
              <summary>
                <span className="faq-number">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <h2>{topic.question}</h2>
                <Icon name="plus" />
              </summary>
              <div className="faq-answer">
                {topic.answer.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </div>
            </details>
          ))}
        </div>
      </div>
    </div>
  );
}
