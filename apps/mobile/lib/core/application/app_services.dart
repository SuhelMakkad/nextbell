import 'dart:async';

import 'package:drift/native.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

import '../models.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../../features/reminders/data/alarm_scheduler.dart';
import '../../features/reminders/domain/reminder_planner.dart';
import '../../features/sync/data/google_gateway.dart';
import '../../features/sync/application/sync_coordinator.dart';
import '../../features/sync/application/sync_engine.dart';
import '../../features/cloud/data/cloud_api.dart';
import '../../features/cloud/application/cloud_sync.dart';
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
    this.cloud,
  ) {
    ready = _initialize();
  }
  factory AppServices.create({bool demo = false}) {
    final db = demo ? AppDatabase(NativeDatabase.memory()) : AppDatabase.open();
    final host = NextbellHostApi();
    final cloudApi = !demo && CloudConfig.enabled ? CloudApi(db) : null;
    final AccountRepository auth = demo
        ? DemoAccountRepository()
        : cloudApi != null
        ? CloudAccountRepository(db, host, cloudApi)
        : NativeAccountRepository(db, host);
    final AlarmScheduler alarms = demo
        ? DemoAlarmScheduler(db)
        : NativeAlarmScheduler(db, host);
    final gateway = demo ? DemoGateway() : null;
    final google = GoogleGateway(auth);
    final cloud = cloudApi == null
        ? null
        : CloudSync(db, cloudApi, alarms, host);
    return AppServices._(
      db,
      auth,
      cloud ??
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
      cloud,
    );
  }
  final AppDatabase db;
  final AccountRepository auth;
  final SyncEngine sync;
  final CloudSync? cloud;
  final AlarmScheduler alarms;
  final ReminderRepository reminders;
  final NextbellHostApi host;
  final bool demo;
  late final Future<void> ready;
  StreamSubscription<RemoteMessage>? _messages;
  Future<void> _initialize() async {
    if (demo) {
      await seedDemo(db);
      return;
    }
    if (cloud != null) await db.health({'cloudRequired': true});
    try {
      await auth.restore();
    } catch (_) {
      await db.health({
        'syncError':
            'Account restoration needs attention. Reconnect from Settings.',
      });
    }
    await sync.recoverInterruptedSync();
    if (cloud != null && CloudConfig.configured) {
      _messages = FirebaseMessaging.onMessage.listen((message) {
        if (['sync', 'urgent_change'].contains(message.data['type'])) {
          unawaited(sync.run());
        }
      });
    }
  }

  Future<void> dispose() async {
    await ready;
    await _messages?.cancel();
    await sync.waitForIdle();
    if (cloud?.api case final CloudApi api) api.client.close();
    await db.close();
  }

  Future<void> connect({String? accountId}) async {
    await auth.connect(accountId: accountId);
    await sync.runAfterCurrent();
  }

  Future<void> enableTasks(String accountId) async {
    if (auth is CloudAccountRepository) {
      await (auth as CloudAccountRepository).connectGoogle(
        accountId: accountId,
        includeTasks: true,
      );
      await sync.runAfterCurrent();
    }
  }

  Future<void> resetForCloud() async {
    await db.transaction(() async {
      await db.remove('cloudSession', 'main');
      final device = await db.getOne('cloudDevice', 'main');
      if (device != null) {
        await db.put('cloudDevice', 'main', {
          ...device,
          'alarmsEnabled': false,
        });
      }
      await db.health({'cloudSignedIn': false});
    });
    await sync.waitForIdle();
    await host.cancelAlarms((await host.alarms()).map((a) => a.id).toList());
    await host.configureCloudDevice(false, false);
    for (final account in await host.accounts()) {
      await host.removeAccount(account.id);
    }
    await db.delete(db.records).go();
    await db.health({'cloudRequired': cloud != null, 'cloudSignedIn': false});
  }

  Future<void> finishOnboarding() async {
    final state = await db.snapshot();
    await saveSettings(state.settings.copyWith(onboarded: true));
  }

  Future<void> setSourceMode(CalendarSource source, SourceMode mode) async {
    if (cloud != null) {
      if (mode == SourceMode.alarm) {
        await db.deleteOwner(source.id, kind: 'entry');
      }
      await cloud!.edit('source', source.id, {'mode': mode.name});
      return;
    }
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
    if (cloud != null) {
      await cloud!.edit('source', source.id, {
        'reminderMinutes': minutes == null ? null : normalizeOffsets(minutes),
      });
      return;
    }
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
    if (cloud != null) {
      await cloud!.edit(
        'override',
        id,
        minutes == null
            ? null
            : {'sourceId': sourceId, 'minutes': normalizeOffsets(minutes)},
      );
      return;
    }
    if (minutes == null) {
      await reminders.resetOverride(id);
    } else {
      await reminders.setOverride(id, sourceId, minutes);
    }
    await alarms.reconcile();
  }

  Future<void> resetCalendar(CalendarSource source) async {
    if (cloud != null) {
      for (final rule in (await db.snapshot()).overrides.where(
        (r) => r.sourceId == source.id,
      )) {
        await cloud!.edit('override', rule.id, null);
      }
      await setCalendarOffsets(source, null);
      return;
    }
    await reminders.resetSource(source.id);
    await setCalendarOffsets(source, null);
  }

  Future<void> saveSettings(AppSettings settings) async {
    if (cloud != null) {
      final old = (await db.snapshot()).settings.toJson();
      final next = settings.toJson();
      final patch = <String, dynamic>{};
      for (final key in next.keys) {
        if (next[key].toString() != old[key].toString()) patch[key] = next[key];
      }
      if (patch.isNotEmpty) await cloud!.edit('settings', 'main', patch);
      return;
    }
    await reminders.saveSettings(settings);
    await alarms.reconcile();
  }

  Future<void> resetAllReminders() async {
    if (cloud != null) {
      final state = await db.snapshot();
      for (final source in state.sources) {
        await resetCalendar(source);
      }
      await saveSettings(
        state.settings.copyWith(minutes: [10, 5], snoozeMinutes: 5),
      );
      return;
    }
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
    if (cloud != null) {
      await cloud!.edit('taskList', list.id, {'selected': selected});
      return;
    }
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
    if (cloud != null) {
      await cloud!.edit('taskAlarm', item.id, {
        'alarmAt': at?.toUtc().toIso8601String(),
      });
      return;
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
    if (cloud != null) {
      await cloud!.queueCompletion(item);
      return;
    }
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
      if (cloud != null) {
        final taskIds = state.tasks
            .where((t) => ids.contains(t.listId))
            .map((t) => t.id)
            .toSet();
        for (final op in await db.list('cloudOutbox')) {
          final patch = (op['mutation'] as Json?)?['patch'] as Json?;
          final target = patch?['targetId'];
          final sourceId = (patch?['value'] as Json?)?['sourceId'];
          if (ids.contains(target) ||
              ids.contains(sourceId) ||
              taskIds.contains(target) ||
              taskIds.contains(op['taskId'])) {
            await db.remove('cloudOutbox', op['id']);
          }
        }
      }
      await db.remove('account', id);
      await db.deleteOwner(id);
      for (final source in ids) {
        await db.deleteOwner(source);
      }
    });
    await alarms.cancelSources(ids);
    await alarms.reconcile();
    if (cloud != null) unawaited(sync.runAfterCurrent());
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
