import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// The respectful foreground invitation (SPEC §6.2, S1): shown on Home only when
/// the server says an invitation is eligible. Exactly two large choices, never a
/// third, and no urgency language.
class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.l,
    required this.onAccept,
    required this.onDismiss,
    this.busy = false,
  });

  final L l;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('invitation-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AnchorTheme.primary, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.record_voice_over,
                size: 36,
                color: AnchorTheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.invitationTitle,
                  key: const Key('invitation-title'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.invitationBody, style: AnchorTheme.reading),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: FilledButton.icon(
              key: const Key('invitation-accept'),
              onPressed: busy ? null : onAccept,
              icon: const Icon(Icons.chat_bubble_outline, size: 32),
              label: Text(
                l.invitationAccept,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: OutlinedButton.icon(
              key: const Key('invitation-dismiss'),
              onPressed: busy ? null : onDismiss,
              icon: const Icon(Icons.do_not_disturb_on_outlined, size: 30),
              label: Text(
                l.invitationDismiss,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
