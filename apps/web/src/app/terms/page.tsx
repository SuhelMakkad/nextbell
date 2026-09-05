import { PolicyPage } from "@/components/policy-page";
import { terms } from "@/content/policies";
import { pageMetadata } from "@/content/site";
export const metadata = pageMetadata("Terms of use", terms.summary, "/terms");
export default function Terms() {
  return <PolicyPage content={terms} />;
}
