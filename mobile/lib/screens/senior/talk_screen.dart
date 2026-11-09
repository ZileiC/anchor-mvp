import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/conversation.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/status_banner.dart';
import 'settings_screen.dart';

/// The conversation screen: microphone state, captions, Repeat, Stop and an
/// always-available text fallback (SPEC §9, S2/S6/S7).
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
  bool _starting = false;
  bool _stoppedLocally = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSession();
      _refreshProviders();
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
  Future<void> _openSettings() async {
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
          l.asrNotConnectedBody,
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
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: FilledButton(
              key: const Key('talk-asr-go-settings'),
              onPressed: () => Navigator.of(dialogContext).pop('settings'),
              child: Text(l.goToSettings, style: const TextStyle(fontSize: 24)),
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

  Future<void> _stop() async {
    await widget.state.stopAll();
    if (!mounted) return;
    setState(() => _stoppedLocally = true);
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _micIndicator(l, state),
          const SizedBox(height: 12),
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
              body: l.talkConsentNeeded,
              extraAction: OutlinedButton.icon(
                key: const Key('talk-open-settings'),
                onPressed: _openSettings,
                icon: const Icon(Icons.settings, size: 28),
                label: Text(l.goToSettings),
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
            const SizedBox(height: 8),
          ],
          _captions(l, state),
          const SizedBox(height: 12),
          if (_stoppedLocally) ...<Widget>[
            _stoppedPanel(context, l, state),
            const SizedBox(height: 12),
          ],
          _textInput(l, state),
          const SizedBox(height: 12),
          _controls(l, state),
        ],
      ),
    );
  }

  Widget _micIndicator(L l, AppState state) {
    final asrReady = state.asrConfigured;
    final on = asrReady && state.hasActiveSession && !state.recording;
    final recording = state.recording;
    final color = recording
        ? AnchorTheme.danger
        : (on ? AnchorTheme.primary : AnchorTheme.muted);
    final label = recording
        ? l.listening
        : (!asrReady ? l.micNotConnected : (on ? l.micOn : l.micOff));
    return Semantics(
      label: label,
      liveRegion: true,
      child: Container(
        key: const Key('mic-indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AnchorTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              recording
                  ? Icons.mic
                  : (asrReady ? Icons.mic_none : Icons.mic_off),
              size: 34,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            if (state.sendingTurn)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
          ],
        ),
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

  Widget _captions(L l, AppState state) {
    if (state.captions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AnchorTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AnchorTheme.border, width: 1.5),
        ),
        child: Text(l.talkEmpty, style: AnchorTheme.reading),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < state.captions.length; index++)
          _CaptionTile(
            key: ValueKey<String>('caption-$index'),
            caption: state.captions[index],
            l: l,
          ),
      ],
    );
  }

  Widget _stoppedPanel(BuildContext context, L l, AppState state) {
    return Container(
      key: const Key('talk-stopped-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(14),
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

  Widget _textInput(L l, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l.typeHere, style: const TextStyle(fontSize: 22)),
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

  Widget _controls(L l, AppState state) {
    final asrReady = state.asrConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Always tappable: a microphone that failed once (busy headset, a call
        // holding it) must be retryable without restarting the app.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: FilledButton.icon(
            key: const Key('talk-mic'),
            onPressed: _toggleMic,
            // Greyed but still tappable: tapping explains *why* instead of
            // silently doing nothing. Without a recogniser nothing is recorded.
            style: asrReady
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: AnchorTheme.muted,
                    foregroundColor: AnchorTheme.surface,
                  ),
            icon: Icon(
              state.recording
                  ? Icons.stop
                  : (asrReady ? Icons.mic : Icons.mic_off),
              size: 32,
            ),
            label: Text(
              state.recording
                  ? l.doneSpeaking
                  : (asrReady ? l.startTalking : l.micNotConnected),
              style: const TextStyle(fontSize: 26),
            ),
          ),
        ),
        if (state.recording) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            l.listeningHint,
            style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('talk-repeat'),
          onPressed: _repeat,
          icon: const Icon(Icons.replay, size: 30),
          label: Text(l.repeat, style: const TextStyle(fontSize: 26)),
        ),
      ],
    );
  }
}

class _CaptionTile extends StatelessWidget {
  const _CaptionTile({super.key, required this.caption, required this.l});

  final Caption caption;
  final L l;

  @override
  Widget build(BuildContext context) {
    final isSenior = caption.isSenior;
    final accent = isSenior ? AnchorTheme.muted : AnchorTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnchorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isSenior ? l.you : l.anchor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(caption.text, style: AnchorTheme.reading),
        ],
      ),
    );
  }
}
