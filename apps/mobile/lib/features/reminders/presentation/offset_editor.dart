import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

class OffsetChoice {
  const OffsetChoice(this.minutes);
  final List<int>? minutes;
}

Future<OffsetChoice?> showOffsetEditor(
  BuildContext context, {
  required String title,
  required List<int>? current,
  required List<int> inherited,
  bool allowInherit = true,
}) => showModalBottomSheet<OffsetChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _OffsetEditor(
    title: title,
    current: current,
    inherited: inherited,
    allowInherit: allowInherit,
  ),
);

class _OffsetEditor extends StatefulWidget {
  const _OffsetEditor({
    required this.title,
    required this.current,
    required this.inherited,
    required this.allowInherit,
  });
  final String title;
  final List<int>? current;
  final List<int> inherited;
  final bool allowInherit;
  @override
  State<_OffsetEditor> createState() => _OffsetEditorState();
}

class _OffsetEditorState extends State<_OffsetEditor> {
  late bool inherit = widget.current == null && widget.allowInherit;
  late final Set<int> values = {...widget.current ?? widget.inherited};
  final input = TextEditingController();
  int unit = 1;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void add() {
    final value = int.tryParse(input.text);
    if (value == null || value < 0 || value * unit > 40320) {
      setState(() => error = 'Choose a time from 0 minutes to 4 weeks.');
      return;
    }
    setState(() {
      inherit = false;
      values.add(value * unit);
      error = null;
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = values.toList()..sort();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('A little heads-up, exactly when you need it.'),
            if (widget.allowInherit)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use inherited defaults'),
                subtitle: Text(formatOffsets(widget.inherited)),
                value: inherit,
                onChanged: (v) => setState(() => inherit = v),
              ),
            const SizedBox(height: 20),
            Text(
              'BEFORE IT STARTS',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final value in ({
                  5,
                  10,
                  15,
                  30,
                  60,
                  ...selected,
                }.toList()..sort()))
                  PressFeedback(
                    spring: true,
                    child: FilterChip(
                      label: Text(offsetLabel(value)),
                      selected: !inherit && values.contains(value),
                      onSelected: (v) => setState(() {
                        inherit = false;
                        v ? values.add(value) : values.remove(value);
                      }),
                      selectedColor: AppColors.indigo.withValues(alpha: .15),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Custom'),
                    onSubmitted: (_) => add(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Minutes')),
                      DropdownMenuItem(value: 60, child: Text('Hours')),
                      DropdownMenuItem(value: 1440, child: Text('Days')),
                    ],
                    onChanged: (v) => setState(() => unit = v!),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: add,
                  tooltip: 'Add custom reminder',
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() {
                inherit = false;
                values.clear();
              }),
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: const Text('No reminders'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    OffsetChoice(inherit ? null : normalizeOffsets(values)),
                  );
                },
                child: Text(
                  inherit
                      ? 'Use defaults'
                      : values.isEmpty
                      ? 'Turn reminders off'
                      : 'Save reminders',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String offsetLabel(int value) => value == 0
    ? 'At start'
    : value % 1440 == 0
    ? '${value ~/ 1440}d'
    : value % 60 == 0
    ? '${value ~/ 60}h'
    : '${value}m';
String formatOffsets(List<int> values) => values.isEmpty
    ? 'No reminders'
    : '${values.map(offsetLabel).join(' · ')} before';
