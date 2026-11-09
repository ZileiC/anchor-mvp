import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';

/// Settings → “AI 接入（模型/语音）”.
///
/// Two honest sections: the chat model (DeepSeek preset, or any OpenAI-compatible
/// endpoint) and speech recognition (the packaged backend's on-device recogniser
/// by default). Every status and probe result comes from the backend — this
/// screen never guesses, and it shows the masked `key_hint`, never the key.
class AiProvidersScreen extends StatefulWidget {
  const AiProvidersScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AiProvidersScreen> createState() => _AiProvidersScreenState();
}

class _AiProvidersScreenState extends State<AiProvidersScreen> {
  final TextEditingController _llmBase = TextEditingController();
  final TextEditingController _llmModel = TextEditingController();
  final TextEditingController _llmKey = TextEditingController();
  final TextEditingController _asrBase = TextEditingController();
  final TextEditingController _asrModel = TextEditingController();
  final TextEditingController _asrKey = TextEditingController();

  bool _llmBusy = false;
  bool _llmTesting = false;
  bool _asrBusy = false;
  bool _asrTesting = false;
  String? _llmTestMessage;
  bool _llmTestFailed = false;
  String? _asrTestMessage;
  bool _asrTestFailed = false;
  bool _loaded = false;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _llmBase.dispose();
    _llmModel.dispose();
    _llmKey.dispose();
    _asrBase.dispose();
    _asrModel.dispose();
    _asrKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_state.isSenior) return;
    await _state.loadProviders();
    if (!mounted) return;
    setState(() {
      _applyStatus(_state.providers, overwrite: !_loaded);
      _loaded = true;
    });
  }

  /// Note: the API key is never restored into a field — only the masked hint.
  void _applyStatus(ProviderStatus? status, {required bool overwrite}) {
    if (status == null || !overwrite) return;
    _llmBase.text = status.llm.baseUrl ?? '';
    _llmModel.text = status.llm.model;
    // Show the shipped defaults instead of an empty box: the backend already
    // treats "key with no endpoint" as this endpoint, and an empty field is what
    // made a correctly saved key look like it was never applied.
    final asrBase = status.asr.baseUrl ?? '';
    _asrBase.text = asrBase.isEmpty ? 'https://api.siliconflow.cn/v1' : asrBase;
    final asrModel = status.asr.model;
    _asrModel.text =
        asrModel.isEmpty ? 'FunAudioLLM/SenseVoiceSmall' : asrModel;
  }

  String? _trim(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  ProviderUpdate _llmUpdate() => ProviderUpdate(
    llm: ProviderSectionUpdate(
      baseUrl: _trim(_llmBase.text),
      model: _trim(_llmModel.text),
      apiKey: _trim(_llmKey.text),
    ),
  );

  ProviderUpdate _asrUpdate() => ProviderUpdate(
    asr: ProviderSectionUpdate(
      baseUrl: _trim(_asrBase.text),
      model: _trim(_asrModel.text),
      apiKey: _trim(_asrKey.text),
    ),
  );

  void _applyDeepSeekPreset() {
    setState(() {
      _llmBase.text = 'https://api.deepseek.com';
      // deepseek-flash is the fast tier this account exposes; the demo's whole
      // conversation budget is latency, so that is the default, not deepseek-chat.
      _llmModel.text = 'deepseek-flash';
      _llmTestMessage = null;
      _llmTestFailed = false;
    });
  }

  void _applyAsrPreset() {
    setState(() {
      _asrBase.text = 'https://api.siliconflow.cn/v1';
      _asrModel.text = 'FunAudioLLM/SenseVoiceSmall';
      _asrTestMessage = null;
      _asrTestFailed = false;
    });
  }

  Future<void> _saveLlm() async {
    final l = _state.l;
    final update = _llmUpdate();
    if ((update.llm?.toJson().isEmpty ?? true)) {
      _snack(l.aiNothingToSave);
      return;
    }
    setState(() => _llmBusy = true);
    final status = await _state.saveProviders(update);
    if (!mounted) return;
    setState(() {
      _llmBusy = false;
      if (status == null) {
        _llmTestMessage = _state.lastErrorText ?? l.unknownError;
        _llmTestFailed = true;
      } else {
        _llmKey.clear();
        _applyStatus(status, overwrite: true);
        _llmTestMessage = null;
      }
    });
    _snack(
      status == null
          ? (_state.lastErrorText ?? l.aiTestFailed(l.unknownError))
          : l.aiSavedAgain,
    );
  }

  Future<void> _testLlm() async {
    final l = _state.l;
    setState(() {
      _llmTesting = true;
      _llmTestMessage = null;
      _llmTestFailed = false;
    });
    final result = await _state.testProviders();
    if (!mounted) return;
    setState(() {
      _llmTesting = false;
      final probe = result?.llm;
      if (probe == null) {
        _llmTestMessage = _state.lastErrorText ?? l.unknownError;
        _llmTestFailed = true;
      } else if (probe.ok) {
        _llmTestMessage = l.aiTestOkDetail(
          probe.latencyMs ?? 0,
          probe.replySample ?? '',
        );
        _llmTestFailed = false;
      } else if ((probe.error ?? '').contains('not_configured')) {
        _llmTestMessage = l.aiTestNotConfigured;
        _llmTestFailed = true;
      } else {
        _llmTestMessage = l.aiTestFailed(probe.error ?? l.aiStatusUnknown);
        _llmTestFailed = true;
      }
    });
  }

  Future<void> _clearLlm() async {
    final l = _state.l;
    setState(() => _llmBusy = true);
    final status = await _state.saveProviders(
      const ProviderUpdate(llm: ProviderSectionUpdate(clear: true)),
    );
    if (!mounted) return;
    setState(() {
      _llmBusy = false;
      if (status == null) {
        _llmTestMessage = _state.lastErrorText ?? l.unknownError;
        _llmTestFailed = true;
      } else {
        _llmBase.clear();
        _llmModel.clear();
        _llmKey.clear();
        _llmTestMessage = null;
        _applyStatus(status, overwrite: true);
      }
    });
    if (status != null) _snack(l.aiSavedAgain);
  }

  Future<void> _saveAsr() async {
    final l = _state.l;
    final update = _asrUpdate();
    if ((update.asr?.toJson().isEmpty ?? true)) {
      _snack(l.aiNothingToSave);
      return;
    }
    setState(() => _asrBusy = true);
    final status = await _state.saveProviders(update);
    if (!mounted) return;
    setState(() {
      _asrBusy = false;
      if (status == null) {
        _asrTestMessage = _state.lastErrorText ?? l.unknownError;
        _asrTestFailed = true;
      } else {
        _asrKey.clear();
        _applyStatus(status, overwrite: true);
        _asrTestMessage = null;
      }
    });
    _snack(
      status == null
          ? (_state.lastErrorText ?? l.aiTestFailed(l.unknownError))
          : l.aiSavedAgain,
    );
  }

  /// Records a short real clip and asks the backend to transcribe it. The result
  /// shown is the backend's text or its honest error — never a canned sentence.
  Future<void> _testAsr() async {
    final l = _state.l;
    setState(() {
      _asrTesting = true;
      _asrTestMessage = l.aiAsrTesting;
      _asrTestFailed = false;
    });
    final audio = await _state.captureProbeClip();
    if (!mounted) return;
    if (audio == null) {
      setState(() {
        _asrTesting = false;
        _asrTestMessage = _state.micUnavailable
            ? l.aiMicUnavailable
            : l.aiAsrNoSample;
        _asrTestFailed = true;
      });
      return;
    }
    final result = await _state.testProviders(audio: audio);
    if (!mounted) return;
    setState(() {
      _asrTesting = false;
      final probe = result?.asr;
      if (probe == null) {
        _asrTestMessage = _state.lastErrorText ?? l.unknownError;
        _asrTestFailed = true;
      } else if (probe.ok) {
        _asrTestMessage = l.aiAsrTranscript(probe.textSample ?? '');
        _asrTestFailed = false;
      } else {
        _asrTestMessage = _asrFailureText(l, probe);
        _asrTestFailed = true;
      }
    });
  }

  String _asrFailureText(L l, ProviderProbeResult probe) =>
      switch (probe.reason) {
        'no_sample' => l.aiAsrReasonNoSample,
        'invalid_sample' => l.aiAsrReasonInvalidSample,
        'empty_sample' => l.aiAsrNoSample,
        'not_configured' => l.aiAsrReasonNotConfigured,
        _ => l.aiAsrError(probe.error ?? l.aiStatusUnknown),
      };

  Future<void> _clearAsr() async {
    final l = _state.l;
    setState(() => _asrBusy = true);
    final status = await _state.saveProviders(
      const ProviderUpdate(asr: ProviderSectionUpdate(clear: true)),
    );
    if (!mounted) return;
    setState(() {
      _asrBusy = false;
      if (status == null) {
        _asrTestMessage = _state.lastErrorText ?? l.unknownError;
        _asrTestFailed = true;
      } else {
        _asrBase.clear();
        _asrModel.clear();
        _asrKey.clear();
        _asrTestMessage = null;
        _applyStatus(status, overwrite: true);
      }
    });
    if (status != null) _snack(l.aiSavedAgain);
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    final l = state.l;
    if (!state.isSenior) {
      return Scaffold(
        appBar: AppBar(title: Text(l.aiProvidersTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(l.aiProvidersSeniorOnly, style: AnchorTheme.reading),
          ),
        ),
      );
    }
    return AnchorScaffold(
      state: state,
      title: l.aiProvidersTitle,
      subtitle: l.aiProvidersEntryHint,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.providersLoading)
            const LinearProgressIndicator(minHeight: 8),
          _llmCard(l, state, state.providers?.llm),
          _asrCard(l, state, state.providers?.asr),
        ],
      ),
    );
  }

  // -- LLM -----------------------------------------------------------------
  Widget _llmCard(L l, AppState state, ProviderSectionStatus? section) {
    final configured = section?.configured ?? false;
    final statusLabel = section == null
        ? l.aiStatusUnknown
        : (configured ? l.aiStatusHttp : l.aiStatusOfflineLlm);
    return SectionCard(
      title: l.aiLlmSection,
      hint: l.aiLlmHint,
      icon: Icons.smart_toy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _statusLine(
            key: const Key('ai-llm-status'),
            l: l,
            label: statusLabel,
            good: configured,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('ai-llm-base-url'),
            controller: _llmBase,
            autocorrect: false,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              labelText: l.aiBaseUrl,
              hintText: 'https://api.deepseek.com',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('ai-llm-model'),
            controller: _llmModel,
            autocorrect: false,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              labelText: l.aiModel,
              hintText: 'deepseek-chat',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('ai-llm-key'),
            controller: _llmKey,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              labelText: l.aiApiKey,
              helperText: l.aiKeepKey,
            ),
          ),
          if (section?.keyHint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              l.aiSavedKeyHint(section!.keyHint!),
              key: const Key('ai-llm-key-hint'),
              style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('ai-llm-preset'),
            onPressed: _applyDeepSeekPreset,
            icon: const Icon(Icons.auto_fix_high, size: 28),
            label: Text(
              l.aiDeepSeekPreset,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.aiDeepSeekPresetHint,
            style: const TextStyle(fontSize: 20, color: AnchorTheme.inkSoft),
          ),
          if (_llmTesting) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(key: Key('ai-llm-progress')),
          ],
          if (_llmTestMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            _resultText(
              key: const Key('ai-llm-test-result'),
              text: _llmTestMessage!,
              failed: _llmTestFailed,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('ai-llm-save'),
                onPressed: _llmBusy ? null : _saveLlm,
                icon: const Icon(Icons.save_outlined, size: 26),
                label: Text(l.save, style: const TextStyle(fontSize: 24)),
              ),
              OutlinedButton.icon(
                key: const Key('ai-llm-test'),
                onPressed: _llmTesting ? null : _testLlm,
                icon: const Icon(Icons.wifi_tethering, size: 26),
                label: Text(l.aiTestLlm, style: const TextStyle(fontSize: 24)),
              ),
              TextButton(
                key: const Key('ai-llm-clear'),
                onPressed: _llmBusy ? null : _clearLlm,
                child: Text(
                  l.aiClearSection,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- ASR -----------------------------------------------------------------
  Widget _asrCard(L l, AppState state, ProviderSectionStatus? section) {
    final engineLabel = _asrEngineLabel(l, section);
    return SectionCard(
      title: l.aiAsrSection,
      hint: l.aiAsrHint,
      icon: Icons.mic_none_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _statusLine(
            key: const Key('ai-asr-status'),
            l: l,
            label: engineLabel,
            good: section?.configured ?? false,
          ),
          if (section != null && section.baseUrl != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              section.baseUrl!,
              style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const Key('ai-asr-base-url'),
            controller: _asrBase,
            autocorrect: false,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(labelText: l.aiBaseUrl),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('ai-asr-model'),
            controller: _asrModel,
            autocorrect: false,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(labelText: l.aiModel),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('ai-asr-key'),
            controller: _asrKey,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              labelText: l.aiApiKey,
              helperText: l.aiKeepKey,
            ),
          ),
          if (section?.keyHint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              l.aiSavedKeyHint(section!.keyHint!),
              key: const Key('ai-asr-key-hint'),
              style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
            ),
          ],
          if (_asrTesting) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(key: Key('ai-asr-progress')),
          ],
          if (_asrTestMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            _resultText(
              key: const Key('ai-asr-test-result'),
              text: _asrTestMessage!,
              failed: _asrTestFailed,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('ai-asr-save'),
                onPressed: _asrBusy ? null : _saveAsr,
                icon: const Icon(Icons.save_outlined, size: 26),
                label: Text(l.save, style: const TextStyle(fontSize: 24)),
              ),
              OutlinedButton.icon(
                key: const Key('ai-asr-test'),
                onPressed: _asrTesting ? null : _testAsr,
                icon: const Icon(Icons.graphic_eq, size: 26),
                label: Text(
                  l.aiAsrTestMic,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('ai-asr-preset'),
                onPressed: _applyAsrPreset,
                icon: const Icon(Icons.auto_fix_high, size: 26),
                label: Text(
                  l.aiAsrPreset,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              TextButton(
                key: const Key('ai-asr-clear'),
                onPressed: _asrBusy ? null : _clearAsr,
                child: Text(
                  l.aiClearSection,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _asrEngineLabel(L l, ProviderSectionStatus? section) {
    if (section == null) return l.aiStatusUnknown;
    return switch (section.engine) {
      'windows-sapi' => l.aiAsrEngineWindows,
      'http' => l.aiAsrEngineHttp,
      'fake' => l.aiAsrEngineFake,
      _ => l.aiAsrEngineNone,
    };
  }

  Widget _statusLine({
    required Key key,
    required L l,
    required String label,
    required bool good,
  }) {
    final color = good ? AnchorTheme.primary : AnchorTheme.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          good ? Icons.check_circle : Icons.info_outline,
          size: 28,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${l.aiStatusLine}：$label',
            key: key,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultText({
    required Key key,
    required String text,
    required bool failed,
  }) {
    return Text(
      text,
      key: key,
      style: TextStyle(
        fontSize: 22,
        height: 1.35,
        color: failed ? AnchorTheme.danger : AnchorTheme.primary,
      ),
    );
  }
}
