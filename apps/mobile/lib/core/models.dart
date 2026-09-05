import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

String stableId(Iterable<Object?> parts) {
  final h = sha256.convert(utf8.encode(jsonEncode(parts.toList()))).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

DateTime? date(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toUtc();
List<int>? offsets(dynamic v) =>
    v == null ? null : (v as List).cast<num>().map((n) => n.toInt()).toList();
List<int> normalizeOffsets(Iterable<int> values) {
  final result = values.toSet().toList()..sort((a, b) => b.compareTo(a));
  if (result.any((v) => v < 0 || v > 40320)) {
    throw ArgumentError('Choose offsets between now and four weeks before.');
  }
  return result;
}

enum SourceMode { off, showOnly, alarm }

class ConnectedAccount {
  const ConnectedAccount({
    required this.id,
    required this.email,
    required this.name,
    this.error,
  });
  final String id, email, name;
  final String? error;
  Json toJson() => {'id': id, 'email': email, 'name': name, 'error': error};
  factory ConnectedAccount.fromJson(Json j) => ConnectedAccount(
    id: j['id'],
    email: j['email'],
    name: j['name'],
    error: j['error'],
  );
}

class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.accountId,
    required this.calendarId,
    required this.name,
    required this.accessRole,
    this.color = 0xff6658d9,
    this.primary = false,
    this.hidden = false,
    this.mode = SourceMode.off,
    this.reminderMinutes,
    this.available = true,
    this.lastSync,
    this.error,
  });
  final String id, accountId, calendarId, name, accessRole;
  final int color;
  final bool primary, hidden, available;
  final SourceMode mode;
  final List<int>? reminderMinutes;
  final DateTime? lastSync;
  final String? error;
  bool get availabilityOnly => accessRole == 'freeBusyReader';
  bool get canReadEvents => const [
    'reader',
    'writer',
    'writerWithoutPrivateAccess',
    'owner',
  ].contains(accessRole);
  String get accessLabel => availabilityOnly
      ? 'Availability only'
      : switch (accessRole) {
          'owner' => 'Manage access',
          'writer' || 'writerWithoutPrivateAccess' => 'Can edit in Google',
          'reader' => 'View only',
          _ => 'Access unavailable',
        };
  CalendarSource copyWith({
    SourceMode? mode,
    List<int>? reminderMinutes,
    bool inherit = false,
    bool? available,
    DateTime? lastSync,
    String? error,
    bool clearError = false,
  }) => CalendarSource(
    id: id,
    accountId: accountId,
    calendarId: calendarId,
    name: name,
    accessRole: accessRole,
    color: color,
    primary: primary,
    hidden: hidden,
    mode: mode ?? this.mode,
    reminderMinutes: inherit ? null : reminderMinutes ?? this.reminderMinutes,
    available: available ?? this.available,
    lastSync: lastSync ?? this.lastSync,
    error: clearError ? null : error ?? this.error,
  );
  Json toJson() => {
    'id': id,
    'accountId': accountId,
    'calendarId': calendarId,
    'name': name,
    'accessRole': accessRole,
    'color': color,
    'primary': primary,
    'hidden': hidden,
    'mode': mode.name,
    'reminderMinutes': reminderMinutes,
    'available': available,
    'lastSync': lastSync?.toIso8601String(),
    'error': error,
  };
  factory CalendarSource.fromJson(Json j) => CalendarSource(
    id: j['id'],
    accountId: j['accountId'],
    calendarId: j['calendarId'],
    name: j['name'],
    accessRole: j['accessRole'],
    color: j['color'],
    primary: j['primary'] ?? false,
    hidden: j['hidden'] ?? false,
    mode: SourceMode.values.byName(j['mode'] ?? 'off'),
    reminderMinutes: offsets(j['reminderMinutes']),
    available: j['available'] ?? true,
    lastSync: date(j['lastSync']),
    error: j['error'],
  );
}

sealed class AgendaEntry {
  const AgendaEntry({
    required this.id,
    required this.sourceId,
    required this.start,
    required this.end,
  });
  final String id, sourceId;
  final DateTime start, end;
  String get title;
  String get canonicalId;
  Json toJson();
  static AgendaEntry fromJson(Json j) =>
      j['kind'] == 'busy' ? BusyBlock.fromJson(j) : CalendarEvent.fromJson(j);
}

