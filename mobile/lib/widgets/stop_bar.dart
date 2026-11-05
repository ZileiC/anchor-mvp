import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// The persistent Stop / Not now control required on every senior screen
/// (SPEC §9, S7). It is always the last thing above the system inset, so it
/// never scrolls away and never moves between screens.
class StopBar extends StatelessWidget {
  const StopBar({
    super.key,
    required this.onStop,
    required this.l,
    this.label,
    this.hint,
  });

  final VoidCallback onStop;
  final L l;
  final String? label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = label ?? '${l.stop} · ${l.notNow}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              key: const Key('stop-control'),
              constraints: const BoxConstraints(minHeight: 72),
              child: Semantics(
                button: true,
                label: '$text. ${hint ?? l.stopHint}',
                child: FilledButton.icon(
                  onPressed: onStop,
                  style: FilledButton.styleFrom(
                    backgroundColor: AnchorTheme.danger,
                    foregroundColor: AnchorTheme.onDanger,
                    minimumSize: const Size(AnchorTheme.minTouchTarget, 72),
                    textStyle: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 34),
                  label: Text(
                    text,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint ?? l.stopHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                color: AnchorTheme.muted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
