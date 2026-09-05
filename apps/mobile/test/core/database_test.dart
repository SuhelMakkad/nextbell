import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/data/app_database.dart';
import 'package:nextbell/core/models.dart';

void main() {
  test('schema v1 survives reopen with preferences and handled state; collection writes roll back atomically', () async {
    final dir = await Directory.systemTemp.createTemp('nextbell-db-test');
    final file = File('${dir.path}/database.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    try {
      await db.put(
        'settings',
        'main',
        const AppSettings(minutes: [30, 10]).toJson(),
      );
      await db.put('handled', 'dismissed', {
        'id': 'dismissed',
        'kind': 'dismiss',
      });
      await db.put('entry', 'one', {'id': 'one'}, owner: 'source');
      await expectLater(
        db.transaction(() async {
          await db.replace('entry', 'source', [
            {'id': 'two'},
          ]);
          throw StateError('Simulated failed commit');
        }),
        throwsStateError,
      );
      expect((await db.list('entry', owner: 'source')).single['id'], 'one');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect((await db.getOne('settings', 'main'))!['minutes'], [30, 10]);
      expect(await db.getOne('handled', 'dismissed'), isNotNull);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        1,
      );
      final indices = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .get();
      expect(
        indices.map((row) => row.read<String>('name')),
        contains('records_owner_kind'),
      );
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
