import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/activity.dart';
import '../../state/activity_rotation.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/status_banner.dart';

/// Play: one of the three curated activity types, a friendly three-minute
/// session and no scores or rankings anywhere (SPEC §9, S3).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const int _sessionSeconds = 180;

  late ActivityRotationController _rotation;
  Timer? _timer;
  int _remaining = _sessionSeconds;
  bool _loading = false;
  bool _finished = false;
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _rotation = ActivityRotationController(feed: widget.state.activityFeed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    if (_rotation.isEmpty) {
      setState(() => _loading = true);
      await widget.state.loadActivities();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rotation = ActivityRotationController(feed: widget.state.activityFeed);
      });
    }
    if (_rotation.isEmpty) return;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final seconds = (_rotation.current?.minutes ?? 3) * 60;
    setState(() {
      _remaining = seconds <= 0 ? _sessionSeconds : seconds;
      _finished = false;
      _chosen = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining = _remaining - 1);
      if (_remaining <= 0) {
        timer.cancel();
        _finish(completed: true);
      }
    });
  }

  Future<void> _finish({required bool completed}) async {
    _timer?.cancel();
    final item = _rotation.current;
    if (!mounted) return;
    setState(() => _finished = true);
    if (item == null) return;
    final raw = (item.minutes * 60) - _remaining;
    final elapsed = raw < 0 ? 0 : (raw > 7200 ? 7200 : raw);
    await widget.state.finishActivity(
      activityId: item.id,
      completed: completed,
      durationSeconds: elapsed,
    );
  }

  Future<void> _next() async {
    _rotation.advance();
    _startTimer();
  }

  String get _timerLabel {
    final l = widget.state.l;
    if (_remaining >= 60) {
      return l.activityMinutesLeft((_remaining / 60).ceil());
    }
    return l.activitySecondsLeft(_remaining < 0 ? 0 : _remaining);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = state.l;
    final item = _rotation.current;
    return AnchorScaffold(
      state: state,
      title: l.activityTitle,
      onStop: () async {
        _timer?.cancel();
        await state.stopAll();
        if (!mounted) return;
        setState(() => _finished = true);
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.offline)
            StatusBanner(
              l: l,
              title: l.offlineTitle,
              body: _rotation.isEmpty ? l.activityNoCache : l.activityCached,
              onRetry: _bootstrap,
            ),
          if (state.lastError != null && !state.offline)
            StatusBanner(
              l: l,
              tone: BannerTone.problem,
              title: state.lastErrorText ?? l.unknownError,
              onRetry: _bootstrap,
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(minHeight: 8),
            ),
          if (item == null && !_loading) _empty(l),
          if (item != null) ...<Widget>[
            _typeChip(l, item),
            const SizedBox(height: 12),
            Text(
              item.title,
              key: const Key('activity-title'),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(item.prompt, style: AnchorTheme.reading),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.timer_outlined,
                  size: 28,
                  color: AnchorTheme.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  _timerLabel,
                  key: const Key('activity-timer'),
                  style: const TextStyle(
                    fontSize: 24,
                    color: AnchorTheme.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_finished) _finishedPanel(l, item) else _playArea(l, item),
          ],
        ],
      ),
    );
  }

  Widget _empty(L l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l.activityEmpty, style: AnchorTheme.reading),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('activity-retry'),
          onPressed: _bootstrap,
          icon: const Icon(Icons.refresh, size: 30),
          label: Text(l.retry),
        ),
      ],
    );
  }

  Widget _typeChip(L l, ActivityItem item) {
    final label = switch (item.type) {
      'trivia' => l.activityTrivia,
      'story' => l.activityStory,
      _ => l.activityMemory,
    };
    final icon = switch (item.type) {
      'trivia' => Icons.quiz,
      'story' => Icons.menu_book,
      _ => Icons.psychology_alt,
    };
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AnchorTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AnchorTheme.border, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 26, color: AnchorTheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playArea(L l, ActivityItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (item.options.isNotEmpty) ...<Widget>[
          Text(l.activityChoose, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          for (final option in item.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AnchorTheme.minTouchTarget,
                ),
                child: OutlinedButton(
                  onPressed: () => setState(() => _chosen = option),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _chosen == option
                        ? const Color(0xFFE3EFE6)
                        : AnchorTheme.surface,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(option, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
        ] else
          Text(l.activityThink, style: const TextStyle(fontSize: 26)),
        if (_chosen != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            key: const Key('activity-feedback'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EFE6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnchorTheme.primary, width: 2),
            ),
            child: Text(
              item.answer == null || item.answer!.isEmpty
                  ? l.activityThanks
                  : '${l.activityThanks}\n${item.answer}',
              style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('activity-next'),
          onPressed: _next,
          icon: const Icon(Icons.skip_next, size: 30),
          label: Text(l.activityAnother),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('activity-finish'),
          onPressed: () => _finish(completed: true),
          icon: const Icon(Icons.check, size: 30),
          label: Text(l.activityFinish),
        ),
      ],
    );
  }

  Widget _finishedPanel(L l, ActivityItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          key: const Key('activity-done'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE3EFE6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AnchorTheme.primary, width: 2),
          ),
          child: Text(
            l.activityDone,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AnchorTheme.ink,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('activity-another'),
          onPressed: _next,
          icon: const Icon(Icons.skip_next, size: 30),
          label: Text(l.activityAnother),
        ),
      ],
    );
  }
}
