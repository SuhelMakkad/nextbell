import 'dart:io';

import 'package:nextbell_platform/nextbell_platform.dart';

import '../models.dart';
import 'app_database.dart';

abstract interface class AccountRepository {
  Future<void> restore();
  Future<ConnectedAccount> connect({String? accountId});
  Future<String> accessToken(String accountId);
  Future<void> remove(String accountId);
}

class NativeAccountRepository implements AccountRepository {
  NativeAccountRepository(this.db, this.host);
  final AppDatabase db;
  final NextbellHostApi host;
  @override
  Future<void> restore() async {
    for (final a in await host.accounts()) {
      await db.transaction(() async {
        if (await db.accountRemoved(a.id)) return;
        await db.put(
          'account',
          a.id,
          ConnectedAccount(id: a.id, email: a.email, name: a.name).toJson(),
        );
      });
    }
  }

  @override
  Future<ConnectedAccount> connect({String? accountId}) async {
    const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    if (Platform.isIOS && iosClientId.isEmpty) {
      throw StateError(
        'Google connection needs an iOS OAuth client ID. See docs/SETUP.md.',
      );
    }
    final a = await host.connect(Platform.isIOS ? iosClientId : '', accountId);
    if (accountId != null && a.id != accountId) {
      throw StateError('Choose the same Google account when reconnecting.');
    }
    final account = ConnectedAccount(id: a.id, email: a.email, name: a.name);
    await db.transaction(() async {
      await db.allowAccount(a.id);
      await db.put('account', a.id, account.toJson());
    });
    return account;
  }

  @override
  Future<String> accessToken(String accountId) => host.accessToken(accountId);
  @override
  Future<void> remove(String accountId) => host.removeAccount(accountId);
}

abstract interface class CalendarSourceRepository {
  Future<List<CalendarSource>> discover(ConnectedAccount account);
}

class AvailabilityResult {
  const AvailabilityResult(this.blocks, {this.failures = const {}});
  final Map<String, List<BusyBlock>> blocks;
  final Map<String, SyncFailure> failures;
}

abstract interface class CalendarRepository {
  Future<List<AgendaEntry>> events(
    ConnectedAccount account,
    CalendarSource source,
    DateTime from,
    DateTime to,
  );
  Future<AvailabilityResult> busy(
    ConnectedAccount account,
    List<CalendarSource> sources,
    DateTime from,
    DateTime to,
  );
}

abstract interface class TaskRepository {
  Future<List<TaskListSource>> lists(ConnectedAccount account);
  Future<List<TaskItem>> tasks(ConnectedAccount account, TaskListSource list);
  Future<void> complete(
    ConnectedAccount account,
    TaskListSource list,
    TaskItem task,
  );
}

class ReminderRepository {
  ReminderRepository(this.db);
  final AppDatabase db;
  Future<void> setOverride(String id, String sourceId, List<int> minutes) =>
      db.put(
        'override',
        id,
        ReminderOverride(
          id: id,
          sourceId: sourceId,
          minutes: normalizeOffsets(minutes),
        ).toJson(),
        owner: sourceId,
      );
  Future<void> resetOverride(String id) => db.remove('override', id);
  Future<void> resetSource(String sourceId) =>
      db.deleteOwner(sourceId, kind: 'override');
  Future<void> saveSettings(AppSettings settings) =>
      db.put('settings', 'main', settings.toJson());
}

/// Safe user-facing failures. Raw OAuth responses and event data are never logged.
class SyncFailure implements Exception {
  const SyncFailure(
    this.message, {
    this.accessLost = false,
    this.reauthorize = false,
    this.transient = false,
  });
  final String message;
  final bool accessLost, reauthorize, transient;
  @override
  String toString() => message;
}
