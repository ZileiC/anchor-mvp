import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/activity.dart';
import '../../state/activity_rotation.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/status_banner.dart';

/// How one tap should feel: an achievement, a gentle correction, or a reply
/// with no verdict at all.
enum _Tone { correct, wrong, open }

/// The feedback for one tap: what is written, what is spoken, and the colour.
///
/// [spoken] is *exactly* the sentence the panel renders, so the voice can never
/// drift from what the senior reads (they are the same string, built once).
typedef _Feedback = ({String title, String body, String spoken, _Tone tone});

/// Pale green — "this one is right". Ink on it stays far above 12:1.
const Color _correctFill = Color(0xFFE3EFE6);

/// Pale amber — "not quite". Warm, never red: a wrong pick is not an alarm.
const Color _wrongFill = Color(0xFFF8ECD8);

/// Neutral warmth for a memory reply, which has no right or wrong answer.
const Color _openFill = Color(0xFFF4EFE5);

/// Play: one of the three curated activity types, with no scores and no
/// rankings anywhere (SPEC §9, S3).
///
/// Answering is one tap and it is final: the card shows a teaching sentence,
/// speaks the same sentence and locks. There is deliberately **no visible
/// clock**: the time spent is still measured (and posted with the session) but
/// never put on screen, because a countdown turns a friendly activity into a
/// test. That was the "rigid" feeling the user reported.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.state, this.clock});

  final AppState state;

  /// Time source for the silently measured duration. Tests inject a fixed one;
  /// the app uses the wall clock.
  final DateTime Function()? clock;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  /// Upper bound on a reported duration, so a suspended machine cannot post a
  /// nonsense number (a session is a few minutes).
  static const int _maxReportedSeconds = 7200;

  late ActivityRotationController _rotation;
  bool _loading = false;
  bool _finished = false;

  /// Index of the option the senior picked; null while the card is still open.
  /// Non-null is also the lock: no second answer can change it.
  int? _chosenIndex;

  /// When the current card was opened. The posted duration is the time actually
  /// spent on the card, measured silently.
  DateTime _cardStartedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _rotation = ActivityRotationController(feed: widget.state.activityFeed);
    _cardStartedAt = _now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool get _answered => _chosenIndex != null;

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
    _openCard();
  }

  /// Opens a fresh card: clears the answer lock, restarts the silent duration
  /// and, for a story, reads it aloud once.
  void _openCard() {
    final item = _rotation.current;
    if (!mounted) return;
    setState(() {
      _chosenIndex = null;
      _finished = false;
      _cardStartedAt = _now();
    });
    final story = item?.story?.trim() ?? '';
    if (story.isNotEmpty) _speak(story);
  }

  /// Fire-and-forget: the sentence is already on screen, so a missing voice must
  /// never surface as an error here.
  void _speak(String text) {
    if (text.trim().isEmpty) return;
    unawaited(widget.state.speakFeedback(text));
  }

  /// Builds the one sentence pair for the pick at [index]. Pure, so the panel
  /// and the voice always agree.
  _Feedback _feedbackFor(L l, ActivityItem item, int index) {
    if (item.hasAnswer) {
      if (item.isCorrect(index)) {
        final body = item.explanation?.trim() ?? '';
        return _compose(l.activityCorrect, body, _Tone.correct);
      }
      final hint = item.wrongHint?.trim() ?? '';
      // On a wrong pick the senior gets the gentle line, the teaching sentence
      // and the right option — the card is locked, so "再想想" would be a lie
      // and the explanation is the only thing that actually teaches.
      final explanation = item.explanation?.trim() ?? '';
      final lines = <String>[
        if (hint.isNotEmpty) hint,
        if (explanation.isNotEmpty) explanation,
        l.activityAnswerWas(item.correctOption!),
      ].where((line) => line.isNotEmpty);
      return _compose(l.activityWrong, lines.join('\n'), _Tone.wrong);
    }
    // Memory, or any card without a graded answer: a warm reply, never a
    // verdict. A missing reply falls back to the thank-you line already shown.
    return _compose(
      l.activityThanks,
      item.replyFor(index)?.trim() ?? '',
      _Tone.open,
    );
  }

  _Feedback _compose(String title, String body, _Tone tone) => (
    title: title,
    body: body,
    spoken: body.isEmpty ? title : '$title\n$body',
    tone: tone,
  );

  void _answer(int index) {
    final item = _rotation.current;
    if (item == null || _answered) return;
    final feedback = _feedbackFor(widget.state.l, item, index);
    setState(() => _chosenIndex = index);
    _speak(feedback.spoken);
  }

  Future<void> _finish({required bool completed}) async {
    final item = _rotation.current;
    if (!mounted) return;
    setState(() => _finished = true);
    if (item == null) return;
    final measured = _now().difference(_cardStartedAt).inSeconds;
    final seconds = measured < 0
        ? 0
        : (measured > _maxReportedSeconds ? _maxReportedSeconds : measured);
    // Posted silently: the senior never sees a clock, the caregiver still gets
    // an honest "how long did this take".
    await widget.state.finishActivity(
      activityId: item.id,
      completed: completed,
      durationSeconds: seconds,
    );
  }

  void _next() {
    _rotation.advance();
    _openCard();
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
            if (item.story?.trim().isNotEmpty ?? false) _storyBlock(l, item),
            Text(item.prompt, style: AnchorTheme.reading),
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

  /// The story a `story` card reads before its question.
  Widget _storyBlock(L l, ActivityItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const Key('activity-story'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AnchorTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AnchorTheme.border, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.menu_book,
                  size: 30,
                  color: AnchorTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.activityListen,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AnchorTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.story!.trim(), style: AnchorTheme.reading),
          ],
        ),
      ),
    );
  }

  Widget _playArea(L l, ActivityItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (item.options.isNotEmpty) ...<Widget>[
          Text(l.activityChoose, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          for (var index = 0; index < item.options.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _option(item, index),
            ),
          if (_answered) _feedbackPanel(l, item),
        ] else ...<Widget>[
          Text(l.activityThink, style: const TextStyle(fontSize: 26)),
          if (_answered) _feedbackPanel(l, item),
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

  /// One big option. After an answer every option is disabled; the correct one
  /// stays visibly marked (green fill, bold text, check icon) so the senior can
  /// learn it, even on a wrong pick.
  Widget _option(ActivityItem item, int index) {
    final option = item.options[index];
    final correct = _answered && item.isCorrect(index);
    final rejected = _answered && _chosenIndex == index && !correct;
    final fill = correct
        ? _correctFill
        : (rejected ? _wrongFill : AnchorTheme.surface);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AnchorTheme.minTouchTarget),
      child: OutlinedButton(
        key: Key('activity-option-$index'),
        onPressed: _answered ? null : () => _answer(index),
        style: OutlinedButton.styleFrom(
          backgroundColor: fill,
          disabledBackgroundColor: fill,
          foregroundColor: AnchorTheme.ink,
          disabledForegroundColor: AnchorTheme.ink,
          alignment: Alignment.centerLeft,
          side: BorderSide(
            color: correct ? AnchorTheme.primary : AnchorTheme.border,
            width: correct ? 3 : 2,
          ),
        ),
        child: Row(
          children: <Widget>[
            if (correct) ...<Widget>[
              const Icon(
                Icons.check_circle,
                size: 30,
                color: AnchorTheme.primary,
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: correct ? FontWeight.w700 : FontWeight.w400,
                  color: AnchorTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The panel that replaces silence after a tap. It renders exactly the
  /// [spoken] sentence, and is a live region so a screen reader announces it.
  Widget _feedbackPanel(L l, ActivityItem item) {
    final feedback = _feedbackFor(l, item, _chosenIndex!);
    final (fill, border, icon, iconColor) = switch (feedback.tone) {
      _Tone.correct => (
        _correctFill,
        AnchorTheme.primary,
        Icons.check_circle,
        AnchorTheme.primary,
      ),
      _Tone.wrong => (
        _wrongFill,
        AnchorTheme.accent,
        Icons.lightbulb_outline,
        AnchorTheme.accent,
      ),
      _Tone.open => (
        _openFill,
        AnchorTheme.border,
        Icons.favorite_border,
        AnchorTheme.primary,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('activity-feedback'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 34, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: feedback.title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AnchorTheme.ink,
                        height: 1.3,
                      ),
                    ),
                    if (feedback.body.isNotEmpty)
                      TextSpan(
                        text: '\n${feedback.body}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w400,
                          color: AnchorTheme.ink,
                          height: 1.45,
                        ),
                      ),
                  ],
                ),
                key: const Key('activity-feedback-text'),
              ),
            ),
          ],
        ),
      ),
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
