import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 38, this.wordmark = true});
  final double size;
  final bool wordmark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.indigo,
          borderRadius: BorderRadius.circular(size * .32),
        ),
        child: Transform.rotate(
          angle: -.13,
          child: Icon(
            Icons.notifications_rounded,
            size: size * .65,
            color: Colors.white,
          ),
        ),
      ),
      if (wordmark) ...[
        const SizedBox(width: 10),
        Text(
          'nextbell',
          style: TextStyle(
            fontSize: size * .61,
            fontWeight: FontWeight.w800,
            letterSpacing: -.9,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    ],
  );
}

class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child, this.spring = false});
  final Widget child;
  final bool spring;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => down = true),
    onPointerCancel: (_) => setState(() => down = false),
    onPointerUp: (_) => setState(() => down = false),
    child: AnimatedScale(
      scale: down && !Motion.reduced(context) ? .97 : 1,
      duration: Motion.duration(context, Motion.quick),
      curve: widget.spring && !down ? Curves.easeOutBack : Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class AsyncButton extends StatefulWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool outlined;
  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool busy = false;
  Future<void> _run() async {
    if (busy || widget.onPressed == null) return;
    setState(() => busy = true);
    await perform(context, widget.onPressed!);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 21),
        if (busy || widget.icon != null) const SizedBox(width: 10),
        Flexible(child: Text(widget.label)),
      ],
    );
    return PressFeedback(
      child: widget.outlined
          ? OutlinedButton(
              onPressed: busy || widget.onPressed == null ? null : _run,
              child: child,
            )
          : FilledButton(
              onPressed: busy || widget.onPressed == null ? null : _run,
              child: child,
            ),
    );
  }
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) showMessage(context, success);
    return true;
  } catch (e) {
    if (context.mounted) {
      final message = switch (e) {
        StateError e => e.message,
        ArgumentError e => e.message.toString(),
        PlatformException e when e.code == 'cancelled' =>
          'Connection cancelled. You can try again any time.',
        PlatformException e when e.code == 'permission' =>
          'Allow alarms in your device settings first.',
        _ => 'That didn’t finish. Check Settings for details and try again.',
      };
      showMessage(context, message);
    }
    return false;
  }
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: Motion.delight,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context) || widget.index >= 5) {
      controller.value = 1;
    } else if (controller.value == 0) {
      Future<void>.delayed(
        Duration(milliseconds: math.min(widget.index, 4) * 35),
        () {
          if (mounted) controller.forward();
        },
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: controller,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
      ),
      child: widget.child,
    ),
  );
}

class BellDelight extends StatefulWidget {
  const BellDelight({
    super.key,
    required this.trigger,
    this.size = 28,
    this.color,
  });
  final int trigger;
  final double size;
  final Color? color;
  @override
  State<BellDelight> createState() => _BellDelightState();
}

class _BellDelightState extends State<BellDelight>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: Motion.delight,
  );
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized && widget.trigger > 0 && !Motion.reduced(context)) {
      controller.forward();
    }
    initialized = true;
  }

  @override
  void didUpdateWidget(BellDelight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && !Motion.reduced(context)) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => Transform.rotate(
      angle: Motion.reduced(context)
          ? 0
          : math.sin(controller.value * math.pi * 5) *
                (1 - controller.value) *
                .25,
      child: child,
    ),
    child: Icon(
      Icons.notifications_active_rounded,
      size: widget.size,
      color: widget.color,
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ColorScheme.fromSeed(
      seedColor: color ?? theme.colorScheme.primary,
      brightness: theme.brightness,
    ).primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(
    this.message, {
    super.key,
    this.onTap,
    this.icon = Icons.info_outline_rounded,
  });
  final String message;
  final VoidCallback? onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer
        .withValues(alpha: .5),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.wb_sunny_outlined,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.indigo.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 42, color: AppColors.indigo),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Reset',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
