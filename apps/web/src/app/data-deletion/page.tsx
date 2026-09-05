import { PolicyPage } from "@/components/policy-page";
import { deletion } from "@/content/policies";
import { pageMetadata } from "@/content/site";
export const metadata = pageMetadata(
  "Remove your data",
  deletion.summary,
  "/data-deletion",
);
export default function DataDeletion() {
  return <PolicyPage content={deletion} />;
}
