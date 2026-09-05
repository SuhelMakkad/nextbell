import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as gt;
import 'package:http/http.dart' as http;

import '../../../core/models.dart';
import '../../../core/data/repositories.dart';

class _AuthorizedClient extends http.BaseClient {
  _AuthorizedClient(this.token, [http.Client? inner])
    : _inner = inner ?? http.Client();
  final String token;
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request).timeout(const Duration(seconds: 30));
  }

  @override
  void close() => _inner.close();
}

class GoogleGateway
    implements CalendarSourceRepository, CalendarRepository, TaskRepository {
  GoogleGateway(this.auth, {http.Client Function(String)? clientFactory})
    : _clientFactory = clientFactory == null
          ? _AuthorizedClient.new
          : ((token) => _AuthorizedClient(token, clientFactory(token)));
  final AccountRepository auth;
  final http.Client Function(String) _clientFactory;
  Future<T> _call<T>(
    ConnectedAccount account,
    Future<T> Function(http.Client) action,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      http.Client? client;
      try {
        client = _clientFactory(await auth.accessToken(account.id));
        return await action(client).timeout(const Duration(minutes: 3));
      } catch (e) {
        final failure = _failure(e);
        if (!failure.transient || attempt == 2) throw failure;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      } finally {
        client?.close();
      }
    }
    throw const SyncFailure('Please try syncing again.');
  }

  SyncFailure _failure(Object e) {
    if (e is SyncFailure) return e;
    if (e is PlatformException) {
      return const SyncFailure(
        'Reconnect this Google account to continue syncing.',
        reauthorize: true,
      );
    }
    if (e is SocketException ||
        e is http.ClientException ||
        e is TimeoutException) {
      return const SyncFailure(
        'You’re offline. Your downloaded reminders are still available.',
        transient: true,
      );
    }
    // Google API exception types are shared by the generated API libraries.
    if (e is cal.DetailedApiRequestError) {
      final reasons = e.errors.map((v) => v.reason).toSet();
      if (e.status == 429 ||
          reasons.contains('rateLimitExceeded') ||
          reasons.contains('userRateLimitExceeded') ||
          (e.status != null && e.status! >= 500)) {
        return const SyncFailure(
          'Google is temporarily unavailable. We’ll try again.',
          transient: true,
        );
      }
      if (e.status == 401) {
        return const SyncFailure(
          'Reconnect this Google account.',
          reauthorize: true,
        );
      }
      if (e.status == 404 ||
          (e.status == 403 && reasons.contains('forbidden'))) {
        return const SyncFailure(
          'Access to this source is no longer available.',
          accessLost: true,
        );
      }
      return const SyncFailure(
        'Google could not read this source. Check access and try again.',
      );
    }
    return const SyncFailure('Sync could not finish. Please try again.');
  }

  @override
  Future<List<CalendarSource>> discover(ConnectedAccount account) =>
      _call(account, (client) async {
        final api = cal.CalendarApi(client);
        final result = <CalendarSource>[];
        String? page;
        do {
          final response = await api.calendarList.list(
            showHidden: true,
            maxResults: 250,
            pageToken: page,
          );
          for (final c in response.items ?? <cal.CalendarListEntry>[]) {
            if (c.id == null || c.deleted == true) continue;
            final color =
                int.tryParse(
                  (c.backgroundColor ?? '#6658d9').replaceFirst('#', 'ff'),
                  radix: 16,
                ) ??
                0xff6658d9;
            result.add(
              CalendarSource(
                id: stableId([account.id, c.id]),
                accountId: account.id,
                calendarId: c.id!,
                name: c.summaryOverride ?? c.summary ?? 'Calendar',
                accessRole: c.accessRole ?? 'none',
                color: color,
                primary: c.primary ?? false,
                hidden: c.hidden ?? false,
              ),
            );
          }
          page = response.nextPageToken;
        } while (page != null);
        return result;
      });

  @override
  Future<List<AgendaEntry>> events(
    ConnectedAccount account,
    CalendarSource source,
    DateTime from,
    DateTime to,
  ) => _call(account, (client) async {
    final api = cal.CalendarApi(client);
    final result = <AgendaEntry>[];
    String? page;
    do {
      final response = await api.events.list(
        source.calendarId,
        singleEvents: true,
        showDeleted: false,
        timeMin: from.toUtc(),
        timeMax: to.toUtc(),
        timeZone: 'UTC',
        maxResults: 2500,
        pageToken: page,
      );
      for (final e in response.items ?? <cal.Event>[]) {
        if (e.id == null ||
            e.status == 'cancelled' ||
            e.start == null ||
            e.end == null) {
          continue;
        }
        final start = e.start!.dateTime?.toUtc() ?? e.start!.date?.toUtc();
        final end = e.end!.dateTime?.toUtc() ?? e.end!.date?.toUtc();
        if (start == null || end == null) continue;
        // Shared calendar 'self' can refer to its owner, so compare the connected email.
        final declined =
            e.attendees?.any(
              (a) =>
                  a.email?.toLowerCase() == account.email.toLowerCase() &&
                  a.responseStatus == 'declined',
            ) ??
            false;
        final join =
            e.conferenceData?.entryPoints
                ?.where((p) => p.entryPointType == 'video')
                .firstOrNull
                ?.uri ??
            e.hangoutLink;
        result.add(
          CalendarEvent(
            id: stableId([source.id, e.id]),
            sourceId: source.id,
            start: start,
            end: end,
            title: e.summary ?? 'Private event',
            providerId: e.id!,
            calendarId: source.calendarId,
            iCalUid: e.iCalUID,
            seriesId: e.recurringEventId,
            originalStart:
                e.originalStartTime?.dateTime?.toUtc() ??
                e.originalStartTime?.date?.toUtc(),
            allDayDate: e.start!.date?.toIso8601String().substring(0, 10),
            endDate: e.end!.date?.toIso8601String().substring(0, 10),
            timeZone: e.start!.timeZone,
            description: e.description,
            location: e.location,
            joinUrl: join,
            webUrl: e.htmlLink,
            declined: declined,
          ),
        );
      }
      page = response.nextPageToken;
    } while (page != null);
    return result;
  });

  @override
  Future<AvailabilityResult> busy(
    ConnectedAccount account,
    List<CalendarSource> sources,
    DateTime from,
    DateTime to,
  ) async {
    final blocks = <String, List<BusyBlock>>{};
    final failures = <String, SyncFailure>{};
    for (var i = 0; i < sources.length; i += 50) {
      final batch = sources.skip(i).take(50).toList();
      try {
        final response = await _call(
          account,
          (client) => cal.CalendarApi(client).freebusy.query(
            cal.FreeBusyRequest(
              timeMin: from.toUtc(),
              timeMax: to.toUtc(),
              timeZone: 'UTC',
              calendarExpansionMax: 50,
              items: batch
                  .map((s) => cal.FreeBusyRequestItem(id: s.calendarId))
                  .toList(),
            ),
          ),
        );
        for (final source in batch) {
          final calendar = response.calendars?[source.calendarId];
          if (calendar == null || (calendar.errors?.isNotEmpty ?? false)) {
            final lost =
                calendar?.errors?.any(
                  (e) => e.reason == 'notFound' || e.reason == 'forbidden',
                ) ??
                false;
            failures[source.id] = SyncFailure(
              lost
                  ? 'Access to this availability calendar is no longer available.'
                  : 'Google could not refresh this availability calendar.',
              accessLost: lost,
            );
            continue;
          }
          blocks[source.id] = [
            for (final period in calendar.busy ?? <cal.TimePeriod>[])
              if (period.start != null && period.end != null)
                BusyBlock(
                  id: stableId([
                    source.id,
                    period.start!.toUtc().toIso8601String(),
                  ]),
                  sourceId: source.id,
                  start: period.start!.toUtc(),
                  end: period.end!.toUtc(),
                  calendarId: source.calendarId,
                  calendarName: source.name,
                ),
          ];
        }
      } on SyncFailure catch (failure) {
        for (final source in batch) {
          failures[source.id] = failure;
        }
      }
    }
    return AvailabilityResult(blocks, failures: failures);
  }

  @override
  Future<List<TaskListSource>> lists(ConnectedAccount account) =>
      _call(account, (client) async {
        final api = gt.TasksApi(client);
        final result = <TaskListSource>[];
        String? page;
        do {
          final response = await api.tasklists.list(
            maxResults: 100,
            pageToken: page,
          );
          for (final l in response.items ?? <gt.TaskList>[]) {
            if (l.id != null) {
              result.add(
                TaskListSource(
                  id: stableId([account.id, 'tasks', l.id]),
                  accountId: account.id,
                  providerId: l.id!,
                  title: l.title ?? 'Tasks',
                ),
              );
            }
          }
          page = response.nextPageToken;
        } while (page != null);
        return result;
      });

  @override
  Future<List<TaskItem>> tasks(ConnectedAccount account, TaskListSource list) =>
      _call(account, (client) async {
        final api = gt.TasksApi(client);
        final result = <TaskItem>[];
        String? page;
        do {
          final response = await api.tasks.list(
            list.providerId,
            maxResults: 100,
            pageToken: page,
            showCompleted: true,
            showHidden: true,
            showDeleted: false,
          );
          for (final t in response.items ?? <gt.Task>[]) {
            if (t.id == null || t.deleted == true) continue;
            result.add(
              TaskItem(
                id: stableId([list.id, t.id]),
                listId: list.id,
                providerId: t.id!,
                title: t.title ?? 'Untitled task',
                notes: t.notes,
                dueDate: t.due?.substring(0, 10),
                completed: t.status == 'completed',
              ),
            );
          }
          page = response.nextPageToken;
        } while (page != null);
        return result;
      });
  @override
  Future<void> complete(
    ConnectedAccount account,
    TaskListSource list,
    TaskItem task,
  ) => _call(account, (client) async {
    await gt.TasksApi(client).tasks
        .patch(gt.Task(status: 'completed'), list.providerId, task.providerId);
  });
}
