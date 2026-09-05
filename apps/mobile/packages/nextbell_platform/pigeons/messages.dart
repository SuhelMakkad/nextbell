import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'nextbell_platform',
    dartOut: 'packages/nextbell_platform/lib/src/messages.g.dart',
    kotlinOut: 'packages/nextbell_platform/android/src/main/kotlin/com/suhel/nextbell_platform/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.suhel.nextbell_platform'),
    swiftOut: 'packages/nextbell_platform/ios/nextbell_platform/Sources/nextbell_platform/Messages.g.swift',
  ),
)
class NativeAccount {
  NativeAccount({required this.id, required this.email, required this.name});
  String id;
  String email;
  String name;
}

class NativeAlarm {
  NativeAlarm({
    required this.id,
    required this.entryId,
    required this.title,
    required this.subtitle,
    required this.fireAtMillis,
    required this.snoozeMinutes,
    required this.sourceIds,
    this.parentId,
    this.ringing = false,
  });
  String id;
  String entryId;
  String title;
  String subtitle;
  int fireAtMillis;
  int snoozeMinutes;
  List<String> sourceIds;
  String? parentId;
  bool ringing;
}

class NativePermissions {
  NativePermissions({
    required this.alarms,
    required this.notifications,
    required this.fullScreen,
  });
  bool alarms;
  bool notifications;
  bool fullScreen;
}

class NativeAlarmAction {
  NativeAlarmAction({
    required this.id,
    required this.alarmId,
    required this.kind,
    required this.atMillis,
  });
  String id;
  String alarmId;
  String kind;
  int atMillis;
}

@HostApi()
abstract class NextbellHostApi {
  @async
  NativeAccount connect(String clientId, String? accountId);
  @async
  List<NativeAccount> accounts();
  @async
  String accessToken(String accountId);
  @async
  void removeAccount(String accountId);
  @async
  NativePermissions permissions();
  @async
  NativePermissions requestPermissions();
  @async
  void openSettings(String section);
  @async
  void scheduleAlarm(NativeAlarm alarm);
  @async
  void cancelAlarms(List<String> ids);
  @async
  List<NativeAlarm> alarms();
  @async
  List<NativeAlarmAction> pendingActions();
  @async
  void acknowledgeActions(List<String> ids);
}
