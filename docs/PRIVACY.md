# Privacy policy source

The publishing policy is now maintained as typed content in `apps/web/src/content/policies.ts` (`privacy`) and rendered at `/privacy` by the shared document layout. It supersedes the original publication draft.

Operator: **Suhel Makkad**. Contact: **makadsuhel11@gmail.com**. Reviewed September 5, 2026.

Canonical URL reserved for publication: **https://nextbell.org/privacy**. This implementation is local; the document has not been published externally.

The policy covers authorized Google data, read-only calendars, task completion writes and offline queues, Android cloud/Firebase storage, encrypted server credentials, device caches and native iOS credentials, lock-screen alarm data, account removal and iOS Keychain retention, technical hosting data, support email, and the Google API Services User Data Policy including Limited Use.

Device-only data cannot be deleted remotely through the website. See `/data-deletion` for the user-facing removal instructions. Reconcile this policy with the shipping build and hosting configuration before publishing; update it when adding web accounts, server storage or other new data processing.

The cloud-beta policy update must be reachable from the beta before inviting testers. Production publication is a separate release action. Account deletion includes cloud data; see CLOUD_BETA.md for active-copy removal, seven-day backups, minimal deletion markers and support-assisted deletion.
