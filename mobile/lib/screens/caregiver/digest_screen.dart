import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/call_helpers.dart';
import '../../widgets/hub.dart';
import '../../widgets/status_banner.dart';

/// The weekly digest a caregiver may read: up to three approved highlights and a
/// call action. Everything else — conversations, memories, raw observations —
/// stays private because the backend refuses it (SPEC §4).
///
/// Redesign 2026-11-11: the highlights are the page; the period is a small rule
/// above them, and the one filled action is the phone call at the bottom.
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
    final period = digest == null || digest.periodStart == null
        ? null
        : '${digest.periodStart} – ${digest.periodEnd ?? ''}';

    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverDigestTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_loading) ...<Widget>[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 8),
                const SizedBox(height: 14),
              ],
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
                _quiet(l.caregiverDigestUnavailable)
              else if (digest == null)
                _quiet(
                  state.digestNote == 'insufficient_information'
                      ? l.caregiverInsufficient
                      : l.caregiverNoDigest,
                )
              else if (digest.isInsufficientData)
                _quiet(l.caregiverInsufficient)
              else ...<Widget>[
                if (period != null) ...<Widget>[
                  HubSectionLabel(label: period),
                  const SizedBox(height: 2),
                ],
                for (var index = 0; index < digest.highlights.length; index++)
                  _HighlightCard(
                    key: ValueKey<String>('highlight-$index'),
                    index: index,
                    item: digest.highlights[index],
                    l: l,
                  ),
                if (digest.highlights.isEmpty) _quiet(l.caregiverInsufficient),
              ],
              const SizedBox(height: 8),
              HubPrimaryButton(
                key: const Key('caregiver-call-checkin'),
                icon: Icons.phone_in_talk,
                label: contact == null
                    ? l.caregiverCallCheckin
                    : '${l.caregiverCallCheckin} · ${contact.label}',
                onPressed: contact == null
                    ? null
                    : () => _callCheckIn(state, contact),
              ),
              if (contact == null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  l.caregiverNoDigestContact,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AnchorTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              HubFooterNote(text: l.caregiverPrivacy),
            ],
          ),
        ),
      ),
    );
  }

  /// A sentence in a quiet panel, for every state where there is nothing to show
  /// yet. Never a blank page and never an invented highlight.
  Widget _quiet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HubPanel(
        tone: HubTone.ochre,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 24,
            color: AnchorTheme.ink,
            height: 1.4,
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(color: AnchorTheme.line, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE7EFE9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.jade,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.topicLabel(item.topic),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ochre,
                    letterSpacing: 0.6,
                    height: 1.3,
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
