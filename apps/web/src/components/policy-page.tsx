import Link from "next/link";
import type { PolicyContent } from "@/content/policies";
import { site, supportEmail } from "@/content/site";
import { Icon } from "./icon";

export function PolicyPage({ content }: { content: PolicyContent }) {
  return (
    <div className="container document-page">
      <div className="document-heading entrance">
        <p className="eyebrow">{content.description}</p>
        <h1>{content.title}</h1>
        <p className="lede">{content.summary}</p>
        <p className="review-date">
          Reviewed {site.reviewedOn} · {site.operator}
        </p>
      </div>
      <div className="document-grid">
        <aside>
          <nav aria-label="On this page">
            <p className="eyebrow">On this page</p>
            {content.sections.map((section) => (
              <a href={`#${section.id}`} key={section.id}>
                {section.title}
              </a>
            ))}
          </nav>
        </aside>
        <article className="prose">
          {content.sections.map((section) => (
            <section id={section.id} key={section.id}>
              <h2>{section.title}</h2>
              {section.paragraphs.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
              {section.steps && (
                <ol>
                  {section.steps.map((step) => (
                    <li key={step}>{step}</li>
                  ))}
                </ol>
              )}
              {section.links && (
                <ul className="resource-links">
                  {section.links.map((link) => (
                    <li key={link.href}>
                      <Link href={link.href}>
                        {link.label}
                        <Icon name="arrow" />
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          ))}
          <div className="contact-note">
            <Icon name="bell" />
            <div>
              <h2>We’re here to help.</h2>
              <p>Questions about Nextbell or your data?</p>
              <a href={supportEmail}>{site.email}</a>
            </div>
          </div>
        </article>
      </div>
    </div>
  );
}
