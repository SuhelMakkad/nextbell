# Play Data safety — device-only Android 1.0.0

Recorded on 7 September 2026 for package `com.suhel.nextbell`, version code 1, built from main commit `680ca1e`. These answers describe the shipped app and Google SDK/API behavior, not the unmerged cloud-sync feature branch. They were submitted with the closed-test release. Reassess every answer before adding a backend, analytics SDK, new data flow, or app-account system.

## Submitted collection answers

Play defines collection as transmitting data off the device, including through an SDK. The absence of a Nextbell backend does not by itself justify answering “no collection.” Google authorization, account selection, authenticated API requests, and explicit task completion communicate with Google over HTTPS.

| Play data type | Collected | Ephemeral | Required or optional | Purposes |
| --- | --- | --- | --- | --- |
| Personal info → Email address | Yes | No | Required | App functionality; account management |
| Personal info → User IDs | Yes | No | Required | App functionality; account management |
| App activity → Other actions | Yes | No | Optional | App functionality |

“Other actions” covers a user's explicit Google Tasks completion. Nextbell sends completion status and the relevant task/list identifiers; it does not upload a task's title or notes. The operation is queued locally when offline. Identity is required for the connected Google integration, even though the app also has an optional sample-data tour.

All declared transmission uses encryption in transit. Data is not marked ephemeral because Google account and task state persist. No advertising ID, ads, analytics, or crash-reporting SDK is part of this build.

## Sharing and locally held content

The submitted form does not mark these types as “shared.” This classification relies on Google's exemption for user-initiated transfers to another party that the user reasonably expects: connecting a Google account, authorizing the requested Calendar/Tasks access, and explicitly completing a Google task. It is not a blanket exemption for arbitrary Google services or future cloud processing. Collection remains declared independently.

Calendar event content, downloaded task titles/notes, reminder rules, handled states, and schedule preferences remain on the phone. The app downloads calendar content and uses it locally; it does not send event titles or descriptions to Nextbell servers. Google requests still include account/calendar identifiers, query windows, and authorized API operations. Cached content being local is separate from those outbound requests.

Display-name/profile data is received from Google for the account UI. The app does not independently upload that cached profile content. Credentials use platform storage outside SQLite and are sent only as required for Google authentication/API access; never include tokens in logs or this record.

## Account and deletion answers

- The app does not let users create a Nextbell server account. Users connect an existing external Google account.
- External-account sign-in: Yes. Creation sources: employment/enterprise accounts and Other (personal accounts created with Google).
- User deletion requests supported: Yes, through the public [data-removal instructions](https://www.nextbell.org/data-deletion) and operator support.
- Removing a connected account in the app cancels its pending alarms and removes its cached content, preferences, queued operations, and local credentials. Users can also clear app storage or uninstall and separately revoke Google access.
- The website cannot remotely erase device-only data or delete a Google account. Completing or deleting Nextbell's local data does not remove Google calendar events or completed task state from Google.

Reviewer sign-in details live only in Play Console. Public support is `makadsuhel11@gmail.com`. The privacy and deletion pages describe the device-only release and must be revised before cloud functionality ships.

## Sources used for classification

- [Google Play Data safety definitions and exemptions](https://support.google.com/googleplay/android-developer/answer/10787469).
- [Google Play account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111).
- [Google Checks data-type taxonomy](https://developers.google.com/checks/guide/code-compliance/review-findings/supported-data-types).
- [Google Play services data-disclosure guidance](https://developers.google.com/android/guides/play-data-disclosure).
