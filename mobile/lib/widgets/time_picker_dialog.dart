import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// Large, dependency-free time picker (no `flutter_localizations`, no spinner a
/// shaking hand cannot hit). Returns minutes since midnight, or null.
Future<int?> showLargeTimePicker(
  BuildContext context, {
  required L l,
  required int initialMinuteOfDay,
  required String title,
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _LargeTimeDialog(
      l: l,
      title: title,
      initialMinuteOfDay: initialMinuteOfDay,
    ),
  );
}

class _LargeTimeDialog extends StatefulWidget {
  const _LargeTimeDialog({
    required this.l,
    required this.title,
    required this.initialMinuteOfDay,
  });

  final L l;
  final String title;
  final int initialMinuteOfDay;

  @override
  State<_LargeTimeDialog> createState() => _LargeTimeDialogState();
}

class _LargeTimeDialogState extends State<_LargeTimeDialog> {
  late int _minutes = widget.initialMinuteOfDay;

  static const int _step = 15;

  void _shift(int delta) {
    setState(() {
      _minutes = (_minutes + delta) % (24 * 60);
      if (_minutes < 0) _minutes += 24 * 60;
    });
  }

  String get _label {
    final hour = (_minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (_minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AnchorTheme.surface,
      title: Text(widget.title, style: const TextStyle(fontSize: 28)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _label,
            key: const Key('time-picker-value'),
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              color: AnchorTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _ArrowButton(
                key: const Key('time-picker-minus'),
                icon: Icons.remove,
                label: widget.l.t('-15 分钟', '-15 min'),
                onPressed: () => _shift(-_step),
              ),
              _ArrowButton(
                key: const Key('time-picker-plus'),
                icon: Icons.add,
                label: widget.l.t('+15 分钟', '+15 min'),
                onPressed: () => _shift(_step),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AnchorTheme.minTouchTarget,
          ),
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.l.cancel),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AnchorTheme.minTouchTarget,
          ),
          child: FilledButton(
            key: const Key('time-picker-confirm'),
            onPressed: () => Navigator.of(context).pop(_minutes),
            child: Text(widget.l.ok),
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 120,
        height: 88,
        child: OutlinedButton(
          onPressed: onPressed,
          child: Icon(icon, size: 40),
        ),
      ),
    );
  }
}