class CalendarEvent extends AgendaEntry {
  const CalendarEvent({
    required super.id,
    required super.sourceId,
    required super.start,
    required super.end,
    required this.title,
    required this.providerId,
    required this.calendarId,
    this.iCalUid,
    this.seriesId,
    this.originalStart,
    this.allDayDate,
    this.endDate,
    this.timeZone,
    this.description,
    this.location,
    this.joinUrl,
    this.webUrl,
    this.declined = false,
  });
  @override
  final String title;
  final String providerId, calendarId;
  final String? iCalUid,
      seriesId,
      allDayDate,
      endDate,
      timeZone,
      description,
      location,
      joinUrl,
      webUrl;
  final DateTime? originalStart;
  final bool declined;
  bool get allDay => allDayDate != null;
  String? get seriesKey =>
      seriesId == null ? null : stableId([sourceId, seriesId]);
  @override
  String get canonicalId => stableId([
    'event',
    iCalUid ?? '$calendarId/$providerId',
    (originalStart ?? start).toUtc().toIso8601String(),
  ]);
  @override
  Json toJson() => {
    'kind': 'event',
    'id': id,
    'sourceId': sourceId,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'title': title,
    'providerId': providerId,
    'calendarId': calendarId,
    'iCalUid': iCalUid,
    'seriesId': seriesId,
    'originalStart': originalStart?.toIso8601String(),
    'allDayDate': allDayDate,
    'endDate': endDate,
    'timeZone': timeZone,
    'description': description,
    'location': location,
    'joinUrl': joinUrl,
    'webUrl': webUrl,
    'declined': declined,
  };
  factory CalendarEvent.fromJson(Json j) => CalendarEvent(
    id: j['id'],
    sourceId: j['sourceId'],
    start: date(j['start'])!,
    end: date(j['end'])!,
    title: j['title'],
    providerId: j['providerId'],
    calendarId: j['calendarId'],
    iCalUid: j['iCalUid'],
    seriesId: j['seriesId'],
    originalStart: date(j['originalStart']),
    allDayDate: j['allDayDate'],
    endDate: j['endDate'],
    timeZone: j['timeZone'],
    description: j['description'],
    location: j['location'],
    joinUrl: j['joinUrl'],
    webUrl: j['webUrl'],
    declined: j['declined'] ?? false,
  );
}

class BusyBlock extends AgendaEntry {
  const BusyBlock({
    required super.id,
    required super.sourceId,
    required super.start,
    required super.end,
    required this.calendarId,
    required this.calendarName,
  });
  final String calendarId, calendarName;
  @override
  String get title => 'Busy — $calendarName';
  @override
  String get canonicalId =>
      stableId(['busy', calendarId, start.toUtc().toIso8601String()]);
  @override
  Json toJson() => {
    'kind': 'busy',
    'id': id,
    'sourceId': sourceId,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'calendarId': calendarId,
    'calendarName': calendarName,
  };
  factory BusyBlock.fromJson(Json j) => BusyBlock(
    id: j['id'],
    sourceId: j['sourceId'],
    start: date(j['start'])!,
    end: date(j['end'])!,
    calendarId: j['calendarId'],
    calendarName: j['calendarName'],
  );
}

class TaskListSource {
  const TaskListSource({
    required this.id,
    required this.accountId,
    required this.providerId,
    required this.title,
    this.selected = false,
    this.lastSync,
    this.error,
  });
  final String id, accountId, providerId, title;
  final bool selected;
  final DateTime? lastSync;
  final String? error;
  Json toJson() => {
    'id': id,
    'accountId': accountId,
    'providerId': providerId,
    'title': title,
    'selected': selected,
    'lastSync': lastSync?.toIso8601String(),
    'error': error,
  };
  factory TaskListSource.fromJson(Json j) => TaskListSource(
    id: j['id'],
    accountId: j['accountId'],
    providerId: j['providerId'],
    title: j['title'],
    selected: j['selected'] ?? false,
    lastSync: date(j['lastSync']),
    error: j['error'],
  );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.listId,
    required this.providerId,
    required this.title,
    this.notes,
    this.dueDate,
    this.completed = false,
    this.pendingCompletion = false,
    this.alarmAt,
  });
  final String id, listId, providerId, title;
  final String? notes, dueDate;
  final bool completed, pendingCompletion;
  final DateTime? alarmAt;
  TaskItem copyWith({
    bool? completed,
    bool? pendingCompletion,
    DateTime? alarmAt,
    bool clearAlarm = false,
  }) => TaskItem(
    id: id,
    listId: listId,
    providerId: providerId,
    title: title,
    notes: notes,
    dueDate: dueDate,
    completed: completed ?? this.completed,
    pendingCompletion: pendingCompletion ?? this.pendingCompletion,
    alarmAt: clearAlarm ? null : alarmAt ?? this.alarmAt,
  );
  Json toJson() => {
    'id': id,
    'listId': listId,
    'providerId': providerId,
    'title': title,
    'notes': notes,
    'dueDate': dueDate,
    'completed': completed,
    'pendingCompletion': pendingCompletion,
    'alarmAt': alarmAt?.toIso8601String(),
  };
  factory TaskItem.fromJson(Json j) => TaskItem(
    id: j['id'],
    listId: j['listId'],
    providerId: j['providerId'],
    title: j['title'],
    notes: j['notes'],
    dueDate: j['dueDate'],
    completed: j['completed'] ?? false,
    pendingCompletion: j['pendingCompletion'] ?? false,
    alarmAt: date(j['alarmAt']),
  );
}

