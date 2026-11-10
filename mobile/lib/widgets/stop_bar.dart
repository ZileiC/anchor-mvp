import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// The persistent Stop control required on every senior screen (SPEC §9, S7).
///
/// Redesigned 2026-11-10 as a sticker rather than a panel: one compact brick
/// bar, the last thing above the system inset, identical on every screen. It
/// never scrolls (the scaffold hosts it in `bottomNavigationBar`), so it is
/// always in the same place under the thumb — the product's escape hatch.
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: ConstrainedBox(
          key: const Key('stop-control'),
          constraints: const BoxConstraints(
            minHeight: 64,
            minWidth: AnchorTheme.minTouchTarget,
          ),
          child: Semantics(
            button: true,
            label: '$text. ${hint ?? l.stopHint}',
            child: FilledButton(
              onPressed: onStop,
              style: FilledButton.styleFrom(
                backgroundColor: AnchorTheme.brick,
                foregroundColor: AnchorTheme.onDanger,
                minimumSize: const Size(AnchorTheme.minTouchTarget, 64),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
                ),
                textStyle: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              // A plain Row with a Flexible label: FilledButton.icon cannot
              // shrink its text, and at 1.3x text "+ 停止 · 现在不要" overflowed
              // the button on a 390 px phone.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.stop_circle_outlined, size: 30),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
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
}
