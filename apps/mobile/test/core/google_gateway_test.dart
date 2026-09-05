import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/features/sync/data/google_gateway.dart';

import 'sync_coordinator_test.dart' show FakeAuth, account, source, taskList;

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
void main() {
  test('calendar list includes hidden entries and follows every page with account provenance', () async {
    int pages = 0;
    final gateway = GoogleGateway(
      FakeAuth(),
      clientFactory: (_) => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.queryParameters['showHidden'], 'true');
        pages++;
        if (pages == 1) {
          return jsonResponse({
            'items': [
              {
                'id': 'shared',
                'summary': 'Shared',
                'accessRole': 'reader',
                'hidden': true,
              },
            ],
            'nextPageToken': 'page2',
          });
        }
        expect(request.url.queryParameters['pageToken'], 'page2');
        return jsonResponse({
          'items': [
            {'id': 'busy', 'summary': 'Busy', 'accessRole': 'freeBusyReader'},
          ],
        });
      }),
    );
    final sources = await gateway.discover(account);
    expect(sources.length, 2);
    expect(sources.first.hidden, true);
    expect(
      sources.every(
        (s) => s.accountId == account.id && s.mode == SourceMode.off,
      ),
      true,
    );
  });
  test('expanded event pages preserve private returned fields and watched invitations', () async {
    int pages = 0;
    final gateway = GoogleGateway(
      FakeAuth(),
      clientFactory: (_) => MockClient((request) async {
        expect(request.url.queryParameters['singleEvents'], 'true');
        expect(request.url.queryParameters['timeZone'], 'UTC');
        pages++;
        final fields = {
          'start': {'dateTime': '2026-09-06T15:00:00+05:30'},
          'end': {'dateTime': '2026-09-06T16:00:00+05:30'},
        };
        if (pages == 1) {
          return jsonResponse({
            'items': [
              {'id': 'private', ...fields},
            ],
            'nextPageToken': 'more',
          });
        }
        return jsonResponse({
          'items': [
            {
              'id': 'watched',
              'summary': 'Team call',
              ...fields,
              'attendees': [
                {
                  'email': 'owner@example.com',
                  'self': true,
                  'responseStatus': 'declined',
                },
              ],
            },
            {
              'id': 'declined',
              ...fields,
              'attendees': [
                {'email': account.email, 'responseStatus': 'declined'},
              ],
            },
            {'id': 'canceled', 'status': 'cancelled', ...fields},
            {
              'id': 'all-day',
              'start': {'date': '2026-09-06'},
              'end': {'date': '2026-09-07'},
            },
          ],
        });
      }),
    );
    final events = (await gateway.events(
      account,
      source('shared'),
      DateTime.utc(2026),
      DateTime.utc(2027),
    )).cast<CalendarEvent>();
    expect(events.length, 4);
    expect(events.first.title, 'Private event');
    expect(events.first.start, DateTime.utc(2026, 9, 6, 9, 30));
    expect(events[1].declined, false);
    expect(events[2].declined, true);
    expect(events.last.allDayDate, '2026-09-06');
  });
  test(
    'freebusy batches at 50 and reports per-calendar access loss separately',
    () async {
      final lengths = <int>[];
      final gateway = GoogleGateway(
        FakeAuth(),
        clientFactory: (_) => MockClient((request) async {
          final data = jsonDecode(request.body) as Map;
          final items = data['items'] as List;
          lengths.add(items.length);
          return jsonResponse({
            'calendars': {
              for (final item in items)
                item['id']: item['id'] == 's0@example.com'
                    ? {
                        'errors': [
                          {'domain': 'global', 'reason': 'notFound'},
                        ],
                      }
                    : {
                        'busy': [
                          {
                            'start': '2026-09-06T15:00:00Z',
                            'end': '2026-09-06T16:00:00Z',
                          },
                        ],
                      },
            },
          });
        }),
      );
      final result = await gateway.busy(
        account,
        List.generate(51, (i) => source('s$i', role: 'freeBusyReader')),
        DateTime.utc(2026, 9, 6),
        DateTime.utc(2026, 9, 7),
      );
      expect(lengths, [50, 1]);
      expect(result.blocks.length, 50);
      expect(result.failures['s0']!.accessLost, true);
    },
  );
  test(
    '97-day availability is contiguous and merges blocks across windows',
    () async {
      final from = DateTime.utc(2026, 9, 1);
      final to = from.add(const Duration(days: 97));
      final busyStart = from.add(const Duration(days: 29, hours: 23));
      final busyEnd = from.add(const Duration(days: 30, hours: 1));
      final windows = <(DateTime, DateTime)>[];
      final gateway = GoogleGateway(
        FakeAuth(),
        clientFactory: (_) => MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final start = DateTime.parse(body['timeMin'] as String);
          final end = DateTime.parse(body['timeMax'] as String);
          windows.add((start, end));
          expect(
            end.difference(start),
            lessThanOrEqualTo(const Duration(days: 30)),
          );
          return jsonResponse({
            'calendars': {
              'shared@example.com': {
                'busy': [
                  if (start.isBefore(busyEnd) && end.isAfter(busyStart))
                    {
                      'start': (start.isAfter(busyStart) ? start : busyStart)
                          .toIso8601String(),
                      'end': (end.isBefore(busyEnd) ? end : busyEnd)
                          .toIso8601String(),
                    },
                ],
              },
            },
          });
        }),
      );
      final result = await gateway.busy(
        account,
        [source('shared', role: 'freeBusyReader')],
        from,
        to,
      );
      expect(windows.length, 4);
      expect(windows.first.$1, from);
      expect(windows.last.$2, to);
      for (var i = 1; i < windows.length; i++) {
        expect(windows[i - 1].$2, windows[i].$1);
      }
      expect(result.failures, isEmpty);
      expect(result.blocks['shared'], hasLength(1));
      expect(result.blocks['shared']!.single.start, busyStart);
      expect(result.blocks['shared']!.single.end, busyEnd);
    },
  );
  test(
    'one failed availability window never commits a partial source',
    () async {
      var calls = 0;
      final gateway = GoogleGateway(
        FakeAuth(),
        clientFactory: (_) => MockClient((request) async {
          calls++;
          return jsonResponse({
            'calendars': {
              'good@example.com': {'busy': []},
              'partial@example.com': calls == 2
                  ? {
                      'errors': [
                        {'reason': 'internalError'},
                      ],
                    }
                  : {'busy': []},
            },
          });
        }),
      );
      final result = await gateway.busy(
        account,
        [
          source('good', role: 'freeBusyReader'),
          source('partial', role: 'freeBusyReader'),
        ],
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 12, 7),
      );
      expect(calls, 4);
      expect(result.blocks.containsKey('good'), true);
      expect(result.blocks.containsKey('partial'), false);
      expect(result.failures.containsKey('partial'), true);
    },
  );
  test('task completion sends only the permitted status patch', () async {
    final gateway = GoogleGateway(
      FakeAuth(),
      clientFactory: (_) => MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {'status': 'completed'});
        return jsonResponse({'id': 't', 'status': 'completed'});
      }),
    );
    await gateway.complete(
      account,
      taskList,
      const TaskItem(
        id: 'local',
        listId: 'list',
        providerId: 't',
        title: 'Keep title unchanged',
      ),
    );
  });
}