class ReminderOverride {
  const ReminderOverride({
    required this.id,
    required this.sourceId,
    required this.minutes,
  });
  final String id, sourceId;
  final List<int> minutes;
  Json toJson() => {'id': id, 'sourceId': sourceId, 'minutes': minutes};
  factory ReminderOverride.fromJson(Json j) => ReminderOverride(
    id: j['id'],
    sourceId: j['sourceId'],
    minutes: offsets(j['minutes'])!,
  );
}

class AppSettings {
  const AppSettings({
    this.minutes = const [10, 5],
    this.snoozeMinutes = 5,
    this.theme = 'system',
    this.onboarded = false,
  });
  final List<int> minutes;
  final int snoozeMinutes;
  final String theme;
  final bool onboarded;
  AppSettings copyWith({
    List<int>? minutes,
    int? snoozeMinutes,
    String? theme,
    bool? onboarded,
  }) => AppSettings(
    minutes: minutes ?? this.minutes,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    theme: theme ?? this.theme,
    onboarded: onboarded ?? this.onboarded,
  );
  Json toJson() => {
    'minutes': minutes,
    'snoozeMinutes': snoozeMinutes,
    'theme': theme,
    'onboarded': onboarded,
  };
  factory AppSettings.fromJson(Json j) => AppSettings(
    minutes: offsets(j['minutes']) ?? const [10, 5],
    snoozeMinutes: j['snoozeMinutes'] ?? 5,
    theme: j['theme'] ?? 'system',
    onboarded: j['onboarded'] ?? false,
  );
}

class AlarmSpec {
  const AlarmSpec({
    required this.id,
    required this.entryId,
    required this.title,
    required this.subtitle,
    required this.fireAt,
    required this.sourceIds,
    required this.snoozeMinutes,
  });
  final String id, entryId, title, subtitle;
  final DateTime fireAt;
  final List<String> sourceIds;
  final int snoozeMinutes;
  Json toJson() => {
    'id': id,
    'entryId': entryId,
    'title': title,
    'subtitle': subtitle,
    'fireAt': fireAt.toIso8601String(),
    'sourceIds': sourceIds,
    'snoozeMinutes': snoozeMinutes,
  };
  factory AlarmSpec.fromJson(Json j) => AlarmSpec(
    id: j['id'],
    entryId: j['entryId'],
    title: j['title'],
    subtitle: j['subtitle'],
    fireAt: date(j['fireAt'])!,
    sourceIds: (j['sourceIds'] as List).cast<String>(),
    snoozeMinutes: j['snoozeMinutes'],
  );
}

class AppSnapshot {
  const AppSnapshot({
    this.accounts = const [],
    this.sources = const [],
    this.entries = const [],
    this.taskLists = const [],
    this.tasks = const [],
    this.overrides = const [],
    this.settings = const AppSettings(),
    this.alarms = const [],
    this.syncing = false,
    this.syncError,
    this.alarmError,
    this.backgroundError,
    this.lastSync,
    this.demo = false,
  });
  final List<ConnectedAccount> accounts;
  final List<CalendarSource> sources;
  final List<AgendaEntry> entries;
  final List<TaskListSource> taskLists;
  final List<TaskItem> tasks;
  final List<ReminderOverride> overrides;
  final AppSettings settings;
  final List<AlarmSpec> alarms;
  final bool syncing, demo;
  final String? syncError, alarmError, backgroundError;
  final DateTime? lastSync;
  CalendarSource? source(String id) =>
      sources.where((s) => s.id == id).firstOrNull;
}
