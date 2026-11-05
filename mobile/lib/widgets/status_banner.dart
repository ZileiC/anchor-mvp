import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

/// A calm, high-contrast explanation of a problem plus a way forward.
///
/// Used for offline mode, missing consents and feature endpoints that are not
/// deployed yet — never a raw error string (SPEC §9 recovery rule).
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.l,
    required this.title,
    this.body,
    this.onRetry,
    this.retryLabel,
    this.extraAction,
    this.tone = BannerTone.notice,
  });

  final L l;
  final String title;
  final String? body;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final Widget? extraAction;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final background = switch (tone) {
      BannerTone.notice => const Color(0xFFFFF4D6),
      BannerTone.problem => const Color(0xFFFFE3E0),
    };
    final borderColor = switch (tone) {
      BannerTone.notice => const Color(0xFF8A5A00),
      BannerTone.problem => AnchorTheme.danger,
    };
    return Container(
      key: const Key('status-banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                tone == BannerTone.problem
                    ? Icons.error_outline
                    : Icons.info_outline,
                size: 30,
                color: borderColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (body != null && body!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              body!,
              style: const TextStyle(
                fontSize: 24,
                color: AnchorTheme.ink,
                height: 1.4,
              ),
            ),
          ],
          if (onRetry != null || extraAction != null) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                if (onRetry != null)
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 28),
                    label: Text(retryLabel ?? l.retry),
                  ),
                ?extraAction,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

enum BannerTone { notice, problem }
