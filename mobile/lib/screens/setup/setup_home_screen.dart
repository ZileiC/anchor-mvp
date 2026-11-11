import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/hub.dart';
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
/// Redesign 2026-11-11: the stack of identical outlined buttons became a panel
/// you read top to bottom — a note that says what this device is for, a read-out
/// of the configuration it is responsible for, then rows that open. One filled
/// jade action per screen (connect the AI); everything else is a row.
class SetupHomeScreen extends StatelessWidget {
  const SetupHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l = state.l;
    final name = state.displayName;
    return Scaffold(
      appBar: AppBar(title: Text(l.setupTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              HubHeader(
                eyebrow: l.setupTitle,
                title: name.isEmpty ? l.setupTitle : name,
              ),
              const SizedBox(height: 18),
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
              HubNote(
                key: const Key('setup-device-note'),
                icon: Icons.computer,
                title: l.setupDeviceTitle,
                body: l.setupDeviceBody,
              ),
              const SizedBox(height: 18),
              _aiPanel(context, l),
              const SizedBox(height: 18),
              _familySection(context, l),
              const SizedBox(height: 18),
              _recordsSection(l),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  key: const Key('setup-refresh'),
                  onPressed: state.refresh,
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

  /// What the AI is set to right now, then the one action that changes it.
  ///
  /// The two status lines stay plain `Text` widgets with a stable key: the tests
  /// read their text, and so does anyone checking whether the key was saved.
  Widget _aiPanel(BuildContext context, L l) {
    final providers = state.providers;
    final llm = providers == null
        ? l.aiStatusUnknown
        : providers.llm.configured
        ? l.aiStatusHttp
        : l.aiStatusOfflineLlm;
    final asr = providers == null
        ? l.aiStatusUnknown
        : _asrEngineLabel(l, providers.asr.engine);
    return HubPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AnchorTheme.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnchorTheme.line, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${l.aiLlmSection}：$llm',
                  key: const Key('setup-ai-llm'),
                  style: const TextStyle(
                    fontSize: 23,
                    color: AnchorTheme.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l.aiAsrSection}：$asr',
                  key: const Key('setup-ai-asr'),
                  style: const TextStyle(
                    fontSize: 23,
                    color: AnchorTheme.ink,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          HubPrimaryButton(
            key: const Key('setup-ai'),
            icon: Icons.smart_toy_outlined,
            label: l.aiProvidersTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiProvidersScreen(state: state),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l.aiProvidersEntryHint,
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

  String _asrEngineLabel(L l, String engine) => switch (engine) {
    'windows-sapi' => l.aiAsrEngineWindows,
    'http' => l.aiAsrEngineHttp,
    'fake' => l.aiAsrEngineFake,
    _ => l.aiAsrEngineNone,
  };

  Widget _familySection(BuildContext context, L l) {
    final rows = <Widget>[];
    if (state.isSenior) {
      // The older adult's account may still check its own settings here; they
      // simply have no conversation on this device.
      rows.add(
        HubRow(
          key: const Key('setup-settings'),
          icon: Icons.settings,
          label: l.setupDeviceSettings,
          detail: l.setupDeviceSettingsHint,
          onTap: () => _open(context, SettingsScreen(state: state)),
        ),
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            l.setupSeniorNote,
            key: const Key('setup-senior-note'),
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.inkSoft,
              height: 1.4,
            ),
          ),
        ),
      );
    } else {
      rows.addAll(<Widget>[
        HubRow(
          key: const Key('setup-invite'),
          icon: Icons.qr_code_2,
          label: l.caregiverInvite,
          onTap: () => _open(context, InvitationScreen(state: state)),
        ),
        const SizedBox(height: 12),
        HubRow(
          key: const Key('setup-digest'),
          icon: Icons.summarize,
          label: l.caregiverDigest,
          onTap: () => _open(context, DigestScreen(state: state)),
        ),
        const SizedBox(height: 12),
        HubRow(
          key: const Key('setup-prefs'),
          icon: Icons.event_note,
          label: l.caregiverPrefs,
          onTap: () => _open(context, CaregiverPreferencesScreen(state: state)),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HubSectionLabel(label: l.setupFamilyTitle),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: HubReadout(
              key: const Key('setup-relationship'),
              icon: Icons.people_outline,
              label: l.setupFamilyTitle,
              value: _relationshipLabel(l),
            ),
          ),
        ),
        ...rows,
      ],
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HubSectionLabel(label: l.setupRecordsTitle),
        HubPanel(
          tone: HubTone.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l.setupRecordsDigest(_digestStatusLabel(l)),
                key: const Key('setup-records-digest'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AnchorTheme.ink,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              // The audit trail really is written on the computer and has no
              // phone UI yet — saying so is better than inventing a screen.
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
        ),
      ],
    );
  }

  String _digestStatusLabel(L l) {
    if (state.digests.isEmpty) return l.setupNoDigestStatus;
    final digest = state.digests.first;
    if (digest.isInsufficientData) return l.caregiverInsufficient;
    if (digest.isApproved) return l.settingsDigestApproved;
    return l.setupDigestPending;
  }
}
