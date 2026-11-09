import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/senior/ai_providers_screen.dart';
import 'package:anchor_app/screens/senior/settings_screen.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Real-provider UX: the Settings screen must be able to save and test an API
/// key, and the Talk screen must never record or invent a transcript without a
/// configured recogniser.
void main() {
  late FakeApi api;
  late AppState state;

  setUp(() {
    api = FakeApi();
    state = buildTestState(api);
  });

  const configuredLlm = ProviderSectionStatus(
    configured: true,
    mode: 'http',
    engine: 'http',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
    keyHint: 'sk-…abcd',
  );
  const sapiAsr = ProviderSectionStatus(
    configured: true,
    mode: 'offline',
    engine: 'windows-sapi',
    model: 'whisper-1',
  );

  Future<void> openAiScreen(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('primary-settings')));
    await tester.tap(find.byKey(const Key('primary-settings')));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('settings-ai-entry')));
    await tester.tap(find.byKey(const Key('settings-ai-entry')));
    await settle(tester);
    expect(find.byType(AiProvidersScreen), findsOneWidget);
  }

  Future<void> openTalk(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('primary-talk')));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
  }

  group('AI settings screen', () {
    testWidgets('both sections are rendered with their status lines', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      expect(find.text(L.zh.aiLlmSection), findsOneWidget);
      expect(find.text(L.zh.aiAsrSection), findsOneWidget);
      for (final key in <Key>[
        const Key('ai-llm-base-url'),
        const Key('ai-llm-model'),
        const Key('ai-llm-key'),
        const Key('ai-llm-preset'),
        const Key('ai-llm-save'),
        const Key('ai-llm-test'),
        const Key('ai-llm-clear'),
        const Key('ai-asr-base-url'),
        const Key('ai-asr-model'),
        const Key('ai-asr-key'),
        const Key('ai-asr-save'),
        const Key('ai-asr-test'),
        const Key('ai-asr-clear'),
      ]) {
        await tester.ensureVisible(find.byKey(key));
        expect(find.byKey(key), findsOneWidget, reason: '$key');
      }

      final asrStatus = tester.widget<Text>(
        find.byKey(const Key('ai-asr-status')),
      );
      expect(asrStatus.data, contains(L.zh.aiStatusLine));

      await disposeApp(tester);
    });

    testWidgets('the DeepSeek preset fills the URL and model fields', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      await tester.ensureVisible(find.byKey(const Key('ai-llm-preset')));
      await tester.tap(find.byKey(const Key('ai-llm-preset')));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-llm-base-url')))
            .controller!
            .text,
        'https://api.deepseek.com',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-llm-model')))
            .controller!
            .text,
        'deepseek-chat',
      );

      await disposeApp(tester);
    });

    testWidgets('save sends a partial PUT and the new status shows up', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      await tester.ensureVisible(find.byKey(const Key('ai-llm-preset')));
      await tester.tap(find.byKey(const Key('ai-llm-preset')));
      await tester.ensureVisible(find.byKey(const Key('ai-llm-key')));
      await tester.enterText(
        find.byKey(const Key('ai-llm-key')),
        'sk-test-123456',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-llm-save')));
      await tester.tap(find.byKey(const Key('ai-llm-save')));
      await settle(tester);

      expect(api.providerUpdates, hasLength(1));
      expect(api.providerUpdates.single.llm!.toJson(), <String, Object?>{
        'base_url': 'https://api.deepseek.com',
        'api_key': 'sk-test-123456',
        'model': 'deepseek-chat',
      });

      final status = tester.widget<Text>(
        find.byKey(const Key('ai-llm-status')),
      );
      expect(status.data, '${L.zh.aiStatusLine}：${L.zh.aiStatusHttp}');
      // The key field is cleared and only the masked hint remains.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-llm-key')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('ai-llm-key-hint')), findsOneWidget);

      // Back in Settings the same refreshed status is visible.
      await tester.pageBack();
      await settle(tester);
      final settingsStatus = tester.widget<Text>(
        find.byKey(const Key('settings-ai-llm-status')),
      );
      expect(settingsStatus.data, contains(L.zh.aiStatusHttp));

      await disposeApp(tester);
    });

    testWidgets('the saved key hint is shown and a blank key is not re-sent', (
      tester,
    ) async {
      api.providerStatusValue = const ProviderStatus(
        llm: configuredLlm,
        asr: sapiAsr,
      );
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      expect(find.text(L.zh.aiSavedKeyHint('sk-…abcd')), findsOneWidget);
      expect(find.textContaining('sk-test'), findsNothing);
      final keyField = tester.widget<TextField>(
        find.byKey(const Key('ai-llm-key')),
      );
      expect(keyField.obscureText, isTrue);
      expect(keyField.controller!.text, isEmpty);

      await tester.ensureVisible(find.byKey(const Key('ai-llm-save')));
      await tester.tap(find.byKey(const Key('ai-llm-save')));
      await settle(tester);

      final sent = api.providerUpdates.single.llm!.toJson();
      expect(sent.containsKey('api_key'), isFalse);
      expect(sent['base_url'], 'https://api.deepseek.com');

      await disposeApp(tester);
    });

    testWidgets('test connection renders the reply sample and then the error', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      await tester.ensureVisible(find.byKey(const Key('ai-llm-test')));
      await tester.tap(find.byKey(const Key('ai-llm-test')));
      await settle(tester);
      expect(find.text(L.zh.aiTestOkDetail(42, '你好，我在这里。')), findsOneWidget);
      expect(api.lastTestAudioB64, isNull);

      api.providerTestResult = const ProviderTestResult(
        llm: ProviderProbeResult(ok: false, error: 'unauthorized: bad key'),
        asr: ProviderProbeResult(ok: false, reason: 'no_sample'),
      );
      await tester.tap(find.byKey(const Key('ai-llm-test')));
      await settle(tester);
      expect(
        find.text(L.zh.aiTestFailed('unauthorized: bad key')),
        findsOneWidget,
      );

      await disposeApp(tester);
    });

    testWidgets('ASR test records a clip, posts audio_b64 and shows the text', (
      tester,
    ) async {
      api.providerStatusValue = const ProviderStatus(
        llm: configuredLlm,
        asr: sapiAsr,
      );
      api.providerTestResult = const ProviderTestResult(
        llm: ProviderProbeResult(ok: true, latencyMs: 10, replySample: '好'),
        asr: ProviderProbeResult(
          ok: true,
          latencyMs: 180,
          textSample: '今天天气很好',
        ),
      );
      final mic = FakeMicrophoneInput();
      state = buildTestState(api, microphone: mic);
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openAiScreen(tester);

      await tester.ensureVisible(find.byKey(const Key('ai-asr-test')));
      await tester.tap(find.byKey(const Key('ai-asr-test')));
      await settle(tester);

      expect(mic.startCalls, 1);
      expect(mic.stopCalls, 1);
      expect(api.lastTestAudioB64, mic.captured!.base64);
      expect(api.lastTestAudioMime, 'audio/wav');
      expect(find.text(L.zh.aiAsrTranscript('今天天气很好')), findsOneWidget);

      // The honest failure: the server says there was no usable sample.
      api.providerTestResult = const ProviderTestResult(
        llm: ProviderProbeResult(ok: true, latencyMs: 10, replySample: '好'),
        asr: ProviderProbeResult(ok: false, reason: 'no_sample'),
      );
      await tester.ensureVisible(find.byKey(const Key('ai-asr-test')));
      await tester.tap(find.byKey(const Key('ai-asr-test')));
      await settle(tester);
      expect(find.text(L.zh.aiAsrReasonNoSample), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('the caregiver cannot open AI settings', (tester) async {
      api.asCaregiver();
      await pumpSignedIn(
        tester,
        state,
        caregiver: true,
        size: const Size(390, 844),
      );
      expect(find.byKey(const Key('settings-ai-entry')), findsNothing);

      // Even a hand-built route refuses to act for a caregiver.
      await tester.pumpWidget(
        AnchorScope(
          state: state,
          child: MaterialApp(
            theme: AnchorTheme.build(),
            home: AiProvidersScreen(state: state),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(L.zh.aiProvidersSeniorOnly), findsOneWidget);
      expect(find.byKey(const Key('ai-llm-save')), findsNothing);

      await disposeApp(tester);
    });
  });

  group('Talk screen provider states', () {
    testWidgets('without ASR the mic is greyed, warns and records nothing', (
      tester,
    ) async {
      final mic = FakeMicrophoneInput();
      state = buildTestState(api, microphone: mic);
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openTalk(tester);

      // The offline LLM badge is honest while no real model is configured.
      expect(find.byKey(const Key('talk-offline-llm-badge')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('mic-indicator')),
                matching: find.byType(Text),
              ),
            )
            .data,
        L.zh.micNotConnected,
      );

      await tester.ensureVisible(find.byKey(const Key('talk-mic')));
      await tester.tap(find.byKey(const Key('talk-mic')));
      await settle(tester);

      expect(find.byKey(const Key('talk-asr-dialog')), findsOneWidget);
      expect(find.text(L.zh.asrNotConnectedTitle), findsOneWidget);
      expect(mic.startCalls, 0);
      expect(api.turnCalls, 0);
      expect(state.recording, isFalse);

      await tester.tap(find.byKey(const Key('talk-asr-type-instead')));
      await settle(tester);
      expect(find.byKey(const Key('talk-asr-dialog')), findsNothing);
      expect(find.byKey(const Key('talk-text-field')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets(
      'with ASR the mic records and sends audio_b64 for a real transcript',
      (tester) async {
        api.providerStatusValue = const ProviderStatus(
          llm: configuredLlm,
          asr: sapiAsr,
        );
        final mic = FakeMicrophoneInput();
        state = buildTestState(api, microphone: mic);
        await pumpSignedIn(tester, state, size: const Size(390, 844));
        await openTalk(tester);
        expect(find.byKey(const Key('talk-offline-llm-badge')), findsNothing);

        await tester.ensureVisible(find.byKey(const Key('talk-mic')));
        await tester.tap(find.byKey(const Key('talk-mic')));
        await settle(tester);
        expect(mic.startCalls, 1);
        expect(state.recording, isTrue);

        await tester.tap(find.byKey(const Key('talk-mic')));
        await settle(tester);

        expect(api.lastTurnAudioB64, mic.captured!.base64);
        expect(api.lastTurnText, isNull);
        expect(state.captions, hasLength(2));
        expect(find.text('这是识别结果'), findsOneWidget);
        expect(find.text('好的，我在听。'), findsOneWidget);

        await disposeApp(tester);
      },
    );

    testWidgets('a 503 turn offers Retry / type instead and no fake reply', (
      tester,
    ) async {
      api.providerStatusValue = const ProviderStatus(
        llm: configuredLlm,
        asr: sapiAsr,
      );
      api.turnError = const ApiException(
        code: 'provider_unavailable',
        message: 'Speech provider unavailable',
        statusCode: 503,
        recovery: <String>['retry', 'type_instead'],
      );
      final mic = FakeMicrophoneInput();
      state = buildTestState(api, microphone: mic);
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await openTalk(tester);

      await tester.ensureVisible(find.byKey(const Key('talk-mic')));
      await tester.tap(find.byKey(const Key('talk-mic')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('talk-mic')));
      await settle(tester);

      expect(find.text(L.zh.providerUnavailableTitle), findsOneWidget);
      expect(
        find.byKey(const Key('talk-provider-type-instead')),
        findsOneWidget,
      );
      expect(find.text('好的，我在听。'), findsNothing);
      expect(state.captions, isEmpty);

      // The failed clip is kept, so Retry really resends it.
      api.turnError = null;
      await tester.tap(find.widgetWithText(OutlinedButton, L.zh.retry));
      await settle(tester);

      expect(find.text(L.zh.providerUnavailableTitle), findsNothing);
      expect(find.text('这是识别结果'), findsOneWidget);
      expect(find.text('好的，我在听。'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets(
      'the offline badge hides as soon as a real model is configured',
      (tester) async {
        api.providerStatusValue = const ProviderStatus(
          llm: configuredLlm,
          asr: sapiAsr,
        );
        await pumpSignedIn(tester, state, size: const Size(390, 844));
        await openTalk(tester);

        expect(state.llmConfigured, isTrue);
        expect(state.showOfflineLlmBadge, isFalse);
        expect(find.byKey(const Key('talk-offline-llm-badge')), findsNothing);

        await disposeApp(tester);
      },
    );
  });
}
