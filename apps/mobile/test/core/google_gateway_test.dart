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
        DateTime.utc(2026),
        DateTime.utc(2027),
      );
      expect(lengths, [50, 1]);
      expect(result.blocks.length, 50);
      expect(result.failures['s0']!.accessLost, true);
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
