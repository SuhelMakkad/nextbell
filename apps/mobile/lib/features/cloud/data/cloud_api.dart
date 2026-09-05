import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:nextbell_platform/nextbell_platform.dart';

import '../../../core/data/app_database.dart';
import '../../../core/data/repositories.dart';
import '../../../core/models.dart';

String newMutationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class CloudConfig {
  static bool get enabled =>
      Platform.isAndroid &&
      const bool.fromEnvironment('NEXTBELL_CLOUD', defaultValue: true);
  static const origin = String.fromEnvironment(
    'NEXTBELL_API_ORIGIN',
    defaultValue: 'https://www.nextbell.org',
  );
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'nextbell-507711',
  );
  static bool get configured =>
      [serverClientId, apiKey, appId, senderId].every((v) => v.isNotEmpty);
  static Future<void> initialize() async {
    if (!configured) {
      throw StateError(
        'This beta build needs its Nextbell cloud configuration.',
      );
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
        ),
      );
    }
  }
}

class CloudFailure implements Exception {
  const CloudFailure(this.code, this.message, {this.current});
  final String code, message;
  final Json? current;
  @override
  String toString() => message;
}

abstract interface class CloudTransport {
  Future<Json> send(String method, String path, [Json? body]);
}

class CloudApi implements CloudTransport {
  CloudApi(this.db, {http.Client? client}) : client = client ?? http.Client();
  final AppDatabase db;
  final http.Client client;
  Future<String> deviceId() => db.transaction(() async {
    final record = await db.getOne('cloudDevice', 'main');
    if (record != null) return record['id'] as String;
    final id = newMutationId();
    await db.put('cloudDevice', 'main', {'id': id, 'alarmsEnabled': true});
    return id;
  });
  @override
  Future<Json> send(String method, String path, [Json? body]) async {
    await CloudConfig.initialize();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CloudFailure('sign_in', 'Sign in to Nextbell.');
    }
    final uri = Uri.parse('${CloudConfig.origin}/api/v1/$path');
    if (uri.scheme != 'https') {
      throw StateError('Nextbell requires a secure backend address.');
    }
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final request = http.Request(method, uri)
          ..headers.addAll({
            'Authorization': 'Bearer ${await user.getIdToken(attempt == 1)}',
            'X-Nextbell-Device': await deviceId(),
            'Content-Type': 'application/json',
          });
        if (body != null) request.body = jsonEncode(body);
        final response = await http.Response.fromStream(
          await client.send(request).timeout(const Duration(seconds: 30)),
        ).timeout(const Duration(seconds: 30));
        Json result;
        try {
          result = jsonDecode(response.body) as Json;
        } catch (_) {
          throw const CloudFailure(
            'unavailable',
            'Nextbell cloud is temporarily unavailable.',
          );
        }
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode >= 400) {
          final error = result['error'] as Json? ?? {};
          throw CloudFailure(
            error['code'] as String? ?? 'unavailable',
            error['message'] as String? ?? 'Please try syncing again.',
            current: error['current'] as Json?,
          );
        }
        return result;
      }
    } on FirebaseAuthException catch (error) {
      if ([
        'user-disabled',
        'user-not-found',
        'invalid-user-token',
        'user-token-expired',
      ].contains(error.code)) {
        throw const CloudFailure(
          'session_revoked',
          'This phone’s sign-in is no longer valid. Sign in again.',
        );
      }
      throw const CloudFailure(
        'offline',
        'Sign-in could not refresh. Downloaded alarms still work.',
      );
    } on SocketException catch (_) {
      throw const CloudFailure(
        'offline',
        'You’re offline. Downloaded alarms still work.',
      );
    } on http.ClientException catch (_) {
      throw const CloudFailure(
        'offline',
        'You’re offline. Downloaded alarms still work.',
      );
    }
    throw const CloudFailure('sign_in', 'Sign in to Nextbell again.');
  }

  Future<void> register() async {
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      /* Scheduling works without push. */
    }
    final device = await send('POST', 'devices', {
      'id': await deviceId(),
      'name': Platform.localHostname.isEmpty
          ? 'Android phone'
          : Platform.localHostname.substring(
              0,
              min(80, Platform.localHostname.length),
            ),
      'platform': 'android',
      'pushToken': token,
      'appVersion': '1.0.0+2',
    });
    await db.put('cloudDevice', 'main', device);
  }
}

