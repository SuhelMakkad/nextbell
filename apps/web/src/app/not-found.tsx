import Link from "next/link";
import { Icon } from "@/components/icon";
export default function NotFound() {
  return (
    <div className="not-found container">
      <span className="icon-badge">
        <Icon name="bell" />
      </span>
      <p className="eyebrow">404 · A small detour</p>
      <h1>
        This page missed
        <br />
        its reminder.
      </h1>
      <p className="lede">Let’s get you back to somewhere familiar.</p>
      <Link className="button primary" href="/">
        Back to Nextbell
        <Icon name="arrow" />
      </Link>
      <Link className="text-link" href="/support">
        Find a little help
      </Link>
    </div>
  );
}
