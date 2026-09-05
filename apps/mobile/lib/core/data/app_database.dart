import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models.dart';

part 'app_database.g.dart';

/// Versioned records keep domain models independent of Drift-generated classes.
/// Indexed owner/kind keys support atomic per-source replacement and deletion.
class Records extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get owner => text().withDefault(const Constant(''))();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {id, kind};
}

@DriftDatabase(tables: [Records])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.open()
    : super(
        driftDatabase(
          name: 'nextbell',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX records_owner_kind ON records(owner, kind)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA busy_timeout=5000');
    },
  );

  Future<void> put(String kind, String id, Json json, {String owner = ''}) =>
      into(records).insertOnConflictUpdate(
        RecordsCompanion.insert(
          id: id,
          kind: kind,
          owner: Value(owner),
          payload: jsonEncode(json),
        ),
      );
  Future<void> remove(String kind, String id) => (delete(
    records,
  )..where((r) => r.kind.equals(kind) & r.id.equals(id))).go();
  Future<List<Json>> list(String kind, {String? owner}) async =>
      (await (select(records)..where(
                (r) =>
                    r.kind.equals(kind) &
                    (owner == null
                        ? const Constant(true)
                        : r.owner.equals(owner)),
              ))
              .get())
          .map((r) => jsonDecode(r.payload) as Json)
          .toList();
  Future<Json?> getOne(String kind, String id) async {
    final row = await (select(
      records,
    )..where((r) => r.kind.equals(kind) & r.id.equals(id))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.payload) as Json;
  }

  Future<void> deleteOwner(String owner, {String? kind}) =>
      (delete(records)..where(
            (r) =>
                r.owner.equals(owner) &
                (kind == null ? const Constant(true) : r.kind.equals(kind)),
          ))
          .go();
  Future<void> deleteKind(String kind) =>
      (delete(records)..where((r) => r.kind.equals(kind))).go();
  Future<void> replace(String kind, String owner, Iterable<Json> rows) =>
      transaction(() async {
        await deleteOwner(owner, kind: kind);
        for (final row in rows) {
          await put(kind, row['id'] as String, row, owner: owner);
        }
      });
  Stream<AppSnapshot> watchSnapshot() => select(records).watch().map(_snapshot);
  Future<AppSnapshot> snapshot() async =>
      _snapshot(await select(records).get());
  AppSnapshot _snapshot(List<Record> rows) {
    final byKind = <String, List<Json>>{};
    for (final row in rows) {
      (byKind[row.kind] ??= []).add(jsonDecode(row.payload) as Json);
    }
    final settings = byKind['settings']?.firstOrNull;
    final health = byKind['health']?.firstOrNull ?? <String, dynamic>{};
    return AppSnapshot(
      accounts: (byKind['account'] ?? [])
          .map(ConnectedAccount.fromJson)
          .toList(),
      sources: (byKind['source'] ?? []).map(CalendarSource.fromJson).toList(),
      entries: (byKind['entry'] ?? []).map(AgendaEntry.fromJson).toList(),
      taskLists: (byKind['taskList'] ?? [])
          .map(TaskListSource.fromJson)
          .toList(),
      tasks: (byKind['task'] ?? []).map(TaskItem.fromJson).toList(),
      overrides: (byKind['override'] ?? [])
          .map(ReminderOverride.fromJson)
          .toList(),
      settings: settings == null
          ? const AppSettings()
          : AppSettings.fromJson(settings),
      alarms: (byKind['alarm'] ?? []).map(AlarmSpec.fromJson).toList(),
      syncing: health['syncing'] ?? false,
      syncError: health['syncError'],
      alarmError: health['alarmError'],
      backgroundError: health['backgroundError'],
      lastSync: date(health['lastSync']),
      demo: health['demo'] ?? false,
    );
  }

  Future<void> health(Json patch) => transaction(() async {
    await put('health', 'main', {...?await getOne('health', 'main'), ...patch});
  });

  // A non-reversible identifier prevents an in-flight restore from undoing removal.
  Future<bool> accountRemoved(String id) async =>
      await getOne('removedAccount', stableId(['removed', id])) != null;
  Future<void> markAccountRemoved(String id) =>
      put('removedAccount', stableId(['removed', id]), {'removed': true});
  Future<void> allowAccount(String id) =>
      remove('removedAccount', stableId(['removed', id]));
}
