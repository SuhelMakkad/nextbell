import 'dart:convert';
import 'dart:io';

/// Generate native Firebase resources for FCM before a Dart isolate starts.
/// Inputs are client identifiers, never OAuth client secrets or refresh tokens.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/configure_cloud.dart cloud.local.json',
    );
    exitCode = 64;
    return;
  }
  final config =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  const resources = {
    'FIREBASE_APP_ID': 'google_app_id',
    'FIREBASE_API_KEY': 'google_api_key',
    'FIREBASE_MESSAGING_SENDER_ID': 'gcm_defaultSenderId',
    'FIREBASE_PROJECT_ID': 'project_id',
    'GOOGLE_SERVER_CLIENT_ID': 'default_web_client_id',
  };
  if (config.keys.any(
    (key) =>
        key.toLowerCase().contains('secret') ||
        key.toLowerCase().contains('token'),
  )) {
    throw StateError('Do not include server credentials in a mobile build.');
  }
  final origin = Uri.tryParse(config['NEXTBELL_API_ORIGIN'] as String? ?? '');
  if (origin == null ||
      origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.path.isNotEmpty && origin.path != '/') {
    throw StateError('Set NEXTBELL_API_ORIGIN to the HTTPS beta origin.');
  }
  String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  final xml = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n',
  );
  for (final entry in resources.entries) {
    final value = config[entry.key] as String?;
    if (value == null || value.trim().isEmpty || value.contains('YOUR_')) {
      throw StateError('Configure ${entry.key}.');
    }
    xml.writeln(
      '  <string name="${entry.value}" translatable="false">${escape(value)}</string>',
    );
  }
  xml.writeln('</resources>');
  final file = File('android/app/src/main/res/values/nextbell_firebase.xml');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(xml.toString());
  stdout.writeln(
    'Native Firebase resources generated. Build with --dart-define-from-file=${args.single}.',
  );
}
