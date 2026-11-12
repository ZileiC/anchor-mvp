import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/conversation.dart';
import '../../services/speaker.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/inline_activity_card.dart';
import '../../widgets/status_banner.dart';
import 'choices_screen.dart';
import 'settings_screen.dart';

/// The conversation screen: microphone state, captions, Repeat, Stop and an
/// always-available text fallback (SPEC §9, S2/S6/S7).
///
/// Layout (redesign 2026-11-10, docs/design/senior-ui.md): the conversation is
/// a quiet stream of turns — no avatar, no bubble, no card per turn — and the
/// one action that must never be hunted for, the microphone, sits in a fixed
/// dock under the stream with Stop directly beneath it. So the senior never has
/// to scroll to talk: only the conversation and the typing fallback scroll.
///
/// A late reply can never appear after Stop: [AppState.stopAll] bumps the request
/// nonce first, so the pending response is discarded instead of rendered.
class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key, required this.state});

  final AppState state;

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// The only scrolling on this screen: the dock below it never moves.
  final ScrollController _streamController = ScrollController();

  bool _starting = false;
  bool _stoppedLocally = false;

  /// Caption count of the previous frame. A repaint caused by anything else
  /// (speech flags, provider refreshes, a refreshed flower count) must not yank
  /// the stream to the bottom while the senior is re-reading an older turn.
  int _captionCount = 0;

  @override
  void initState() {
    super.initState();
    _captionCount = widget.state.captions.length;
    // The inline activity card lives in [AppState] (it is answered outside this
    // widget and its offer arrives with a turn), so the stream has to repaint
    // when that state changes — including a tap collapsing the card in place.
    widget.state.addListener(_onAppStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSession();
      _refreshProviders();
      _anchorStream();
    });
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final count = widget.state.captions.length;
    final grew = count != _captionCount;
    _captionCount = count;
    setState(() {});
    if (grew) _anchorStream();
  }

  /// Keeps the newest turn in view: a conversation grows from the bottom, so a
  /// new caption is only useful if it is the one being looked at. One jump
  /// after the frame that grew the list — never an animated chase.
  void _anchorStream() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_streamController.hasClients) return;
      final position = _streamController.position;
      if (!position.hasContentDimensions) return;
      final end = position.maxScrollExtent;
      if (_streamController.offset < end) _streamController.jumpTo(end);
    });
  }

  /// The provider status decides whether the mic may record: it is re-read on
  /// open and after the user comes back from Settings, so a just-saved key takes
  /// effect without restarting the app.
  Future<void> _refreshProviders() async {
    if (!mounted) return;
    await widget.state.loadProviders();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAppStateChanged);
    _streamController.dispose();
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _ensureSession() async {
    final state = widget.state;
    if (!mounted || _starting) return;
    if (state.hasActiveSession || state.offline) return;
    setState(() => _starting = true);
    final ok = await state.startConversation();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _stoppedLocally = !ok && state.lastError?.code == 'consent_required';
    });
  }

  Future<void> _sendText() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    setState(() => _stoppedLocally = false);
    await widget.state.sendText(text);
  }

  /// Opens Settings and re-reads the provider status on the way back.
  ///
  /// The Windows appliance has no settings screen (architecture change
  /// 2026-11-10), so this never pushes one there: a stale button explains
  /// instead of opening a route that does not exist on this build.
  /// Opens 我的选择 and makes sure a conversation can start once the older adult
  /// has changed a permission (2026-11-12).
  Future<void> _openChoices() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChoicesScreen(state: widget.state),
      ),
    );
    if (mounted) await _ensureSession();
  }

  Future<void> _openSettings() async {
    if (!widget.state.policy.setupApp) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(widget.state.l.setupNotOnComputer)),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(state: widget.state),
      ),
    );
    await _refreshProviders();
  }

  /// Honest mic gate: no recogniser means no recording and no transcript.
  Future<void> _showAsrUnavailableDialog() async {
    final l = widget.state.l;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('talk-asr-dialog'),
        backgroundColor: AnchorTheme.surface,
        title: Text(
          l.asrNotConnectedTitle,
          style: const TextStyle(fontSize: 28),
        ),
        content: Text(
          // The appliance has no settings screen, so it names the phone instead.
          widget.state.policy.setupApp
              ? l.asrNotConnectedBody
              : l.asrNotConnectedBodyOnComputer,
          style: const TextStyle(fontSize: 24, color: AnchorTheme.ink),
        ),
        actions: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: TextButton(
              key: const Key('talk-asr-type-instead'),
              onPressed: () => Navigator.of(dialogContext).pop('type'),
              child: Text(l.typeInstead, style: const TextStyle(fontSize: 24)),
            ),
          ),
          // Appliance only: there is no settings screen to send the senior to, so
          // the honest typing fallback is the only action offered.
          if (widget.state.policy.setupApp)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AnchorTheme.minTouchTarget,
              ),
              child: FilledButton(
                key: const Key('talk-asr-go-settings'),
                onPressed: () => Navigator.of(dialogContext).pop('settings'),
                child: Text(
                  l.goToSettings,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'type') {
      _focusTyping();
    } else if (action == 'settings') {
      await _openSettings();
    }
  }

  Future<void> _retryTurn() async {
    await widget.state.retryLastTurn();
    if (mounted) setState(() {});
  }

  /// One tap on an in-chat option. [AppState.answerInlineActivity] locks the
  /// card, records the result and posts the choice as the next chat turn, so
  /// nothing here decides anything: the screen only forwards the tap.
  Future<void> _answerInline(int index) async {
    await widget.state.answerInlineActivity(index);
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    // Show the stopped state first: the button must react to the press even if
    // the server never answers. Stop used to look broken after the first tap
    // because the UI waited for the whole stop round trip.
    if (mounted && !_stoppedLocally) {
      setState(() => _stoppedLocally = true);
    }
    await widget.state.stopAll();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(widget.state.l.stoppedTitle)));
  }

  Future<void> _toggleMic() async {
    final state = widget.state;
    if (!state.recording && !state.asrConfigured) {
      await _showAsrUnavailableDialog();
      return;
    }
    if (state.recording) {
      await state.stopRecordingAndSend();
    } else {
      await state.startRecording();
    }
    if (mounted) setState(() {});
  }

  Future<void> _repeat() async {
    final state = widget.state;
    if (state.repeatableText == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(state.l.repeatNothing)));
      return;
    }
    await state.repeatLastReply();
  }

  void _focusTyping() {
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = state.l;
    final consentError = state.lastError?.code == 'consent_required';

    return AnchorScaffold(
      state: state,
      title: l.talkTitle,
      onStop: _stop,
      // After Stop there is nothing left to stop: the bar disappears and only
      // the "已经停下来了" panel (with 继续聊天) remains.
      showStop: !_stoppedLocally,
      // The conversation scrolls; the microphone and Stop never do.
      scrollable: false,
      aboveStop: _stoppedLocally ? null : _dock(l, state),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _statusLine(l, state),
          const SizedBox(height: 8),
          Expanded(child: _stream(l, state, consentError)),
        ],
      ),
    );
  }

  /// The conversation and everything that belongs to it.
  ///
  /// It owns the only scroll view on the screen, and on a wide window the
  /// reading column stays a comfortable 860 px, centred, while the dock below
  /// keeps the full width.
  Widget _stream(L l, AppState state, bool consentError) {
    return SingleChildScrollView(
      key: const Key('talk-stream'),
      controller: _streamController,
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_starting) ...<Widget>[
                  const LinearProgressIndicator(minHeight: 8),
                  const SizedBox(height: 8),
                  Text(l.talkStarting, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 12),
                ],
                if (consentError)
                  StatusBanner(
                    l: l,
                    tone: BannerTone.problem,
                    title: l.needConsentCloud,
                    // The older adult can turn cloud speech on themselves, on the
                    // appliance, in 我的选择 (2026-11-12). Before this banner sent
                    // them to the family's phone for a permission that is theirs.
                    body: state.policy.setupApp
                        ? l.talkConsentNeeded
                        : l.t(
                            '您可以在「我的选择」里允许云端语音处理。',
                            'You can allow cloud voice processing in My choices.',
                          ),
                    extraAction: OutlinedButton.icon(
                      key: const Key('talk-open-settings'),
                      onPressed: state.policy.setupApp
                          ? _openSettings
                          : _openChoices,
                      icon: Icon(
                        state.policy.setupApp
                            ? Icons.settings
                            : Icons.verified_user_outlined,
                        size: 28,
                      ),
                      label: Text(
                        state.policy.setupApp
                            ? l.goToSettings
                            : l.t('我的选择', 'My choices'),
                      ),
                    ),
                  )
                else if (state.offline)
                  StatusBanner(
                    l: l,
                    title: l.offlineTitle,
                    body: l.offlineBody,
                    onRetry: _ensureSession,
                    extraAction: OutlinedButton.icon(
                      key: const Key('talk-type-instead'),
                      onPressed: _focusTyping,
                      icon: const Icon(Icons.keyboard, size: 28),
                      label: Text(l.typeInstead),
                    ),
                  )
                else if (state.lastError?.code == 'provider_unavailable')
                  StatusBanner(
                    l: l,
                    tone: BannerTone.problem,
                    title: l.providerUnavailableTitle,
                    body: l.providerUnavailableBody,
                    onRetry: _retryTurn,
                    extraAction: OutlinedButton.icon(
                      key: const Key('talk-provider-type-instead'),
                      onPressed: _focusTyping,
                      icon: const Icon(Icons.keyboard, size: 28),
                      label: Text(l.typeInstead),
                    ),
                  )
                else if (state.lastError != null)
                  StatusBanner(
                    l: l,
                    tone: BannerTone.problem,
                    title: state.lastErrorText ?? l.unknownError,
                    onRetry: _ensureSession,
                    extraAction: OutlinedButton.icon(
                      onPressed: _focusTyping,
                      icon: const Icon(Icons.keyboard, size: 28),
                      label: Text(l.typeInstead),
                    ),
                  ),
                if (state.micUnavailable)
                  StatusBanner(
                    l: l,
                    title: l.micUnavailable,
                    tone: BannerTone.notice,
                  ),
                if (state.showOfflineLlmBadge) ...<Widget>[
                  _offlineLlmBadge(l),
                  const SizedBox(height: 12),
                ],
                _turns(l, state),
                // The activity is part of the chat, not a separate screen: it
                // follows the assistant's bridge sentence and collapses in
                // place after the answer (product decision 2026-11-10).
                if (state.inlineActivity != null)
                  InlineActivityCard(
                    l: l,
                    activity: state.inlineActivity!,
                    onChoose: _answerInline,
                    flowers: state.flowers,
                    awarded: state.lastAnswerAwarded,
                  ),
                if (_stoppedLocally) ...<Widget>[
                  _stoppedPanel(context, l, state),
                  const SizedBox(height: 16),
                ],
                _repeatButton(l),
                const SizedBox(height: 16),
                _textInput(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The turns, as conversation: a small speaker label and one sentence, 16 px
  /// apart, on the paper itself. No avatar, bubble or card, so the eye goes
  /// straight to what Anchor said.
  Widget _turns(L l, AppState state) {
    if (state.captions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          l.talkEmpty,
          key: const Key('talk-empty'),
          style: const TextStyle(
            fontSize: 26,
            color: AnchorTheme.inkSoft,
            height: 1.35,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < state.captions.length; index++)
          _CaptionEntry(
            key: ValueKey<String>('caption-$index'),
            caption: state.captions[index],
            l: l,
          ),
      ],
    );
  }

  /// A compact line of truth next to the screen header: the microphone state
  /// and, while sending, that the turn is still being worked on. No box.
  Widget _statusLine(L l, AppState state) {
    final asrReady = state.asrConfigured;
    final on = asrReady && state.hasActiveSession && !state.recording;
    final recording = state.recording;
    final color = recording || on ? AnchorTheme.ink : AnchorTheme.inkSoft;
    // Say what is actually happening, 2026-11-12 (borrowed from the TA5 fork):
    // a bare on/off flag made the dock say '麦克风已开' while the machine was still
    // synthesising, and said nothing at all while the device voice was trying to
    // take over. Colour is never the only channel here — each state has words.
    final phase = state.speechPhase;
    final label = recording
        ? l.listening
        : phase == SpeechPhase.playing
        ? l.t('正在朗读，随时可以停止。', 'Speaking. You can stop at any time.')
        : phase == SpeechPhase.fallback
        ? l.t(
            '正在尝试系统语音。您也可以阅读文字。',
            'Trying the device voice. You can also read the reply.',
          )
        : phase == SpeechPhase.preparing
        ? l.t('正在准备语音，文字已显示。', 'Preparing the voice; you can read the reply.')
        : (!asrReady
              ? l.micNotConnected
              : on
              ? l.micOn
              : l.t('麦克风已关闭，点按后说话。', 'Microphone off. Tap to speak.'));
    return Semantics(
      label: label,
      liveRegion: true,
      child: Row(
        key: const Key('mic-indicator'),
        children: <Widget>[
          Icon(
            recording ? Icons.mic : (asrReady ? Icons.mic_none : Icons.mic_off),
            size: 26,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: recording ? FontWeight.w700 : FontWeight.w600,
                color: color,
                height: 1.25,
              ),
            ),
          ),
          if (state.sendingTurn)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
        ],
      ),
    );
  }

  /// The fixed footer. The microphone is the one action that must always be
  /// reachable, so it lives here with Stop directly underneath; the listening
  /// hint grows the dock upward and never comes between the two.
  Widget _dock(L l, AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _listeningHint(l, state.recording),
          _MicButton(
            key: const ValueKey<String>('talk-mic-dock'),
            l: l,
            asrReady: state.asrConfigured,
            recording: state.recording,
            onPressed: _toggleMic,
          ),
        ],
      ),
    );
  }

  Widget _listeningHint(L l, bool recording) {
    if (!recording) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        l.listeningHint,
        key: const Key('talk-listening-hint'),
        style: const TextStyle(
          fontSize: 22,
          color: AnchorTheme.inkSoft,
          height: 1.35,
        ),
      ),
    );
  }

  /// "Say that again" belongs to the conversation, not to the dock: it is a
  /// secondary action, and it may scroll away with the sentence it replays.
  Widget _repeatButton(L l) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('talk-repeat'),
        onPressed: _repeat,
        icon: const Icon(Icons.replay, size: 28),
        label: Text(l.repeat, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  Widget _offlineLlmBadge(L l) {
    return Container(
      key: const Key('talk-offline-llm-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8A5A00), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 20, color: Color(0xFF8A5A00)),
          const SizedBox(width: 6),
          Text(
            l.llmOfflineBadge,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AnchorTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stoppedPanel(BuildContext context, L l, AppState state) {
    return Container(
      key: const Key('talk-stopped-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnchorTheme.correctFill,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(color: AnchorTheme.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.check_circle,
                size: 32,
                color: AnchorTheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.stoppedTitle,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('talk-resume'),
            onPressed: _ensureSession,
            icon: const Icon(Icons.play_arrow, size: 32),
            label: Text(l.resumeTalk),
          ),
        ],
      ),
    );
  }

  /// The typing fallback. It sits at the end of the stream, above the dock: the
  /// microphone must never scroll away, this may.
  Widget _textInput(L l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.typeHere,
          style: const TextStyle(
            fontSize: 22,
            color: AnchorTheme.inkSoft,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('talk-text-field'),
          controller: _controller,
          focusNode: _inputFocus,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(fontSize: 26, color: AnchorTheme.ink),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendText(),
          decoration: InputDecoration(
            hintText: l.typeHere,
            suffixIcon: IconButton(
              key: const Key('talk-send'),
              icon: const Icon(Icons.send, size: 30),
              tooltip: l.send,
              onPressed: _sendText,
            ),
          ),
        ),
      ],
    );
  }
}

