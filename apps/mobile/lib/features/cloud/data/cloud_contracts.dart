import '../../../core/models.dart';

/// The mobile projection of packages/cloud/openapi.json. Provider rows are
/// validated by the existing domain models before a snapshot can be committed.
enum CloudRecordKind { account, source, entry, taskList, task }

class CloudCollection {
  CloudCollection.fromJson(this.metadata)
    : kind = CloudRecordKind.values.byName(metadata['kind'] as String),
      key = metadata['key'] as String,
      owner = metadata['owner'] as String,
      generation = metadata['generation'] as String,
      deleted = metadata['deleted'] == true;
  final CloudRecordKind kind;
  final String key, owner, generation;
  final bool deleted;
  final Json metadata;

  void validateRow(Json row) {
    switch (kind) {
      case CloudRecordKind.account:
        ConnectedAccount.fromJson(row);
      case CloudRecordKind.source:
        CalendarSource.fromJson(row);
      case CloudRecordKind.entry:
        AgendaEntry.fromJson(row);
      case CloudRecordKind.taskList:
        TaskListSource.fromJson(row);
      case CloudRecordKind.task:
        TaskItem.fromJson(row);
    }
  }
}

class CloudManifest {
  CloudManifest.fromJson(Json value)
    : revision = value['revision'] as int,
      serverTime = DateTime.parse(value['serverTime'] as String),
      collections = (value['collections'] as List)
          .map((row) => CloudCollection.fromJson(row as Json))
          .toList(),
      preferences = (value['preferences'] as List).cast<Json>(),
      devices = (value['devices'] as List).cast<Json>() {
    if (revision < 0) throw const FormatException('Invalid sync revision.');
  }
  final int revision;
  final DateTime serverTime;
  final List<CloudCollection> collections;
  final List<Json> preferences, devices;
}

class CloudPage {
  CloudPage.fromJson(Json value)
    : rows = (value['rows'] as List)
          .map((row) => (row as Json)['data'] as Json)
          .toList(),
      next = value['next'] as String?;
  final List<Json> rows;
  final String? next;
}
