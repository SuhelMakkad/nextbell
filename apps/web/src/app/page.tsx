import Image from "next/image";
import { features } from "@/content/home";
import Link from "next/link";
import { Icon } from "@/components/icon";
import { ReminderDemo } from "@/components/reminder-demo";
import { StoreLinks } from "@/components/site-shell";
import { pageMetadata, site } from "@/content/site";

export const metadata = pageMetadata(
  "A little ahead. A lot more present.",
  site.description,
  "/",
);

export default function Home() {
  return (
    <>
      <section className="hero container">
        <div className="hero-copy entrance">
          <p className="eyebrow">
            <span className="status-dot" />
            For all the things you don’t want to miss
          </p>
          <h1>
            A little ahead.
            <br />A lot more
            <br />
            <span className="accent-text">present.</span>
            <span className="little-spark" aria-hidden="true">
              ✳
            </span>
          </h1>
          <p className="lede">
            Your calendar makes the plans.
            <br className="desktop-break" /> Nextbell gives you a little room to
            get ready.
          </p>
          <p className="hero-description">
            Thoughtful alarms for Google Calendar and Tasks.
            <br className="desktop-break" /> Your meetings, your people, your
            kind of heads-up.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#features">
              Meet your next reminder
              <Icon name="arrow" />
            </a>
            <span className="availability-note">
              Coming soon
              <br />
              <strong>Android & iOS</strong>
            </span>
          </div>
          <div className="hero-trust">
            <span>
              <Icon name="check" />
              Free, without ads
            </span>
            <span>
              <Icon name="shield" />
              Your data stays yours
            </span>
          </div>
        </div>
        <div className="hero-visual entrance">
          <div className="orbit orbit-one" />
          <div className="orbit orbit-two" />
          <span className="visual-star" aria-hidden="true">
            ✳
          </span>
          <div className="hero-phone">
            <Image
              src="/previews/agenda.png"
              alt="Nextbell Today agenda with sample meetings and 10- and 5-minute reminders"
              width={860}
              height={1864}
              sizes="(max-width: 700px) 260px, 310px"
              preload
            />
          </div>
          <div className="floating-reminder">
            <span className="floating-icon">
              <Icon name="bell" />
            </span>
            <div>
              <strong>A little heads-up</strong>
              <span>Your next meeting is in 10 min.</span>
            </div>
            <span className="tiny-dot" />
          </div>
          <div className="floating-note">
            <span aria-hidden="true">↳</span> room to breathe.
          </div>
        </div>
      </section>
      <div className="integration-strip container">
        <p>Your day, gently brought together.</p>
        <div>
          <span>
            <Icon name="calendar" />
            Google Calendar
          </span>
          <span>
            <Icon name="check" />
            Google Tasks
          </span>
          <span>
            <Icon name="globe" />
            Shared calendars, too
          </span>
        </div>
      </div>
      <section id="features" className="features-section container">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Small details. More peace of mind.</p>
            <h2>
              A reminder that
              <br />
              feels like <span className="accent-text">you.</span>
            </h2>
          </div>
          <p>
            Five minutes to grab a coffee. Ten to find your notes.
            <br />
            Make a little space before your next thing.
          </p>
        </div>
        <div className="feature-grid">
          <article className="feature-card reminder-card">
            <div className="card-title">
              <span className="icon-badge">
                <Icon name="bell" />
              </span>
              <span className="eyebrow">Your rhythm</span>
            </div>
            <h3>
              {features.reminders.title[0]}
              <br />
              {features.reminders.title[1]}
            </h3>
            <p>{features.reminders.description}</p>
            <ReminderDemo />
          </article>
          <article className="feature-card calendar-card">
            <div className="card-title">
              <span className="icon-badge mint">
                <Icon name="calendar" />
              </span>
              <span className="eyebrow">Your whole day</span>
            </div>
            <h3>
              {features.calendars.title[0]}
              <br />
              {features.calendars.title[1]}
            </h3>
            <p>{features.calendars.description}</p>
            <div
              className="calendar-example"
              aria-label="Examples of calendar modes"
            >
              <div>
                <span className="calendar-dot purple" />
                <strong>My work</strong>
                <span className="mode-pill">Show and alarm</span>
              </div>
              <div>
                <span className="calendar-dot green" />
                <strong>
                  Team calendar<small>Shared · Read only</small>
                </strong>
                <span className="mode-pill neutral">Show only</span>
              </div>
              <div>
                <span className="calendar-dot peach" />
                <strong>Holidays</strong>
                <span className="mode-pill neutral">Off</span>
              </div>
            </div>
            <p className="card-footnote">{features.calendars.note}</p>
          </article>
          <article className="feature-card travel-card">
            <span className="icon-badge peach">
              <Icon name="globe" />
            </span>
            <h3>
              {features.travel.title[0]}
              <br />
              {features.travel.title[1]}
            </h3>
            <p>{features.travel.description}</p>
            <div className="timezone-example">
              <div>
                <small>London</small>
                <strong>
                  10:00<span>AM</span>
                </strong>
              </div>
              <span aria-hidden="true">↔</span>
              <div>
                <small>Mumbai</small>
                <strong>
                  2:30<span>PM</span>
                </strong>
              </div>
            </div>
            <p className="card-footnote">{features.travel.note}</p>
          </article>
          <article className="feature-card task-card">
            <span className="icon-badge">
              <Icon name="check" />
            </span>
            <h3>
              {features.tasks.title[0]}
              <br />
              {features.tasks.title[1]}
            </h3>
            <p>{features.tasks.description}</p>
            <div className="task-example">
              <span className="task-check">
                <Icon name="check" />
              </span>
              <div>
                <strong>Send the meeting notes</strong>
                <span>One less thing on your mind.</span>
              </div>
              <span className="task-spark" aria-hidden="true">
                ✳
              </span>
            </div>
            <p className="card-footnote">{features.tasks.note}</p>
          </article>
        </div>
      </section>
      <section id="preview" className="preview-section">
        <div className="container preview-grid">
          <div>
            <p className="eyebrow">Less noise. More clarity.</p>
            <h2>
              Your day,
              <br />
              with a little
              <br />
              <span className="accent-text">breathing room.</span>
            </h2>
            <p className="lede">
              A focused agenda. A gentle checkmark.
              <br />
              Just the things that help you show up.
            </p>
            <ul className="preview-list">
              <li>
                <Icon name="check" />A clear view of what’s next
              </li>
              <li>
                <Icon name="check" />
                Light and dark, to match your mood
              </li>
              <li>
                <Icon name="check" />
                Playful motion that knows when to be still
              </li>
            </ul>
            <p className="small-copy">
              App previews show sample data. Reduced motion is supported.
            </p>
          </div>
          <div className="preview-phones">
            <figure>
              <div className="preview-phone dark-phone">
                <Image
                  src="/previews/agenda-dark.png"
                  alt="Nextbell Today agenda in dark mode with sample events"
                  width={860}
                  height={1864}
                  sizes="(max-width: 700px) 40vw, 230px"
                />
              </div>
              <figcaption>A calmer agenda</figcaption>
            </figure>
            <figure>
              <div className="preview-phone">
                <Image
                  src="/previews/tasks.png"
                  alt="Nextbell Google Tasks screen showing sample tasks and an explicit reminder time"
                  width={860}
                  height={1864}
                  sizes="(max-width: 700px) 40vw, 230px"
                />
              </div>
              <figcaption>The little things, together</figcaption>
            </figure>
          </div>
        </div>
      </section>
      <section className="privacy-section container">
        <div className="privacy-art" aria-hidden="true">
          <Image src="/brand/icon.png" alt="" width={120} height={120} />
          <span className="privacy-check">
            <Icon name="shield" />
          </span>
        </div>
        <div>
          <p className="eyebrow">Personal by design</p>
          <h2>Your plans stay personal.</h2>
          <p>
            The Android beta keeps selected plans and reminder settings in sync
            across your phones through Nextbell cloud. No ads. No analytics.
            Downloaded alarms can ring offline, and you control connected
            accounts and account deletion.
          </p>
          <Link href="/privacy" className="text-link">
            A little more about privacy
            <Icon name="arrow" />
          </Link>
        </div>
      </section>
      <section id="availability" className="container availability-section">
        <div className="availability-card">
          <span className="launch-badge">
            <span className="status-dot" />A good thing on its way
          </span>
          <h2>
            A little more present.
            <br />
            Coming soon.
          </h2>
          <p>
            We’re getting Nextbell ready for your everyday.
            <br />
            Free for Android 8+ and iOS 26+. No ads, no subscriptions.
          </p>
          <div className="launch-actions">
            <StoreLinks />
            <Link href="/support" className="button light">
              Get to know Nextbell
              <Icon name="arrow" />
            </Link>
          </div>
          <p className="launch-footnote">
            App store links will appear here when we’re ready.
          </p>
          <Icon name="bell" className="launch-bell" />
        </div>
        <p className="alarm-note">
          Alarms depend on your phone’s permissions and system limits. Keep the
          app up to date and check scheduling coverage.
          <br />
          <Link href="/support#alarm">A little help with alarms</Link>
        </p>
      </section>
    </>
  );
}
