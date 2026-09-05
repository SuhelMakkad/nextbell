import Image from "next/image";
import Link from "next/link";
import { publicPages, site, storeListings } from "@/content/site";
import { Icon } from "./icon";

export function Brand() {
  return (
    <Link href="/" aria-label="Nextbell home" className="brand">
      <Image src="/brand/icon.png" width={38} height={38} alt="" />
      <span>
        nextbell<span className="brand-dot">.</span>
      </span>
    </Link>
  );
}
export function Header() {
  return (
    <header className="site-header container">
      <Brand />
      <nav aria-label="Main navigation">
        <Link href="/#features">The little details</Link>
        <Link href="/support">Support</Link>
        <Link className="header-cta" href="/#availability">
          Coming soon <Icon name="arrow" />
        </Link>
      </nav>
    </header>
  );
}
export function StoreLinks() {
  return (
    <>
      {storeListings.map((listing) => (
        <a key={listing.href} className="button primary" href={listing.href}>
          {listing.label}
          <Icon name="arrow" />
        </a>
      ))}
    </>
  );
}
export function Footer() {
  return (
    <footer className="site-footer container">
      <div className="footer-top">
        <div>
          <Brand />
          <p>A little ahead. A lot more present.</p>
        </div>
        <nav aria-label="Footer navigation">
          {publicPages
            .filter((page) => page.href !== "/")
            .map((page) => (
              <Link key={page.href} href={page.href}>
                {page.label}
              </Link>
            ))}
        </nav>
      </div>
      <div className="footer-bottom">
        <span>
          © {new Date().getUTCFullYear()} {site.operator}. Made with a little
          care.
        </span>
        <a href={`mailto:${site.email}`}>{site.email}</a>
      </div>
    </footer>
  );
}
