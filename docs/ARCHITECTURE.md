# Architecture

## Repository boundaries

The pnpm workspace contains `apps/mobile` (Flutter/Dart and its local native plugin), `apps/web` (Next.js public pages and API routes), and `packages/cloud` (server domain, contracts, Google clients and Firestore persistence). Git, CI, toolchain pins and documentation live at the repository root. Flutter owns Dart and Gradle dependencies; pnpm owns JavaScript dependencies in one root lockfile. Root scripts delegate directly without another task orchestrator.

The website uses server components for public publishing content, typed content modules and shared document/navigation layouts. Only the interactive reminder example needs client state. Server-only API routes import `packages/cloud`; public pages never import credentials or user data. The Android cloud beta uses Firebase identity, encrypted server Google grants and device caches. See [CLOUD_BETA.md](CLOUD_BETA.md) for data flow, deployment and deletion/rollback. Future dashboard routes can use the same versioned domain layer with a separately implemented browser session.

## Boundaries

Android composes `CloudAccountRepository`, `CloudSync` and `CloudApi` through the `SyncEngine` interface. The original `SyncCoordinator` below remains for the iOS prototype and demo. Cloud preferences, device state, pending operations, revision cursors and downloaded records occupy separate record kinds; no SQLite schema reset is required. Existing development data is cleared only by an explicit beta reset choice.

`lib/core/models.dart` defines immutable value objects and JSON persistence contracts. `features/reminders/domain/reminder_planner.dart` is pure Dart: UTC arithmetic, precedence, suppression, stable identities and shared-event deduplication. It has no network, platform, database or widget calls.

`core/data/repositories.dart` defines account, source, calendar, task and reminder interfaces. `features/sync/data/google_gateway.dart` implements the three Google content repositories with typed Google clients, account-specific authorization, pagination, bounded retries and sanitized errors. Source discovery never writes Google calendar preferences. Completion is the sole content mutation and sends only `status: completed`.

`SyncCoordinator` orchestrates metadata, snapshots, outbox writes and reconciliation. Calendar and Tasks discovery fail independently. A renewable SQLite lease coordinates foreground/background engines. Fetches happen outside transactions; commits check current account existence, removal tombstones, source mode and effective permissions. Successful collections atomically replace only that source. A failed collection retains its previous snapshot and shows an error. A successful empty snapshot removes canceled/deleted items. Access loss clears inaccessible fields and cancels alarms; role changes pause alarms for explicit review.

`AppServices` composes repositories, coordinates user commands and owns lifecycle. Riverpod exposes services and reactive snapshots. GoRouter owns route identity/transitions. Features own their presentation, while reusable theme/motion components own timing and reduced-motion behavior.

## Local persistence

Drift schema v1 uses a versioned records table with `(id, kind)` primary key and `(owner, kind)` index, JSON payloads separated by kind: account, source, entry, taskList, task, override, settings, alarm, handled, health, lease and account-removal tombstone. Source preferences are separate from fetched entries; turning a source off never deletes its overrides. Source/window snapshots and settings changes use SQLite transactions with WAL. The bounded 97-day window is a deliberate v1 constraint. Add typed tables/projections and incremental UI queries if profiling shows larger accounts require them.

Never put tokens or raw OAuth responses in records/logs. Android schedules use device-protected native preferences so boot restoration works before Flutter starts. iOS sessions are Keychain-protected. Platform backup exclusions keep local preferences/caches from being restored as cross-device settings. A hashed removal tombstone prevents a stale in-flight native restore from resurrecting a removed account; it contains no email or event details.

For future migrations: export a Drift schema snapshot, increment `schemaVersion`, add an explicit non-destructive migration, and test opening the previous version plus rollback and retained overrides. Do not reset the database to ship a schema change. Schema creation/reopen, index presence, rollback and handled persistence are tested now; there is no v2 migration yet.

## Alarm identity and time

Timed events use Google-expanded occurrence instants. Recurrence and DST expansion stay with Google. All-day and task dates remain date-only. Phone-local formatting never changes a persisted alarm instant. Task alarms are independent UTC instants chosen locally and do not move when Google's task date changes.

Identifiable event instances coalesce by iCalUID (or calendar/provider ID fallback), original recurring-instance start, and firing instant. Each alarm retains all contributing source IDs. Busy blocks have separate identities and cannot be equated to a meeting by time alone. An anonymous block's identity is its calendar/start; merging or splitting a successfully refreshed snapshot reconciles old alarms. Overrides for busy blocks stop at calendar level.

The planner applies occurrence → series → calendar → app offsets. Source mode is the master gate. All-day events, canceled occurrences (absent from snapshots), explicitly declined invitations and completed tasks do not ring. A watched event without the user's attendee record still qualifies.

Native action queues commit handled state to SQLite before acknowledgement. Dismiss suppresses one alarm ID; subsequent offsets remain. Snoozes persist natively and survive app termination. Collision reconciliation merges an identifiable occurrence at an identical firing instant. Reconciliation is serialized inside database transactions across engines; only successful native schedules are reported as coverage. New earlier alarms can evict later unhandled schedules when the OS is full. Capacity/permission failures remain visible and retryable.

## Platform limits

Android uses `setAlarmClock`, exact-alarm special access, a foreground alarm audio service and immediate native controls. Boot/package/clock/timezone/permission receivers restore future schedules and skip expired alarms. Android force-stop is a distinct OS state: delivery and background work may remain blocked until the user opens the app again. Do not promise delivery through force-stop or an OEM's unsupported power restrictions.

iOS 26 uses AlarmKit fixed dates with custom native stop/snooze intents. AlarmKit authorization is independent of regular notifications. Native presentation, Focus behavior and limits must be verified on signed physical devices. No Flutter animation delays audio or native controls.

Refresh occurs on launch/resume, manually, every five minutes while active and via requested 15-minute background work. The OS may defer/suppress background execution. The Android beta also uses server watches, durable tasks and push hints, with periodic fallback. Remote changes still require a successful phone download and native reconciliation; an offline or force-stopped device cannot apply them. Already downloaded native alarms work without a network. The 90-day/capacity coverage is visible; opening the app extends it.

## Extensions

Add a provider by implementing repositories and preserving provenance. Add reminder rule types in the pure planner before introducing presentation controls. Add platform operations to the Pigeon schema and regenerate all targets together. Keep event editing, direct ICS imports, standalone reminders, analytics and subscriptions out of v1. Cross-device settings are provided by the Android cloud beta; local Snooze/Dismiss state stays device-specific.
