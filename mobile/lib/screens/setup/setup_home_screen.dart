import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/status_banner.dart';
import '../caregiver/caregiver_preferences_screen.dart';
import '../caregiver/digest_screen.dart';
import '../caregiver/invitation_screen.dart';
import '../senior/ai_providers_screen.dart';
import '../senior/settings_screen.dart';

/// The phone's home: the family/setup shape of Anchor.
///
/// Architecture change 2026-11-10. This screen configures — AI providers
/// (LLM + ASR), family and invitations, the weekly update, the senior's own
/// settings — and it deliberately has **no** conversation UI: no Talk tile, no
/// Play tile, no microphone button, no spoken reply, no Stop control. Voice
/// lives on the older adult's Windows appliance.
///
/// The first card says that out loud in plain language, because a family member
/// opening the app expects a chat and would otherwise think it is broken.
class SetupHomeScreen extends StatelessWidget {
  const SetupHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l = state.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.setupTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (state.displayName.isNotEmpty) ...<Widget>[
                Text(
                  state.displayName,
                  key: const Key('setup-name'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (state.offline)
                StatusBanner(
                  l: l,
                  title: l.offlineTitle,
                  body: l.caregiverDigestUnavailable,
                  onRetry: state.refresh,
                ),
              if (state.lastError != null && !state.offline)
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: state.lastErrorText ?? l.unknownError,
                  onRetry: state.refresh,
                ),
              _deviceCard(l),
              _aiSection(context, l),
              _familySection(context, l),
              _recordsSection(l),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                key: const Key('setup-refresh'),
                onPressed: state.refresh,
                icon: const Icon(Icons.refresh, size: 28),
                label: Text(
                  l.settingsRefresh,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "This phone only sets things up." One plain sentence, no jargon.
  Widget _deviceCard(L l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        key: const Key('setup-device-note'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AnchorTheme.storyInk, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.computer, size: 32, color: AnchorTheme.storyInk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l.setupDeviceTitle,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AnchorTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.setupDeviceBody,
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
      ),
    );
  }

  Widget _aiSection(BuildContext context, L l) {
    final providers = state.providers;
    return SectionCard(
      title: l.aiProvidersTitle,
      icon: Icons.smart_toy_outlined,
      hint: l.aiProvidersEntryHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Only show a status the app really read: no invented "connected".
          if (providers != null) ...<Widget>[
            Text(
              '${l.aiLlmSection}：'
              '${providers.llm.configured ? l.aiStatusHttp : l.aiStatusOfflineLlm}',
              key: const Key('setup-ai-llm'),
              style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${l.aiAsrSection}：${_asrEngineLabel(l, providers.asr.engine)}',
              key: const Key('setup-ai-asr'),
              style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            key: const Key('setup-ai'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiProvidersScreen(state: state),
              ),
            ),
            icon: const Icon(Icons.tune, size: 28),
            label: Text(
              l.aiProvidersTitle,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(76),
            ),
          ),
        ],
      ),
    );
  }

  String _asrEngineLabel(L l, String engine) => switch (engine) {
    'windows-sapi' => l.aiAsrEngineWindows,
    'http' => l.aiAsrEngineHttp,
    'fake' => l.aiAsrEngineFake,
    _ => l.aiAsrEngineNone,
  };

  Widget _familySection(BuildContext context, L l) {
    return SectionCard(
      title: l.setupFamilyTitle,
      icon: Icons.family_restroom,
      hint: l.setupFamilyHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.isSenior) ...<Widget>[
            // The older adult's account may still check its own settings here;
            // they simply have no conversation on this device.
            _entry(
              context,
              key: const Key('setup-settings'),
              icon: Icons.settings,
              label: l.setupDeviceSettings,
              hint: l.setupDeviceSettingsHint,
              screen: SettingsScreen(state: state),
            ),
            const SizedBox(height: 12),
            Text(
              l.setupSeniorNote,
              key: const Key('setup-senior-note'),
              style: const TextStyle(
                fontSize: 22,
                color: AnchorTheme.inkSoft,
                height: 1.4,
              ),
            ),
          ] else ...<Widget>[
            Text(
              _relationshipLabel(l),
              key: const Key('setup-relationship'),
              style: const TextStyle(
                fontSize: 22,
                color: AnchorTheme.inkSoft,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _entry(
              context,
              key: const Key('setup-invite'),
              icon: Icons.qr_code_2,
              label: l.caregiverInvite,
              screen: InvitationScreen(state: state),
            ),
            const SizedBox(height: 12),
            _entry(
              context,
              key: const Key('setup-digest'),
              icon: Icons.summarize,
              label: l.caregiverDigest,
              screen: DigestScreen(state: state),
            ),
            const SizedBox(height: 12),
            _entry(
              context,
              key: const Key('setup-prefs'),
              icon: Icons.event_note,
              label: l.caregiverPrefs,
              screen: CaregiverPreferencesScreen(state: state),
            ),
          ],
        ],
      ),
    );
  }

  String _relationshipLabel(L l) {
    final accepted = state.relationships.where((r) => r.isAccepted).toList();
    if (accepted.isNotEmpty) {
      final name = accepted.first.counterpartName;
      return name == null
          ? l.settingsRelAccepted
          : l.caregiverConnectedTo(name);
    }
    if (state.relationships.where((r) => r.isPending).isNotEmpty) {
      return l.caregiverPending;
    }
    return l.caregiverNotLinked;
  }

  Widget _recordsSection(L l) {
    return SectionCard(
      title: l.setupRecordsTitle,
      icon: Icons.notifications_none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.setupRecordsDigest(_digestStatusLabel(l)),
            key: const Key('setup-records-digest'),
            style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
          ),
          const SizedBox(height: 8),
          // The audit trail really is written on the computer and has no phone
          // UI yet — saying so is better than inventing a screen for it.
          Text(
            l.setupRecordsHint,
            key: const Key('setup-records-note'),
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.inkSoft,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _digestStatusLabel(L l) {
    if (state.digests.isEmpty) return l.setupNoDigestStatus;
    final digest = state.digests.first;
    if (digest.isInsufficientData) return l.caregiverInsufficient;
    if (digest.isApproved) return l.settingsDigestApproved;
    return l.setupDigestPending;
  }

  Widget _entry(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    String? hint,
    required Widget screen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: OutlinedButton.icon(
            key: key,
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => screen)),
            icon: Icon(icon, size: 30),
            label: Text(
              label,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.inkSoft,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
