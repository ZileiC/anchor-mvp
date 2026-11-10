import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/activity.dart';
import '../../services/answer_matcher.dart';
import '../../state/activity_grading.dart';
import '../../state/activity_rotation.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/status_banner.dart';

/// The voice button's three states: nothing happening, the microphone is open
/// ("我在听…"), or the clip is being turned into words ("稍等一下…").
enum _VoicePhase { idle, listening, working }

/// Play: one of the three curated activity types, with no scores and no
/// rankings anywhere (SPEC §9, S3).
///
/// Answering is one tap and it is final: the card shows a teaching sentence,
/// speaks the same sentence and locks. The question itself is spoken when the
/// card opens (and again on "再念一遍"), and the answer may be **said** instead of
/// tapped: the big voice button records one short clip, the backend transcribes
/// it, and the transcript is matched to an option and graded exactly like a tap.
/// There is deliberately **no visible clock**: the time spent is still measured
/// (and posted with the session) but never put on screen, because a countdown
/// turns a friendly activity into a test. That was the "rigid" feeling the user
/// reported.
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

  /// Height of the voice answer button. Bigger than the 56 px minimum because it
  /// is the alternative to tapping for someone who would rather not tap at all.
  static const double _voiceButtonHeight = 72;

  late ActivityRotationController _rotation;
  bool _loading = false;
  bool _finished = false;

  /// Index of the option the senior picked; null while the card is still open.
  /// Non-null is also the lock: no second answer can change it.
  int? _chosenIndex;

  /// When the current card was opened. The posted duration is the time actually
  /// spent on the card, measured silently.
  DateTime _cardStartedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Idle while nothing is being said; the screen never leaves a microphone open.
  _VoicePhase _voicePhase = _VoicePhase.idle;

  /// Words the recogniser returned, shown as "我听到：…" so the senior can see
  /// what was understood (even when it did not fit an option).
  String _heardText = '';

  /// True when words arrived but fitted no option: the amber "没听清" panel.
  bool _voiceMissed = false;

  /// True when nothing usable arrived at all: the amber "没听到声音" panel.
  bool _heardNothing = false;

  /// Bumped whenever an in-flight voice answer must be ignored: Stop, a tap, a
  /// new card, or leaving the screen. A late transcript can then never grade a
  /// card it was not recorded for.
  int _voiceGeneration = 0;

  @override
  void initState() {
    super.initState();
    _rotation = ActivityRotationController(feed: widget.state.activityFeed);
    _cardStartedAt = _now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    // Leaving the screen must never leave the microphone recording.
    _abandonVoice();
    super.dispose();
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

  /// Opens a fresh card: clears the answer lock, restarts the silent duration,
  /// forgets any previous voice attempt and reads the card aloud once.
  void _openCard() {
    final item = _rotation.current;
    if (!mounted) return;
    setState(() {
      _chosenIndex = null;
      _finished = false;
      _cardStartedAt = _now();
      _resetVoice();
    });
    if (item != null) _speak(_questionSpeech(item));
  }

  /// The card's own words, in the order they are heard.
  ///
  /// A story card reads the story and then asks its question; every other card
  /// reads its title and then the question. It is deliberately **one** utterance:
  /// the Windows voice stops whatever it is saying when the next sentence starts,
  /// so two calls would cut each other off.
  String _questionSpeech(ActivityItem item) {
    final story = item.story?.trim() ?? '';
    final first = story.isNotEmpty ? story : item.title.trim();
    final parts = <String>[first, item.prompt.trim()];
    return parts.where((part) => part.isNotEmpty).join('\n');
  }

  /// Fire-and-forget: the sentence is already on screen, so a missing voice must
  /// never surface as an error here.
  void _speak(String text) {
    if (text.trim().isEmpty) return;
    unawaited(widget.state.speakFeedback(text));
  }

  /// Clears the voice UI for a fresh card. Must be called inside `setState`.
  void _resetVoice() {
    _voicePhase = _VoicePhase.idle;
    _heardText = '';
    _voiceMissed = false;
    _heardNothing = false;
  }

  /// Drops any voice answer in flight and closes the microphone.
  ///
  /// Called when a tap wins, when the card changes, when the activity ends and
  /// when the screen is left. Safe to call from [dispose] (no `setState` here).
  void _abandonVoice() {
    _voiceGeneration++;
    if (_voicePhase != _VoicePhase.idle) {
      unawaited(widget.state.cancelRecording());
    }
    _voicePhase = _VoicePhase.idle;
  }

  /// Builds the one sentence pair for the pick at [index]. The words come from
  /// the shared rule in `state/activity_grading.dart`, which the in-chat card
  /// uses too: the Play screen and the conversation must never grade differently.
  ActivityFeedback _feedbackFor(L l, ActivityItem item, int index) =>
      gradeActivity(l, item, index);

  void _answer(int index) {
    final item = _rotation.current;
    if (item == null || _answered) return;
    final feedback = _feedbackFor(widget.state.l, item, index);
    // A tap wins over a voice answer that is still in flight: drop the clip
    // instead of letting a late transcript grade the same card twice.
    _abandonVoice();
    setState(() {
      _chosenIndex = index;
      _voiceMissed = false;
      _heardNothing = false;
    });
    _speak(feedback.spoken);
  }

  /// "说出答案": one short recording, one transcript, exactly one grade.
  ///
  /// The transcript goes through [matchOption] and a match is answered by the
  /// very same [_answer] a tap uses — same grading, same lock, same spoken
  /// feedback. No match is never a guess: the card stays open, the senior sees
  /// and hears "没听清", and can retry or simply tap.
  Future<void> _voiceAnswer() async {
    final state = widget.state;
    final l = state.l;
    final item = _rotation.current;
    if (item == null || item.options.isEmpty || _answered) return;
    if (_voicePhase != _VoicePhase.idle || !state.asrConfigured) return;
    final generation = ++_voiceGeneration;
    setState(() {
      _voicePhase = _VoicePhase.listening;
      _heardText = '';
      _voiceMissed = false;
      _heardNothing = false;
    });
    final transcript = await state.listenForAnswer(
      onRecordingComplete: () {
        if (!mounted || generation != _voiceGeneration) return;
        setState(() => _voicePhase = _VoicePhase.working);
      },
    );
    if (!mounted || generation != _voiceGeneration || _answered) return;
    final words = transcript?.trim() ?? '';
    if (words.isEmpty) {
      setState(() {
        _voicePhase = _VoicePhase.idle;
        _voiceMissed = false;
        _heardNothing = true;
      });
      _speak(l.activityVoiceNothingSpoken);
      return;
    }
    setState(() => _heardText = words);
    final index = matchOption(words, item.options);
    if (index == null) {
      setState(() {
        _voicePhase = _VoicePhase.idle;
        _voiceMissed = true;
      });
      _speak(l.activityVoiceMissedSpoken);
      return;
    }
    setState(() => _voicePhase = _VoicePhase.idle);
    _answer(index);
  }

  Future<void> _finish({required bool completed}) async {
    final item = _rotation.current;
    if (!mounted) return;
    _abandonVoice();
    setState(() {
      _finished = true;
      _resetVoice();
    });
    if (item == null) return;
    final measured = _now().difference(_cardStartedAt).inSeconds;
    final seconds = measured < 0
        ? 0
        : (measured > _maxReportedSeconds ? _maxReportedSeconds : measured);
    // Posted silently: the senior never sees a clock, the caregiver still gets
    // an honest "how long did this take". A graded card also reports whether it
    // was right, which is what earns the flower; an unanswered card reports
    // nothing and earns nothing.
    final chosen = _chosenIndex;
    await widget.state.finishActivity(
      activityId: item.id,
      completed: completed,
      durationSeconds: seconds,
      correct: chosen == null ? null : item.isCorrect(chosen),
    );
  }

  void _next() {
    _abandonVoice();
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
        // A transcript that arrives after Stop must never grade the card.
        _voiceGeneration++;
        await state.stopAll(); // also closes the microphone
        if (!mounted) return;
        setState(() {
          _finished = true;
          _resetVoice();
        });
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
            if (state.flowers > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l.flowersTotal(state.flowers),
                key: const Key('activity-flowers'),
                style: const TextStyle(
                  fontSize: 24,
                  color: AnchorTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
            const SizedBox(height: 8),
            _repeatQuestionButton(l, item),
            const SizedBox(height: 12),
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

  /// "再念一遍": reads the current card's words again.
  ///
  /// Disabled while the microphone is open, so the two voices never overlap and
  /// the recording never contains Anchor's own question.
  Widget _repeatQuestionButton(L l, ActivityItem item) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('activity-repeat-question'),
        onPressed: _voicePhase == _VoicePhase.idle
            ? () => _speak(_questionSpeech(item))
            : null,
        icon: const Icon(Icons.volume_up, size: 28),
        label: Text(
          l.activityRepeatQuestion,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  /// The big voice-answer control and its honest states.
  ///
  /// Idle → "说出答案"; listening → "我在听…" (not tappable); working →
  /// "稍等一下…" while the clip is transcribed. Without a recogniser it is
  /// disabled *and* says why, instead of doing nothing when pressed.
  Widget _voiceArea(L l) {
    final ready = widget.state.asrConfigured;
    final phase = _voicePhase;
    final busy = phase != _VoicePhase.idle;
    // Green whenever it can be pressed; muted when it cannot (answered, or no
    // recogniser). The colours are explicit because the theme's disabled style
    // would wash the text out.
    final fill = ready && !_answered ? AnchorTheme.primary : AnchorTheme.muted;
    final label = switch (phase) {
      _VoicePhase.idle => l.activityVoiceAnswer,
      _VoicePhase.listening => l.activityVoiceListening,
      _VoicePhase.working => l.activityVoiceWorking,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _voiceButtonHeight),
          child: FilledButton.icon(
            key: const Key('activity-voice'),
            onPressed: (!ready || busy || _answered) ? null : _voiceAnswer,
            style: FilledButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: AnchorTheme.surface,
              disabledBackgroundColor: fill,
              disabledForegroundColor: AnchorTheme.surface,
              textStyle: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AnchorTheme.surface,
                    ),
                  )
                : const Icon(Icons.mic, size: 34),
            label: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (!ready) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            l.activityVoiceNotReady,
            key: const Key('activity-voice-not-ready'),
            style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
          ),
        ],
        if (_heardText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l.activityVoiceHeard(_heardText),
            key: const Key('activity-heard'),
            style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
          ),
        ],
        if (_voiceMissed)
          _voiceNotice(
            key: const Key('activity-voice-missed'),
            title: l.activityVoiceMissed,
            hint: l.activityVoiceMissedHint,
          ),
        if (_heardNothing)
          _voiceNotice(
            key: const Key('activity-voice-nothing'),
            title: l.activityVoiceNothing,
            hint: l.activityVoiceNothingHint,
          ),
      ],
    );
  }

  /// The amber "not heard / not understood" panel. Warm, never red: nothing has
  /// gone wrong, and the very next tap still counts.
  Widget _voiceNotice({
    required Key key,
    required String title,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: key,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AnchorTheme.wrongFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AnchorTheme.accent, width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.hearing_disabled,
                size: 32,
                color: AnchorTheme.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AnchorTheme.ink,
                          height: 1.3,
                        ),
                      ),
                      TextSpan(
                        text: '\n$hint',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: AnchorTheme.ink,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playArea(L l, ActivityItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (item.options.isNotEmpty) ...<Widget>[
          _voiceArea(l),
          const SizedBox(height: 16),
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
        ? AnchorTheme.correctFill
        : (rejected ? AnchorTheme.wrongFill : AnchorTheme.surface);
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
      ActivityTone.correct => (
        AnchorTheme.correctFill,
        AnchorTheme.primary,
        Icons.check_circle,
        AnchorTheme.primary,
      ),
      ActivityTone.wrong => (
        AnchorTheme.wrongFill,
        AnchorTheme.accent,
        Icons.lightbulb_outline,
        AnchorTheme.accent,
      ),
      ActivityTone.open => (
        AnchorTheme.openFill,
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
            color: AnchorTheme.correctFill,
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
