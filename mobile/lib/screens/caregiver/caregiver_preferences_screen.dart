import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/hub.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/time_picker_dialog.dart';

/// Caregivers may *propose* a greeting window, the daily cap and a pause. Nothing
/// takes effect until the older adult approves it (SPEC §5.1 / S12).
///
/// Redesign 2026-11-11: the form is grouped into three labelled decisions with
/// one filled action at the end, and the consent rule is stated once, up front,
/// instead of being buried in the middle of a control.
class CaregiverPreferencesScreen extends StatefulWidget {
  const CaregiverPreferencesScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CaregiverPreferencesScreen> createState() =>
      _CaregiverPreferencesScreenState();
}

class _CaregiverPreferencesScreenState
    extends State<CaregiverPreferencesScreen> {
  String _greetingStart = '09:00';
  String _greetingEnd = '11:00';
  int _dailyCap = 1;
  bool _paused = false;
  bool _busy = false;
  bool _sent = false;

  Future<void> _pick({required bool start}) async {
    final current = start ? _greetingStart : _greetingEnd;
    final picked = await showLargeTimePicker(
      context,
      l: widget.state.l,
      title: widget.state.l.settingsGreeting,
      initialMinuteOfDay: Preferences.minuteOfDay(current),
    );
    if (picked == null) return;
    setState(() {
      final value = Preferences.formatMinuteOfDay(picked);
      if (start) {
        _greetingStart = value;
      } else {
        _greetingEnd = value;
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _sent = false;
    });
    final ok = await widget.state.proposeSchedule(<String, Object?>{
      'greeting_start': _greetingStart,
      'greeting_end': _greetingEnd,
      'daily_cap': _dailyCap,
      'paused': _paused,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    final l = state.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverPrefs)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              HubNote(
                icon: Icons.handshake_outlined,
                title: l.caregiverPrefs,
                body: l.caregiverProposeHint,
              ),
              const SizedBox(height: 20),
              HubSectionLabel(label: l.settingsGreeting),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('propose-greeting-start'),
                    onPressed: () => _pick(start: true),
                    icon: const Icon(Icons.schedule, size: 26),
                    label: Text('${l.settingsFrom} $_greetingStart'),
                    style: _timeButtonStyle,
                  ),
                  OutlinedButton.icon(
                    key: const Key('propose-greeting-end'),
                    onPressed: () => _pick(start: false),
                    icon: const Icon(Icons.schedule, size: 26),
                    label: Text('${l.settingsTo} $_greetingEnd'),
                    style: _timeButtonStyle,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              HubSectionLabel(label: l.caregiverDailyCap),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final cap in <int>[0, 1])
                    _Choice(
                      key: ValueKey<String>('propose-cap-$cap'),
                      selected: _dailyCap == cap,
                      label: cap == 0
                          ? l.t('不主动问候', 'No check-ins')
                          : l.t('每天一次', 'Once a day'),
                      onTap: () => setState(() => _dailyCap = cap),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              HubPanel(
                tone: HubTone.plain,
                child: SwitchListTile(
                  key: const Key('propose-paused'),
                  value: _paused,
                  onChanged: (value) => setState(() => _paused = value),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l.settingsPause,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AnchorTheme.ink,
                    ),
                  ),
                  subtitle: Text(
                    l.caregiverPausedHint,
                    style: const TextStyle(
                      fontSize: 22,
                      color: AnchorTheme.inkSoft,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              HubPrimaryButton(
                key: const Key('propose-submit'),
                icon: Icons.send,
                label: l.caregiverPrefs,
                onPressed: _busy ? null : _submit,
              ),
              if (_busy) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 8),
              ],
              if (_sent) ...<Widget>[
                const SizedBox(height: 16),
                StatusBanner(
                  l: l,
                  title: l.caregiverProposeSent,
                  tone: BannerTone.notice,
                ),
              ],
              if (state.lastError != null && !_sent) ...<Widget>[
                const SizedBox(height: 16),
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: state.lastErrorText ?? l.caregiverProposeFailed,
                  onRetry: _submit,
                ),
              ],
              const SizedBox(height: 24),
              HubSectionLabel(label: l.caregiverMyProposals),
              if (state.proposals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: HubFooterNote(text: l.caregiverNoProposals),
                )
              else
                for (final proposal in state.proposals)
                  Container(
                    key: ValueKey<String>('my-proposal-${proposal.id}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AnchorTheme.paperRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AnchorTheme.line, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _describe(l, proposal.payload),
                          style: const TextStyle(
                            fontSize: 24,
                            color: AnchorTheme.ink,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusLabel(l, proposal.status),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _statusColour(proposal.status),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static final ButtonStyle _timeButtonStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(AnchorTheme.minTouchTarget, 64),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
    ),
  );

  Color _statusColour(String status) => switch (status) {
    'approved' => AnchorTheme.jade,
    'rejected' || 'cancelled' => AnchorTheme.inkSoft,
    _ => AnchorTheme.ochre,
  };

  String _describe(L l, Map<String, Object?> payload) {
    final start = payload['greeting_start'];
    final end = payload['greeting_end'];
    final paused = payload['paused'];
    final parts = <String>[];
    if (start != null && end != null) parts.add('$start–$end');
    if (paused == true) parts.add(l.settingsPause);
    return parts.isEmpty ? l.caregiverPrefs : parts.join(' · ');
  }

  String _statusLabel(L l, String status) => switch (status) {
    'approved' => l.proposalApproved,
    'rejected' || 'cancelled' => l.proposalRejected,
    _ => l.proposalPending,
  };
}

/// A two-state choice that is legible without colour: the picked one also gets a
/// filled background, white text and a check mark.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AnchorTheme.onPrimary : AnchorTheme.ink;
    return Material(
      color: selected ? AnchorTheme.jade : AnchorTheme.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
        side: BorderSide(
          color: selected ? AnchorTheme.jade : AnchorTheme.line,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                const Icon(
                  Icons.check_circle,
                  size: 26,
                  color: AnchorTheme.onPrimary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
