// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Nextbell';

  @override
  String get today => 'Today';

  @override
  String get tasks => 'Tasks';

  @override
  String get settings => 'Settings';

  @override
  String get agendaHeadline => 'A little ahead.';

  @override
  String get agendaSubtitle => 'Your day, on your terms.';

  @override
  String get tasksHeadline => 'Small things.\nMore headspace.';

  @override
  String get settingsHeadline => 'Make it yours.';

  @override
  String get accountsAndCalendars => 'Accounts & Calendars';

  @override
  String get alarmsAndReminders => 'Alarms & reminders';

  @override
  String get snooze => 'Snooze';

  @override
  String get dismiss => 'Dismiss';
}