/// One turn in the conversation stream: `你` / `Anchor` in a small label, then
/// the sentence itself. It fades in and rises 8 px once, 180 ms, unless the
/// system asks for reduced motion.
class _CaptionEntry extends StatelessWidget {
  const _CaptionEntry({super.key, required this.caption, required this.l});

  final Caption caption;
  final L l;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption.isSenior ? l.you : l.anchor,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AnchorTheme.inkSoft,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption.text,
          style: const TextStyle(
            fontSize: 26,
            color: AnchorTheme.ink,
            height: 1.35,
          ),
        ),
      ],
    );
    final entry = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: body,
    );
    if (reduceMotion) return entry;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: entry,
    );
  }
}

/// The one action that is always on screen: the microphone.
///
/// A wide jade button with a text label for every state (never colour alone),
/// and while it is listening a slow teal ring breathes around it (2.4 s per
/// breath, static when the system asks for reduced motion). The ring is painted
/// outside the button, so starting to listen never moves or resizes it.
class _MicButton extends StatefulWidget {
  const _MicButton({
    super.key,
    required this.l,
    required this.asrReady,
    required this.recording,
    required this.onPressed,
  });

  final L l;
  final bool asrReady;
  final bool recording;
  final VoidCallback onPressed;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  /// 1.2 s per direction × 2 = the 2.4 s breath from the design note.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recording != widget.recording) _sync();
  }

  void _sync() {
    if (widget.recording && !_reduceMotion) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0.5;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final asrReady = widget.asrReady;
    final recording = widget.recording;
    final label = recording
        ? l.doneSpeaking
        : (asrReady ? l.startTalking : l.micNotConnected);
    final button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: FilledButton.icon(
        key: const Key('talk-mic'),
        onPressed: widget.onPressed,
        // Greyed but still tappable: tapping explains *why* instead of silently
        // doing nothing. Without a recogniser nothing is recorded.
        style: FilledButton.styleFrom(
          // One jade for the one action; the listening state is told by the
          // ring, the icon and the label, never by colour alone.
          backgroundColor: asrReady ? AnchorTheme.jade : AnchorTheme.muted,
          foregroundColor: AnchorTheme.onPrimary,
          minimumSize: const Size(AnchorTheme.minTouchTarget, 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
          ),
        ),
        icon: Icon(
          recording ? Icons.stop : (asrReady ? Icons.mic : Icons.mic_off),
          size: 34,
        ),
        label: Text(label),
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        button,
        if (recording)
          Positioned(
            key: const Key('talk-mic-ring'),
            left: -7,
            right: -7,
            top: -7,
            bottom: -7,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, _) {
                  final alpha = _reduceMotion
                      ? 0.55
                      : 0.22 + 0.58 * _breath.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AnchorTheme.buttonRadius + 7,
                      ),
                      border: Border.all(
                        color: AnchorTheme.teal.withValues(alpha: alpha),
                        width: 3,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
