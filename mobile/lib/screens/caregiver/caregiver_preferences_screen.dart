import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/time_picker_dialog.dart';

/// Caregivers may *propose* a greeting window, the daily cap and a pause. Nothing
/// takes effect until the older adult approves it (SPEC §5.1 / S12).
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l.caregiverProposeHint, style: AnchorTheme.reading),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AnchorTheme.minTouchTarget,
                    ),
                    child: OutlinedButton(
                      key: const Key('propose-greeting-start'),
                      onPressed: () => _pick(start: true),
                      child: Text(
                        '${l.settingsFrom} $_greetingStart',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AnchorTheme.minTouchTarget,
                    ),
                    child: OutlinedButton(
                      key: const Key('propose-greeting-end'),
                      onPressed: () => _pick(start: false),
                      child: Text(
                        '${l.settingsTo} $_greetingEnd',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(l.settingsGreeting, style: const TextStyle(fontSize: 24)),
              SwitchListTile(
                key: const Key('propose-paused'),
                value: _paused,
                onChanged: (value) => setState(() => _paused = value),
                title: Text(
                  l.settingsPause,
                  style: const TextStyle(fontSize: 24),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Text(
                l.settingsGreeting,
                style: const TextStyle(
                  fontSize: 22,
                  color: AnchorTheme.inkSoft,
                ),
              ),
              Wrap(
                spacing: 12,
                children: <Widget>[
                  for (final cap in <int>[0, 1])
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AnchorTheme.minTouchTarget,
                      ),
                      child: OutlinedButton(
                        key: ValueKey<String>('propose-cap-$cap'),
                        onPressed: () => setState(() => _dailyCap = cap),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _dailyCap == cap
                              ? const Color(0xFFE3EFE6)
                              : AnchorTheme.surface,
                        ),
                        child: Text(
                          cap == 0
                              ? l.t('不主动问候', 'No check-ins')
                              : l.t('每天一次', 'Once a day'),
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 84),
                child: FilledButton.icon(
                  key: const Key('propose-submit'),
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.send, size: 30),
                  label: Text(
                    l.caregiverPrefs,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
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
              Text(
                l.caregiverMyProposals,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (state.proposals.isEmpty)
                Text(l.caregiverNoProposals, style: AnchorTheme.reading)
              else
                for (final proposal in state.proposals)
                  Container(
                    key: ValueKey<String>('my-proposal-${proposal.id}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AnchorTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AnchorTheme.border, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _describe(l, proposal.payload),
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusLabel(l, proposal.status),
                          style: const TextStyle(
                            fontSize: 22,
                            color: AnchorTheme.accent,
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