class CloudAccountRepository implements AccountRepository {
  CloudAccountRepository(this.db, this.host, this.api);
  final AppDatabase db;
  final NextbellHostApi host;
  final CloudApi api;
  @override
  Future<void> restore() async {
    if (!CloudConfig.configured) return;
    await CloudConfig.initialize();
    final user = FirebaseAuth.instance.currentUser;
    final session = await db.getOne('cloudSession', 'main');
    if (user == null || session?['uid'] != user.uid) {
      await db.health({'cloudSignedIn': false});
      return;
    }
    await db.health({'cloudSignedIn': true});
    try {
      await api.register();
    } catch (_) {
      /* Preserve offline access to downloaded alarms. */
    }
  }

  Future<void> signIn({bool reauthenticate = false}) async {
    await CloudConfig.initialize();
    if (!reauthenticate &&
        await db.getOne('cloudSession', 'main') == null &&
        (await db.snapshot()).accounts.isNotEmpty) {
      throw StateError(
        'Reset this phone’s development data before joining the cloud beta.',
      );
    }
    final token = await host.identityToken(CloudConfig.serverClientId);
    final credential = GoogleAuthProvider.credential(idToken: token);
    if (reauthenticate) {
      await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(
        credential,
      );
      return;
    }
    final old = await db.getOne('cloudSession', 'main');
    final user = (await FirebaseAuth.instance.signInWithCredential(credential))
        .user!;
    if (old != null && old['uid'] != user.uid) {
      await FirebaseAuth.instance.signOut();
      throw StateError(
        'Sign out and clear this phone before choosing another Nextbell account.',
      );
    }
    await api.register();
    await db.put('cloudSession', 'main', {
      'id': old?['id'] ?? newMutationId(),
      'uid': user.uid,
      'email': user.email,
    });
    await db.health({'cloudSignedIn': true});
  }

  @override
  Future<ConnectedAccount> connect({String? accountId}) =>
      connectGoogle(accountId: accountId);
  Future<ConnectedAccount> connectGoogle({
    String? accountId,
    bool includeTasks = false,
  }) async {
    await CloudConfig.initialize();
    final first = FirebaseAuth.instance.currentUser == null;
    if (first || await db.getOne('cloudSession', 'main') == null) {
      await signIn();
    }
    String id, email, name;
    final existing = accountId == null
        ? null
        : await db.getOne('account', accountId);
    if (existing != null) {
      id = existing['id'] as String;
      email = existing['email'] as String;
      name = existing['name'] as String;
    } else if (first) {
      final user = FirebaseAuth.instance.currentUser!;
      id = user.providerData
          .firstWhere((p) => p.providerId == 'google.com')
          .uid!;
      email = user.email!;
      name = user.displayName ?? email;
    } else {
      final token = await host.identityToken(CloudConfig.serverClientId);
      // Used only to route the consent request. The backend independently verifies
      // Google's authorization response and never trusts these decoded claims.
      final identity = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      ) as Json;
      id = identity['sub'] as String;
      email = identity['email'] as String;
      name = identity['name'] as String? ?? email;
    }
    final attempt = await api.send('POST', 'accounts/authorization', {
      'expectedAccountId': id,
    });
    final code = await host.authorizeCloud(
      CloudConfig.serverClientId,
      email,
      includeTasks,
    );
    await api.send('POST', 'accounts/link', {
      'code': code,
      'expectedAccountId': id,
      'attemptId': attempt['attemptId'],
    });
    final account = ConnectedAccount(id: id, email: email, name: name);
    await db.put('account', id, account.toJson());
    return account;
  }

  @override
  Future<String> accessToken(String accountId) =>
      throw UnsupportedError('Google tokens are held by the Nextbell backend.');
  @override
  Future<void> remove(String accountId) async {
    final id = newMutationId();
    await db.put('cloudOutbox', id, {
      'id': id,
      'operation': 'removeAccount',
      'accountId': accountId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
