import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/status_banner.dart';
import 'caregiver_preferences_screen.dart';
import 'digest_screen.dart';
import 'invitation_screen.dart';

/// Caregiver home: connection and consent status, and the three things a family
/// member may do — read an approved digest, call to check in, propose a schedule.
/// No monitoring feed, no conversation history, no location, no scores.
class CaregiverHomeScreen extends StatelessWidget {
  const CaregiverHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final live = AnchorScope.of(context);
    final l = live.l;
    final accepted = live.relationships
        .where((relationship) => relationship.isAccepted)
        .toList();
    final pending = live.relationships
        .where((relationship) => relationship.isPending)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l.caregiverStatus,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                live.displayName.isEmpty ? l.caregiverTitle : live.displayName,
                style: const TextStyle(
                  fontSize: 24,
                  color: AnchorTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 16),
              if (live.offline)
                StatusBanner(
                  l: l,
                  title: l.offlineTitle,
                  body: l.caregiverDigestUnavailable,
                  onRetry: live.refresh,
                ),
              if (live.lastError != null && !live.offline)
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: live.lastErrorText ?? l.unknownError,
                  onRetry: live.refresh,
                ),
              _statusCard(context, l, live, accepted, pending),
              const SizedBox(height: 16),
              _action(
                context,
                key: const Key('caregiver-digest'),
                icon: Icons.summarize,
                label: l.caregiverDigest,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DigestScreen(state: live),
                  ),
                ),
              ),
              _action(
                context,
                key: const Key('caregiver-prefs'),
                icon: Icons.event_note,
                label: l.caregiverPrefs,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CaregiverPreferencesScreen(state: live),
                  ),
                ),
              ),
              _action(
                context,
                key: const Key('caregiver-invite'),
                icon: Icons.qr_code_2,
                label: l.caregiverInvite,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InvitationScreen(state: live),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('caregiver-refresh'),
                onPressed: live.refresh,
                icon: const Icon(Icons.refresh, size: 28),
                label: Text(
                  l.settingsRefresh,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 20),
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

  Widget _statusCard(
    BuildContext context,
    L l,
    AppState state,
    List<Relationship> accepted,
    List<Relationship> pending,
  ) {
    final String title;
    final String detail;
    final IconData icon;
    if (accepted.isNotEmpty) {
      final name = accepted.first.counterpartName;
      title = name == null
          ? l.settingsRelAccepted
          : l.caregiverConnectedTo(name);
      detail = l.caregiverPrivacy;
      icon = Icons.link;
    } else if (pending.isNotEmpty) {
      title = l.caregiverPending;
      detail = l.settingsRelPending;
      icon = Icons.hourglass_bottom;
    } else {
      title = l.caregiverNotLinked;
      detail = l.caregiverInvite;
      icon = Icons.link_off;
    }
    return Container(
      key: const Key('caregiver-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnchorTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accepted.isNotEmpty ? AnchorTheme.primary : AnchorTheme.border,
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 34, color: AnchorTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AnchorTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: OutlinedButton.icon(
            key: key,
            onPressed: onTap,
            icon: Icon(icon, size: 32),
            label: Text(
              label,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
