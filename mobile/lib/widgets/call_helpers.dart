import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/dialer.dart';
import '../theme.dart';

/// Confirmation before a consequential action (SPEC §5.4 / S6). Calling is
/// consequential, so it always asks once — that is still one tap to reach it.
Future<bool> confirmDial(
  BuildContext context, {
  required L l,
  required String label,
  required String phone,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AnchorTheme.surface,
      title: Text(l.callConfirm(label), style: const TextStyle(fontSize: 30)),
      content: Text(
        phone,
        key: const Key('confirm-dial-number'),
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AnchorTheme.ink,
        ),
      ),
      actions: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AnchorTheme.minTouchTarget,
          ),
          child: TextButton(
            key: const Key('confirm-dial-no'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.callNo),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AnchorTheme.minTouchTarget,
          ),
          child: FilledButton(
            key: const Key('confirm-dial-yes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.callYes),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shown when the platform refused to open the dialer: the number stays visible
/// and readable instead of the action silently doing nothing (SPEC §9).
Future<void> showDialFallback(
  BuildContext context, {
  required L l,
  required DialResult result,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AnchorTheme.surface,
      title: Text(l.callTitle, style: const TextStyle(fontSize: 28)),
      content: Text(
        result.phone.isEmpty
            ? (l.callNoContacts)
            : l.callLaunchFailed(result.phone),
        key: const Key('dial-fallback-number'),
        style: const TextStyle(
          fontSize: 26,
          color: AnchorTheme.ink,
          height: 1.4,
        ),
      ),
      actions: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AnchorTheme.minTouchTarget,
          ),
          child: FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.ok),
          ),
        ),
      ],
    ),
  );
}

/// Dial one contact with confirmation, then report a failure honestly.
Future<DialResult?> dialWithConfirmation(
  BuildContext context, {
  required L l,
  required String label,
  required String phone,
  required Future<DialResult> Function() dial,
}) async {
  final confirmed = await confirmDial(
    context,
    l: l,
    label: label,
    phone: phone,
  );
  if (!confirmed) return null;
  final result = await dial();
  if (!result.launched && context.mounted) {
    await showDialFallback(context, l: l, result: result);
  }
  return result;
}
