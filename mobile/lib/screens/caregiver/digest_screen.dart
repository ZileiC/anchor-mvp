import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/call_helpers.dart';
import '../../widgets/status_banner.dart';

/// The weekly digest a caregiver may read: up to three approved highlights and a
/// call action. Everything else — conversations, memories, raw observations —
/// stays private because the backend refuses it (SPEC §4).
class DigestScreen extends StatefulWidget {
  const DigestScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (widget.state.digests.isNotEmpty) return;
    setState(() => _loading = true);
    await widget.state.loadDigests();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _callCheckIn(AppState state, Contact contact) async {
    await dialWithConfirmation(
      context,
      l: state.l,
      label: contact.label,
      phone: contact.phone,
      dial: () => state.callContact(contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    final l = state.l;
    final digest = state.digests.isEmpty ? null : state.digests.first;
    final contact = state.digestContact;

    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverDigestTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_loading) const LinearProgressIndicator(minHeight: 8),
              if (state.offline)
                StatusBanner(
                  l: l,
                  title: l.offlineTitle,
                  body: l.caregiverNoDigest,
                  onRetry: _load,
                ),
              if (state.lastError != null && !state.offline)
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: state.lastErrorText ?? l.unknownError,
                  onRetry: _load,
                ),
              if (state.digestFeatureMissing)
                Text(l.caregiverDigestUnavailable, style: AnchorTheme.reading)
              else if (digest == null)
                Text(
                  state.digestNote == 'insufficient_information'
                      ? l.caregiverInsufficient
                      : l.caregiverNoDigest,
                  style: AnchorTheme.reading,
                )
              else if (digest.isInsufficientData)
                Text(l.caregiverInsufficient, style: AnchorTheme.reading)
              else ...<Widget>[
                if (digest.periodStart != null)
                  Text(
                    '${digest.periodStart} – ${digest.periodEnd ?? ''}',
                    style: const TextStyle(
                      fontSize: 22,
                      color: AnchorTheme.muted,
                    ),
                  ),
                const SizedBox(height: 12),
                for (var index = 0; index < digest.highlights.length; index++)
                  _HighlightCard(
                    key: ValueKey<String>('highlight-$index'),
                    index: index,
                    item: digest.highlights[index],
                    l: l,
                  ),
                if (digest.highlights.isEmpty)
                  Text(l.caregiverInsufficient, style: AnchorTheme.reading),
              ],
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 84),
                child: FilledButton.icon(
                  key: const Key('caregiver-call-checkin'),
                  onPressed: contact == null
                      ? null
                      : () => _callCheckIn(state, contact),
                  icon: const Icon(Icons.phone_in_talk, size: 32),
                  label: Text(
                    contact == null
                        ? l.caregiverCallCheckin
                        : '${l.caregiverCallCheckin} · ${contact.label}',
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              if (contact == null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  l.caregiverNoDigestContact,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AnchorTheme.inkSoft,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l.caregiverPrivacy,
                style: const TextStyle(
                  fontSize: 22,
                  color: AnchorTheme.inkSoft,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    super.key,
    required this.index,
    required this.item,
    required this.l,
  });

  final int index;
  final DigestItem item;
  final L l;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnchorTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AnchorTheme.border, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor: AnchorTheme.primary,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 22,
                color: AnchorTheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.topicLabel(item.topic),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.text, style: AnchorTheme.reading),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
