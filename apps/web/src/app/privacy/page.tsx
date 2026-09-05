import { PolicyPage } from "@/components/policy-page";
import { privacy } from "@/content/policies";
import { pageMetadata } from "@/content/site";
export const metadata = pageMetadata(
  "Privacy policy",
  privacy.summary,
  "/privacy",
);
export default function Privacy() {
  return <PolicyPage content={privacy} />;
}
