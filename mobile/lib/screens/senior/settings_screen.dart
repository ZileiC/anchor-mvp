import 'package:flutter/material.dart';

import '../../app.dart';
import '../../config.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/hub.dart';
import '../../widgets/closed_on_device.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/time_picker_dialog.dart';
import 'ai_providers_screen.dart';

/// Settings: every autonomy control in one place (SPEC §9, S1/S7/S8/S9).
///
/// Greeting window, quiet hours, pause, pace, short replies, language, memories,
/// sharing topics, digest preview and approval, revocation, deletion, sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _working = false;

  AppState get _state => widget.state;

  Future<void> _run(Future<bool> Function() action) async {
    if (!mounted) return;
    setState(() => _working = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _working = false);
    final l = _state.l;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l.settingsUpdated
              : (_state.lastErrorText ?? l.settingsSaveFailed),
        ),
      ),
    );
  }

  Future<void> _pickTime({
    required String title,
    required String current,
    required Future<bool> Function(String value) save,
  }) async {
    final picked = await showLargeTimePicker(
      context,
      l: _state.l,
      title: title,
      initialMinuteOfDay: Preferences.minuteOfDay(current),
    );
    if (picked == null) return;
    await _run(() => save(Preferences.formatMinuteOfDay(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    // Settings exist only on the family/setup phone (architecture change
    // 2026-11-10). On the Windows appliance this screen is not reachable; a
    // route pushed by hand or restored lands here and bounces back to Home.
    if (!state.policy.setupApp) {
      return ClosedOnDevice(message: state.l.setupNotOnComputer);
    }
    final l = state.l;
    final prefs = state.preferences ?? Preferences.defaults;

    return AnchorScaffold(
      state: state,
      title: l.settingsTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_working) const LinearProgressIndicator(minHeight: 8),
          if (state.offline)
            StatusBanner(
              l: l,
              title: l.offlineTitle,
              body: l.offlineBody,
              onRetry: state.refresh,
            ),
          if (state.lastError != null && !state.offline)
            StatusBanner(
              l: l,
              tone: BannerTone.problem,
              title: state.lastErrorText ?? l.unknownError,
              onRetry: state.refresh,
            ),
          HubSectionLabel(label: l.settingsGroupVoice),
          _scheduleSection(l, state, prefs),
          _voiceSection(l, state, prefs),
          _aiSection(l, state),
          const SizedBox(height: 6),
          HubSectionLabel(label: l.settingsGroupPermissions),
          _consentSection(l, state),
          _sharingSection(l, state),
          const SizedBox(height: 6),
          HubSectionLabel(label: l.settingsGroupRecords),
          _proposalsSection(l, state),
          _memorySection(l, state),
          _digestSection(l, state),
          _familySection(l, state),
          _dataSection(l, state),
        ],
      ),
    );
  }

  // -- schedule ------------------------------------------------------------
  Widget _scheduleSection(L l, AppState state, Preferences prefs) {
    final plan = state.nextReminder;
    return HubPanel(
      title: l.settingsGreeting,
      icon: Icons.wb_sunny_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _timeButton(
                key: const Key('settings-greeting-start'),
                label: '${l.settingsFrom} ${prefs.greetingStart}',
                onTap: () => _pickTime(
                  title: l.settingsGreeting,
                  current: prefs.greetingStart,
                  save: (value) => state.updatePreferences(<String, Object?>{
                    'greeting_start': value,
                  }),
                ),
              ),
              _timeButton(
                key: const Key('settings-greeting-end'),
                label: '${l.settingsTo} ${prefs.greetingEnd}',
                onTap: () => _pickTime(
                  title: l.settingsGreeting,
                  current: prefs.greetingEnd,
                  save: (value) => state.updatePreferences(<String, Object?>{
                    'greeting_end': value,
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(l.settingsQuiet, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(
            l.settingsQuietHint,
            style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _timeButton(
                key: const Key('settings-quiet-start'),
                label: '${l.settingsFrom} ${prefs.quietStart}',
                onTap: () => _pickTime(
                  title: l.settingsQuiet,
                  current: prefs.quietStart,
                  save: (value) => state.updatePreferences(<String, Object?>{
                    'quiet_start': value,
                  }),
                ),
              ),
              _timeButton(
                key: const Key('settings-quiet-end'),
                label: '${l.settingsTo} ${prefs.quietEnd}',
                onTap: () => _pickTime(
                  title: l.settingsQuiet,
                  current: prefs.quietEnd,
                  save: (value) => state.updatePreferences(<String, Object?>{
                    'quiet_end': value,
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            key: const Key('settings-pause'),
            value: prefs.paused,
            onChanged: (value) => _run(
              () => state.updatePreferences(<String, Object?>{'paused': value}),
            ),
            title: Text(l.settingsPause, style: const TextStyle(fontSize: 26)),
            subtitle: Text(
              l.settingsPauseHint,
              style: const TextStyle(fontSize: 22),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          OutlinedButton.icon(
            key: const Key('settings-snooze'),
            onPressed: () => _run(() async {
              await state.snoozeToday();
              return state.lastError == null;
            }),
            icon: const Icon(Icons.do_not_disturb_on_outlined, size: 28),
            label: Text(l.settingsSnooze, style: const TextStyle(fontSize: 24)),
          ),
          SwitchListTile(
            key: const Key('settings-designated-device'),
            value: prefs.designatedDeviceId == AnchorConfig.deviceId,
            onChanged: (value) => _run(
              () => state.updatePreferences(<String, Object?>{
                'designated_device_id': value ? AnchorConfig.deviceId : null,
              }),
            ),
            title: Text(
              l.settingsDesignatedDevice,
              style: const TextStyle(fontSize: 24),
            ),
            subtitle: Text(
              l.settingsDesignatedDeviceHint,
              style: const TextStyle(fontSize: 22),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Text(
            plan == null
                ? l.noNextCheckin
                : '${l.settingsNextCheckin}: ${plan.localDate} ${plan.localTimeLabel}',
            key: const Key('settings-next-checkin'),
            style: const TextStyle(fontSize: 24, color: AnchorTheme.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _timeButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AnchorTheme.minTouchTarget),
      child: OutlinedButton.icon(
        key: key,
        onPressed: onTap,
        icon: const Icon(Icons.schedule, size: 24),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AnchorTheme.minTouchTarget, 64),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
          ),
        ),
      ),
    );
  }

  // -- voice, replies, language -------------------------------------------
  Widget _voiceSection(L l, AppState state, Preferences prefs) {
    return HubPanel(
      title: l.settingsPace,
      icon: Icons.volume_up_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _choice(
                key: const Key('settings-pace-slow'),
                label: l.settingsPaceSlow,
                selected: prefs.isSlowPace,
                onTap: () => _run(
                  () => state.updatePreferences(<String, Object?>{
                    'voice_pace': 'slow',
                  }),
                ),
              ),
              _choice(
                key: const Key('settings-pace-normal'),
                label: l.settingsPaceNormal,
                selected: !prefs.isSlowPace,
                onTap: () => _run(
                  () => state.updatePreferences(<String, Object?>{
                    'voice_pace': 'normal',
                  }),
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('settings-short-replies'),
            value: prefs.shortReplies,
            onChanged: (value) => _run(
              () => state.updatePreferences(<String, Object?>{
                'short_replies': value,
              }),
            ),
            title: Text(l.settingsShort, style: const TextStyle(fontSize: 26)),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Text(l.settingsLanguage, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _choice(
                key: const Key('settings-language-zh'),
                label: l.settingsLanguageZh,
                selected: prefs.language != 'en',
                onTap: () => _run(
                  () => state.updatePreferences(<String, Object?>{
                    'language': 'zh-CN',
                  }),
                ),
              ),
              _choice(
                key: const Key('settings-language-en'),
                label: l.settingsLanguageEn,
                selected: prefs.language == 'en',
                onTap: () => _run(
                  () => state.updatePreferences(<String, Object?>{
                    'language': 'en',
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- AI providers (model + speech recognition) ---------------------------
  Widget _aiSection(L l, AppState state) {
    final providers = state.providers;
    final llmLabel = providers == null
        ? l.aiStatusUnknown
        : (providers.llm.configured ? l.aiStatusHttp : l.aiStatusOfflineLlm);
    final asrLabel = providers == null
        ? l.aiStatusUnknown
        : switch (providers.asr.engine) {
            'windows-sapi' => l.aiAsrEngineWindows,
            'http' => l.aiAsrEngineHttp,
            'fake' => l.aiAsrEngineFake,
            _ => l.aiAsrEngineNone,
          };
    return HubPanel(
      title: l.aiProvidersTitle,
      icon: Icons.smart_toy_outlined,
      hint: l.aiProvidersEntryHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${l.aiLlmSection}：$llmLabel',
            key: const Key('settings-ai-llm-status'),
            style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${l.aiAsrSection}：$asrLabel',
            key: const Key('settings-ai-asr-status'),
            style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('settings-ai-entry'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiProvidersScreen(state: state),
              ),
            ),
            icon: const Icon(Icons.tune, size: 28),
            label: Text(
              l.aiProvidersTitle,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // Selected is a filled jade plate with white text and a tick: three signals,
    // so it still reads on a washed-out screen or in greyscale.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AnchorTheme.minTouchTarget),
      child: OutlinedButton(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected
              ? AnchorTheme.jade
              : AnchorTheme.paperRaised,
          foregroundColor: selected ? AnchorTheme.onPrimary : AnchorTheme.ink,
          minimumSize: const Size(AnchorTheme.minTouchTarget, 60),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(
            color: selected ? AnchorTheme.jade : AnchorTheme.line,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              const Icon(Icons.check, size: 26),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- consents ------------------------------------------------------------
  Widget _consentSection(L l, AppState state) {
    final consent = state.consent;
    return HubPanel(
      title: l.settingsConsents,
      icon: Icons.verified_user_outlined,
      child: Column(
        children: <Widget>[
          _consentSwitch(
            key: const Key('consent-cloud'),
            value: consent.cloudProcessing,
            title: l.settingsConsentCloud,
            onChanged: (value) => _run(
              () => state.setConsent(
                capability: Capabilities.cloudProcessing,
                allowed: value,
              ),
            ),
          ),
          _consentSwitch(
            key: const Key('consent-proactive'),
            value: consent.proactiveInvitations,
            title: l.settingsConsentProactive,
            onChanged: (value) => _run(
              () => state.setConsent(
                capability: Capabilities.proactiveInvitations,
                allowed: value,
              ),
            ),
          ),
          _consentSwitch(
            key: const Key('consent-memory'),
            value: consent.saveMemory,
            title: l.settingsConsentMemory,
            onChanged: (value) => _run(
              () => state.setConsent(
                capability: Capabilities.saveMemory,
                allowed: value,
              ),
            ),
          ),
          _consentSwitch(
            key: const Key('consent-observations'),
            value: consent.recordObservations,
            title: l.settingsConsentObserve,
            onChanged: (value) => _run(
              () => state.setConsent(
                capability: Capabilities.recordObservations,
                allowed: value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _consentSwitch({
    required Key key,
    required bool value,
    required String title,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: key,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 24)),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sharingSection(L l, AppState state) {
    final consent = state.consent;
    return HubPanel(
      title: l.settingsSharing,
      hint: l.settingsSharingHint,
      icon: Icons.share_outlined,
      child: Column(
        children: <Widget>[
          for (final topic in ShareTopics.all)
            SwitchListTile(
              key: ValueKey<String>('share-$topic'),
              value: consent.shareTopicAllowed(topic),
              onChanged: (value) => _run(
                () => state.setConsent(
                  capability: Capabilities.shareTopic,
                  topic: topic,
                  allowed: value,
                ),
              ),
              title: Text(
                l.topicLabel(topic),
                style: const TextStyle(fontSize: 24),
              ),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  // -- family proposals ----------------------------------------------------
  Widget _proposalsSection(L l, AppState state) {
    final pending = state.proposals
        .where((p) => p.status == 'pending')
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return HubPanel(
      title: l.settingsProposals,
      icon: Icons.event_available_outlined,
      child: Column(
        children: <Widget>[
          for (final proposal in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _describeProposal(l, proposal.payload),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: ValueKey<String>('proposal-accept-${proposal.id}'),
                    onPressed: () =>
                        _run(() => state.approveProposal(proposal.id)),
                    child: Text(l.settingsProposalAccept),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _describeProposal(L l, Map<String, Object?> payload) {
    final parts = <String>[];
    final start = payload['greeting_start'];
    final end = payload['greeting_end'];
    if (start != null && end != null) {
      parts.add('${l.settingsGreeting} $start–$end');
    }
    if (payload['paused'] == true) parts.add(l.settingsPause);
    return parts.isEmpty ? l.settingsProposals : parts.join(' · ');
  }

  // -- memories ------------------------------------------------------------
  Widget _memorySection(L l, AppState state) {
    final visible = state.memories
        .where((memory) => memory.approvalState != 'deleted')
        .toList();
    return HubPanel(
      title: l.settingsMemories,
      icon: Icons.bookmark_border,
      child: visible.isEmpty
          ? Text(l.settingsMemoriesEmpty, style: AnchorTheme.reading)
          : Column(
              children: <Widget>[
                for (final memory in visible)
                  Container(
                    key: ValueKey<String>('memory-${memory.id}'),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AnchorTheme.canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AnchorTheme.border, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(memory.fact, style: AnchorTheme.reading),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            if (memory.isProposed)
                              FilledButton(
                                key: ValueKey<String>(
                                  'memory-approve-${memory.id}',
                                ),
                                onPressed: () =>
                                    _run(() => state.approveMemory(memory.id)),
                                child: Text(l.settingsMemoryApprove),
                              ),
                            if (memory.isProposed)
                              Text(
                                l.settingsMemoryProposed,
                                style: const TextStyle(
                                  fontSize: 22,
                                  color: AnchorTheme.accent,
                                ),
                              ),
                            OutlinedButton(
                              key: ValueKey<String>(
                                'memory-delete-${memory.id}',
                              ),
                              onPressed: () =>
                                  _run(() => state.deleteMemory(memory.id)),
                              child: Text(l.settingsMemoryDelete),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // -- digest --------------------------------------------------------------
  Widget _digestSection(L l, AppState state) {
    final digest = state.digests.isEmpty ? null : state.digests.first;
    return HubPanel(
      title: l.settingsDigest,
      icon: Icons.summarize_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.digestFeatureMissing)
            Text(l.caregiverDigestUnavailable, style: AnchorTheme.reading)
          else if (digest == null)
            Text(l.settingsDigestEmpty, style: AnchorTheme.reading)
          else if (digest.isInsufficientData)
            Text(l.caregiverInsufficient, style: AnchorTheme.reading)
          else ...<Widget>[
            if (digest.periodStart != null)
              Text(
                '${digest.periodStart} – ${digest.periodEnd ?? ''}',
                style: const TextStyle(fontSize: 22, color: AnchorTheme.muted),
              ),
            const SizedBox(height: 8),
            for (final item in digest.highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('• ${item.text}', style: AnchorTheme.reading),
              ),
            if (digest.isApproved)
              Text(
                l.settingsDigestApproved,
                style: const TextStyle(
                  fontSize: 24,
                  color: AnchorTheme.primary,
                ),
              )
            else ...<Widget>[
              Text(
                l.settingsDigestWaiting,
                style: const TextStyle(
                  fontSize: 22,
                  color: AnchorTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 8),
              if (digest.canApprove)
                FilledButton(
                  key: const Key('digest-approve'),
                  onPressed: () => _run(() => state.approveDigest(digest)),
                  child: Text(l.settingsDigestApprove),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('digest-edit'),
                onPressed: () => _editDigest(digest),
                child: Text(l.settingsDigestEdit),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editDigest(Digest digest) async {
    final controllers = <TextEditingController>[
      for (final item in digest.highlights)
        TextEditingController(text: item.text),
    ];
    final l = _state.l;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AnchorTheme.surface,
        title: Text(l.settingsDigestEdit, style: const TextStyle(fontSize: 28)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < controllers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    key: ValueKey<String>('digest-item-$index'),
                    controller: controllers[index],
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 24),
                    decoration: InputDecoration(
                      labelText: l.topicLabel(digest.highlights[index].topic),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.cancel),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: FilledButton(
              key: const Key('digest-edit-save'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.save),
            ),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final items = <DigestItem>[
      for (var index = 0; index < digest.highlights.length; index++)
        DigestItem(
          topic: digest.highlights[index].topic,
          text: controllers[index].text.trim(),
          evidenceIds: digest.highlights[index].evidenceIds,
        ),
    ];
    await _run(() => _state.editDigest(digest, items));
  }

  // -- family --------------------------------------------------------------
  Widget _familySection(L l, AppState state) {
    return HubPanel(
      title: l.settingsFamily,
      icon: Icons.family_restroom,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.relationships.isEmpty)
            Text(l.settingsNoFamily, style: AnchorTheme.reading),
          for (final relationship in state.relationships)
            Container(
              key: ValueKey<String>('relationship-${relationship.id}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnchorTheme.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AnchorTheme.border, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    relationship.counterpartName ?? '—',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _relationshipLabel(l, relationship.status),
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      if (relationship.isPending)
                        FilledButton(
                          key: ValueKey<String>(
                            'relationship-approve-${relationship.id}',
                          ),
                          onPressed: () => _run(
                            () => state.approveRelationship(relationship.id),
                          ),
                          child: Text(l.settingsApproveRel),
                        ),
                      if (relationship.status != 'revoked')
                        OutlinedButton(
                          key: ValueKey<String>(
                            'relationship-revoke-${relationship.id}',
                          ),
                          onPressed: () async {
                            final confirmed = await _confirm(
                              title: l.settingsRevoke,
                              body: l.settingsRevokeConfirm,
                            );
                            if (!confirmed) return;
                            await _run(
                              () => state.revokeRelationship(relationship.id),
                            );
                          },
                          child: Text(l.settingsRevoke),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('settings-invite'),
            onPressed: () async {
              final token = await state.createInvitation();
              if (!mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(context);
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    token == null
                        ? l.settingsInviteFailed
                        : l.settingsInviteCode(token),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.person_add_alt, size: 28),
            label: Text(l.settingsInvite, style: const TextStyle(fontSize: 24)),
          ),
          if (state.invitationToken != null) ...<Widget>[
            const SizedBox(height: 10),
            SelectableText(
              state.invitationToken!,
              key: const Key('settings-invite-token'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _relationshipLabel(L l, String status) => switch (status) {
    'accepted' => l.settingsRelAccepted,
    'revoked' => l.settingsRelRevoked,
    _ => l.settingsRelPending,
  };

  // -- data rights ---------------------------------------------------------
  Widget _dataSection(L l, AppState state) {
    return HubPanel(
      title: l.settingsDeleteData,
      icon: Icons.delete_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('settings-delete-data'),
            style: FilledButton.styleFrom(backgroundColor: AnchorTheme.danger),
            onPressed: () async {
              final confirmed = await _confirm(
                title: l.settingsDeleteData,
                body: l.settingsDeleteConfirm,
              );
              if (!confirmed) return;
              await _run(() => state.deleteMyData());
            },
            icon: const Icon(Icons.delete_forever, size: 30),
            label: Text(l.settingsDeleteData),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('settings-sign-out'),
            onPressed: () {
              state.signOut();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.logout, size: 28),
            label: Text(
              l.settingsSignOut,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({required String title, required String body}) async {
    final l = _state.l;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AnchorTheme.surface,
        title: Text(title, style: const TextStyle(fontSize: 28)),
        content: Text(
          body,
          style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
        ),
        actions: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.cancel),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: FilledButton(
              key: const Key('confirm-yes'),
              style: FilledButton.styleFrom(
                backgroundColor: AnchorTheme.danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.ok),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
