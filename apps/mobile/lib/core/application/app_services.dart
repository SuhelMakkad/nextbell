import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

import '../models.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../../features/reminders/data/alarm_scheduler.dart';
import '../../features/reminders/domain/reminder_planner.dart';
import '../../features/sync/data/google_gateway.dart';
import '../../features/sync/application/sync_coordinator.dart';
import '../demo/demo_data.dart';

class DemoMode extends Notifier<bool> {
  @override
  bool build() => const bool.fromEnvironment('NEXTBELL_DEMO');
  void set(bool value) => state = value;
}

final demoModeProvider = NotifierProvider<DemoMode, bool>(DemoMode.new);
final servicesProvider = Provider<AppServices>((ref) {
  final service = AppServices.create(demo: ref.watch(demoModeProvider));
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final snapshotProvider = StreamProvider<AppSnapshot>((ref) async* {
  final service = ref.watch(servicesProvider);
  await service.ready;
  yield* service.db.watchSnapshot();
});

class AppServices {
  AppServices._(
    this.db,
    this.auth,
    this.sync,
    this.alarms,
    this.reminders,
    this.host,
    this.demo,
  ) {
    ready = _initialize();
  }
  factory AppServices.create({bool demo = false}) {
    final db = demo ? AppDatabase(NativeDatabase.memory()) : AppDatabase.open();
    final host = NextbellHostApi();
    final AccountRepository auth = demo
        ? DemoAccountRepository()
        : NativeAccountRepository(db, host);
    final AlarmScheduler alarms = demo
        ? DemoAlarmScheduler(db)
        : NativeAlarmScheduler(db, host);
    final gateway = demo ? DemoGateway() : null;
    final google = GoogleGateway(auth);
    return AppServices._(
      db,
      auth,
      SyncCoordinator(
        db,
        auth,
        gateway ?? google,
        gateway ?? google,
        gateway ?? google,
        alarms,
      ),
      alarms,
      ReminderRepository(db),
      host,
      demo,
    );
  }
  final AppDatabase db;
  final AccountRepository auth;
  final SyncCoordinator sync;
  final AlarmScheduler alarms;
  final ReminderRepository reminders;
  final NextbellHostApi host;
  final bool demo;
  late final Future<void> ready;
  Future<void> _initialize() async {
    if (demo) {
      await seedDemo(db);
      return;
    }
    try {
      await auth.restore();
    } catch (_) {
      await db.health({
        'syncError':
            'Account restoration needs attention. Reconnect from Settings.',
      });
    }
    await sync.recoverInterruptedSync();
  }

  Future<void> dispose() async {
    await ready;
    await sync.waitForIdle();
    await db.close();
  }

  Future<void> connect({String? accountId}) async {
    await auth.connect(accountId: accountId);
    await sync.runAfterCurrent();
  }

  Future<void> finishOnboarding() async {
    final state = await db.snapshot();
    await reminders.saveSettings(state.settings.copyWith(onboarded: true));
  }

  Future<void> setSourceMode(CalendarSource source, SourceMode mode) async {
    final fresh = await db.getOne('source', source.id);
    if (fresh == null) return;
    final current = CalendarSource.fromJson(fresh);
    if (!current.available) {
      throw StateError('Restore access to this calendar in Google first.');
    }
    // Enable with no stale entries; synchronization must succeed before alarms are rebuilt.
    await db.transaction(() async {
      await db.put(
        'source',
        source.id,
        current.copyWith(mode: mode, clearError: true).toJson(),
        owner: source.accountId,
      );
      if (mode == SourceMode.alarm || mode == SourceMode.off) {
        await db.deleteOwner(source.id, kind: 'entry');
      }
    });
    await alarms.cancelSources({source.id});
    await alarms.reconcile();
    if (mode != SourceMode.off) await sync.runAfterCurrent();
  }

  Future<void> setCalendarOffsets(
    CalendarSource source,
    List<int>? minutes,
  ) async {
    final current = CalendarSource.fromJson(
      (await db.getOne('source', source.id))!,
    );
    await db.put(
      'source',
      source.id,
      current
          .copyWith(
            reminderMinutes: minutes == null ? null : normalizeOffsets(minutes),
            inherit: minutes == null,
          )
          .toJson(),
      owner: source.accountId,
    );
    await alarms.reconcile();
  }

  Future<void> setOverride(
    String id,
    String sourceId,
    List<int>? minutes,
  ) async {
    if (minutes == null) {
      await reminders.resetOverride(id);
    } else {
      await reminders.setOverride(id, sourceId, minutes);
    }
    await alarms.reconcile();
  }

  Future<void> resetCalendar(CalendarSource source) async {
    await reminders.resetSource(source.id);
    await setCalendarOffsets(source, null);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await reminders.saveSettings(settings);
    await alarms.reconcile();
  }

  Future<void> resetAllReminders() async {
    await db.transaction(() async {
      await db.deleteKind('override');
      final state = await db.snapshot();
      for (final source in state.sources) {
        await db.put(
          'source',
          source.id,
          source.copyWith(inherit: true).toJson(),
          owner: source.accountId,
        );
      }
      await reminders.saveSettings(
        state.settings.copyWith(minutes: [10, 5], snoozeMinutes: 5),
      );
    });
    await alarms.reconcile();
  }

  Future<void> selectTaskList(TaskListSource list, bool selected) async {
    await db.put(
      'taskList',
      list.id,
      TaskListSource(
        id: list.id,
        accountId: list.accountId,
        providerId: list.providerId,
        title: list.title,
        selected: selected,
        lastSync: list.lastSync,
      ).toJson(),
      owner: list.accountId,
    );
    await alarms.cancelSources({list.id});
    await alarms.reconcile();
    if (selected) await sync.runAfterCurrent();
  }

  Future<void> setTaskAlarm(TaskItem item, DateTime? at) async {
    if (at != null && !at.isAfter(DateTime.now())) {
      throw ArgumentError('Choose a future time.');
    }
    final current = TaskItem.fromJson((await db.getOne('task', item.id))!);
    await db.put(
      'task',
      item.id,
      current.copyWith(alarmAt: at?.toUtc(), clearAlarm: at == null).toJson(),
      owner: item.listId,
    );
    await alarms.reconcile();
  }

  Future<void> completeTask(TaskItem item) async {
    final stored = await db.getOne('task', item.id);
    if (stored == null) return;
    final current = TaskItem.fromJson(stored);
    await db.put(
      'task',
      item.id,
      current.copyWith(completed: true, pendingCompletion: true).toJson(),
      owner: item.listId,
    );
    await alarms.reconcile();
    await sync.runAfterCurrent();
  }

  Future<void> removeAccount(String id) async {
    await db.markAccountRemoved(id);
    await auth.remove(id);
    final state = await db.snapshot();
    final ids = {
      ...state.sources.where((s) => s.accountId == id).map((s) => s.id),
      ...state.taskLists.where((s) => s.accountId == id).map((s) => s.id),
    };
    await db.transaction(() async {
      await db.remove('account', id);
      await db.deleteOwner(id);
      for (final source in ids) {
        await db.deleteOwner(source);
      }
    });
    await alarms.cancelSources(ids);
    await alarms.reconcile();
  }

  List<int> offsetsFor(AgendaEntry entry, AppSnapshot state) {
    final source = state.source(entry.sourceId);
    if (source == null || source.mode != SourceMode.alarm) return [];
    return const ReminderPlanner().effectiveOffsets(
      entry,
      source,
      state.overrides,
      state.settings,
    );
  }
}
