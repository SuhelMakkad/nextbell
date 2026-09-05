import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(),
                const SizedBox(height: 42),
                Entrance(
                  child: ExcludeSemantics(
                    child: MediaQuery.withNoTextScaling(
                      child: const _WelcomeIllustration(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'A little ahead.\nA lot more present.',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontSize: 38),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Your calendars, with a gentle nudge that actually rings. Make room for the moment — we’ll keep an eye on the time.',
                  style: TextStyle(fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 24),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill(
                      'Your Google calendars',
                      icon: Icons.calendar_month_outlined,
                    ),
                    Pill('Your timing', icon: Icons.tune_rounded),
                    Pill('Ready for travel', icon: Icons.public_rounded),
                  ],
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  child: AsyncButton(
                    label: 'Continue with Google',
                    icon: Icons.account_circle_outlined,
                    onPressed: () async {
                      await ref.read(servicesProvider).ready;
                      await ref.read(servicesProvider).connect();
                      // Authentication updates the router as soon as the
                      // account is persisted. Never await a pushed page here:
                      // that would keep the sign-in button busy until Back.
                      if (context.mounted) context.go('/calendars');
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(demoModeProvider.notifier).set(true),
                    child: const Text('Take a look around first →'),
                  ),
                ),
                const SizedBox(height: 18),
                if (ref.watch(snapshotProvider).value?.cloudRequired == true &&
                    ref.watch(snapshotProvider).value?.accounts.isNotEmpty ==
                        true)
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                            context,
                            'Start the cloud beta?',
                            'This resets development data and cancels this phone’s existing alarms. You can then sign in and choose your calendars again.',
                            action: 'Reset this phone',
                          ) &&
                          context.mounted) {
                        await perform(
                          context,
                          ref.read(servicesProvider).resetForCloud,
                        );
                      }
                    },
                    child: const Text('Reset this phone for the cloud beta'),
                  ),
                Text(
                  'Only the calendars you choose. No ads. Nextbell securely syncs your selected Google data and reminder settings; your phone rings even offline.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/about'),
                    child: const Text('Privacy & how it works'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 238,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 206,
          height: 206,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.indigo.withValues(alpha: .07),
          ),
        ),
        Container(
          width: 156,
          height: 156,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.indigo.withValues(alpha: .08),
          ),
        ),
        Transform.rotate(
          angle: -.13,
          child: Container(
            width: 94,
            height: 108,
            decoration: BoxDecoration(
              color: AppColors.indigo,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: .2),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_rounded,
              color: Colors.white,
              size: 65,
            ),
          ),
        ),
        Positioned(
          top: 15,
          right: 15,
          child: Transform.rotate(
            angle: .07,
            child: const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xff2f9c7e),
                      size: 18,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Right on time',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 5,
          left: 0,
          child: Transform.rotate(
            angle: -.04,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.indigo,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your next good idea',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'A 5-minute head start',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: Color(0xffd6a250),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
