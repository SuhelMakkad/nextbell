import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/application/app_services.dart';
import 'core/theme/app_theme.dart';
import 'features/accounts/presentation/welcome_screen.dart';
import 'features/agenda/presentation/today_screen.dart';
import 'features/agenda/presentation/event_detail_screen.dart';
import 'features/calendar_sources/presentation/calendars_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/tasks/presentation/tasks_screen.dart';
import 'features/sync/application/background_sync.dart';
import 'features/cloud/application/cloud_messages.dart';
import 'features/cloud/presentation/devices_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeCloudMessages();
  } catch (_) {
    // Sign-in and Settings report unavailable configuration without preventing launch.
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(const ProviderScope(child: NextbellApp()));
}

CustomTransitionPage<void> motionPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage(
  key: state.pageKey,
  transitionDuration: Motion.duration(context, Motion.standard),
  reverseTransitionDuration: Motion.duration(context, Motion.standard),
  child: child,
  transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: Motion.reduced(context) ? Offset.zero : const Offset(0, .025),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigator = GlobalKey<NavigatorState>();
  final refresh = ValueNotifier(0);
  ref.listen(snapshotProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    navigatorKey: rootNavigator,
    initialLocation: '/today',
    refreshListenable: refresh,
    redirect: (context, route) {
      final state = ref.read(snapshotProvider).value;
      if (state == null) return null;
      if (state.cloudRequired &&
          !state.cloudSignedIn &&
          !state.demo &&
          !const ['/welcome', '/about'].contains(route.matchedLocation)) {
        return '/welcome';
      }
      if (state.cloudRequired &&
          state.cloudSignedIn &&
          route.matchedLocation == '/welcome') {
        return state.settings.onboarded ? '/today' : '/today/calendars';
      }
      if (!state.cloudRequired &&
          state.accounts.isEmpty &&
          !state.settings.onboarded &&
          !state.demo &&
          !const ['/welcome', '/about'].contains(route.matchedLocation)) {
        return '/welcome';
      }
      if ((!state.cloudRequired &&
              (state.accounts.isNotEmpty ||
                  state.settings.onboarded ||
                  state.demo)) &&
          route.matchedLocation == '/welcome') {
        return !state.settings.onboarded && !state.demo
            ? '/today/calendars'
            : '/today';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) =>
            motionPage(context, state, const WelcomeScreen()),
      ),
      ShellRoute(
        builder: (_, state, child) =>
            _Shell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/today',
            pageBuilder: (context, state) =>
                motionPage(context, state, const TodayScreen()),
            routes: [
              // The agenda stays beneath first-time calendar setup. Neither
              // system Back nor the toolbar can uncover the sign-in screen.
              GoRoute(
                path: 'calendars',
                parentNavigatorKey: rootNavigator,
                pageBuilder: (context, state) =>
                    motionPage(context, state, const CalendarsScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/tasks',
            pageBuilder: (context, state) =>
                motionPage(context, state, const TasksScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                motionPage(context, state, const SettingsScreen()),
          ),
        ],
      ),
      GoRoute(path: '/calendars', redirect: (_, _) => '/today/calendars'),
      GoRoute(
        path: '/devices',
        pageBuilder: (context, state) =>
            motionPage(context, state, const DevicesScreen()),
      ),
      GoRoute(
        path: '/alarm-settings',
        pageBuilder: (context, state) =>
            motionPage(context, state, const AlarmSettingsScreen()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (context, state) =>
            motionPage(context, state, const AboutScreen()),
      ),
      GoRoute(
        path: '/event/:id',
        pageBuilder: (context, state) => motionPage(
          context,
          state,
          EventDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/task/:id',
        pageBuilder: (context, state) => motionPage(
          context,
          state,
          TaskDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class NextbellApp extends ConsumerStatefulWidget {
  const NextbellApp({super.key});
  @override
  ConsumerState<NextbellApp> createState() => _NextbellAppState();
}

class _NextbellAppState extends ConsumerState<NextbellApp>
    with WidgetsBindingObserver {
  Timer? timer;
  bool active = true;
  bool started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (active) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final service = ref.read(servicesProvider);
    await service.ready;
    if (service.demo || !mounted) return;
    try {
      final current = await service.db.snapshot();
      if (current.accounts.isNotEmpty || current.cloudSignedIn) {
        try {
          await registerBackgroundSync();
          await service.db.health({'backgroundError': null});
        } catch (_) {
          await service.db.health({
            'backgroundError':
                'Background refresh is unavailable. Open Nextbell to refresh.',
          });
        }
        await service.sync.run();
      } else {
        await service.alarms.reconcile();
      }
    } catch (_) {
      /* Repositories persist actionable status; no private data is logged. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      unawaited(refresh());
      setState(() {});
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(snapshotProvider).value;
    if (snapshot != null && !started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(refresh()));
    }
    final theme = switch (snapshot?.settings.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'Nextbell',
      debugShowCheckedModeBanner: false,
      theme: nextbellTheme(Brightness.light),
      darkTheme: nextbellTheme(Brightness.dark),
      themeMode: theme,
      themeAnimationDuration:
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations
          ? Duration.zero
          : Motion.standard,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final index = path.startsWith('/tasks')
        ? 1
        : path.startsWith('/settings')
        ? 2
        : 0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: NavigationBar(
                  selectedIndex: index,
                  height: 76,
                  backgroundColor: Theme.of(context).cardTheme.color,
                  indicatorColor: AppColors.indigo.withValues(alpha: .13),
                  surfaceTintColor: Colors.transparent,
                  animationDuration: Motion.duration(context, Motion.standard),
                  onDestinationSelected: (i) =>
                      context.go(['/today', '/tasks', '/settings'][i]),
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.calendar_today_outlined),
                      selectedIcon: const Icon(Icons.calendar_today_rounded),
                      label: AppLocalizations.of(context).today,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      selectedIcon: const Icon(Icons.check_circle_rounded),
                      label: AppLocalizations.of(context).tasks,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.tune_rounded),
                      label: AppLocalizations.of(context).settings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
