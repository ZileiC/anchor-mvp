import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/hub.dart';
import '../../widgets/status_banner.dart';
import 'caregiver_preferences_screen.dart';
import 'digest_screen.dart';
import 'invitation_screen.dart';

/// Caregiver home: connection and consent status, and the three things a family
/// member may do — read an approved digest, call to check in, propose a schedule.
/// No monitoring feed, no conversation history, no location, no scores.
///
/// Redesign 2026-11-11: same panel vocabulary as the phone's setup hub, so a
/// family member meets one app whichever device is in front of them.
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
    final name = live.displayName;

    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              HubHeader(
                eyebrow: l.caregiverStatus,
                title: name.isEmpty ? l.caregiverTitle : name,
              ),
              const SizedBox(height: 18),
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
              _statusPanel(l, accepted, pending),
              const SizedBox(height: 18),
              HubSectionLabel(label: l.setupFamilyTitle),
              HubRow(
                key: const Key('caregiver-digest'),
                icon: Icons.summarize,
                label: l.caregiverDigest,
                onTap: () => _open(context, DigestScreen(state: live)),
              ),
              const SizedBox(height: 12),
              HubRow(
                key: const Key('caregiver-prefs'),
                icon: Icons.event_note,
                label: l.caregiverPrefs,
                onTap: () =>
                    _open(context, CaregiverPreferencesScreen(state: live)),
              ),
              const SizedBox(height: 12),
              HubRow(
                key: const Key('caregiver-invite'),
                icon: Icons.qr_code_2,
                label: l.caregiverInvite,
                onTap: () => _open(context, InvitationScreen(state: live)),
              ),
              const SizedBox(height: 18),
              HubPanel(
                tone: HubTone.plain,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[HubFooterNote(text: l.caregiverPrivacy)],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  key: const Key('caregiver-refresh'),
                  onPressed: live.refresh,
                  icon: const Icon(Icons.refresh, size: 24),
                  label: Text(l.settingsRefresh),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// One panel that answers "am I connected to my family member?" in a word.
  ///
  /// Colour is a second signal only: the title itself says 已连接 / 等待同意 /
  /// 还没有连接, so it still reads correctly in greyscale.
  Widget _statusPanel(
    L l,
    List<Relationship> accepted,
    List<Relationship> pending,
  ) {
    final bool connected = accepted.isNotEmpty;
    final String title;
    final String detail;
    final IconData icon;
    if (connected) {
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFE7EFE9) : AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(
          color: connected ? AnchorTheme.jade : AnchorTheme.line,
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: connected ? AnchorTheme.jade : AnchorTheme.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: connected ? AnchorTheme.jade : AnchorTheme.line,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 28,
              color: connected ? AnchorTheme.onPrimary : AnchorTheme.inkSoft,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.25,
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
}
