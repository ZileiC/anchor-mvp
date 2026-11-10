import 'dart:async';

import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Play by voice: the card reads itself aloud, one big button records a short
/// answer, and the transcript is graded exactly like a tap — or honestly not
/// graded at all. These tests never touch a device or a server: the microphone
/// and the recogniser are doubles, so they prove the screen's contract, not that
/// speech recognition works (it cannot be heard from a widget test).
void main() {
  // A recogniser that the backend says is available (the local Windows one).
  const configuredAsr = ProviderStatus(
    llm: ProviderSectionStatus(
      configured: false,
      mode: 'offline',
      engine: 'offline-rule',
    ),
    asr: ProviderSectionStatus(
      configured: true,
      mode: 'offline',
      engine: 'windows-sapi',
    ),
  );

  const trivia = ActivityItem(
    id: 'trivia-1',
    type: 'trivia',
    title: '一年有几个月',
    prompt: '一年有多少个月呀？',
    minutes: 3,
    options: <String>['10', '11', '12'],
    answerIndex: 2,
    explanation: '一年有十二个月。',
    wrongHint: '再数一数日历上的月份。',
  );

  // The real content pack's first card: three long paraphrases.
  const fire = ActivityItem(
    id: 'trivia-01',
    type: 'trivia',
    title: '油锅着了火',
    prompt: '炒菜的时候油锅着了火，第一步该做什么？',
    minutes: 3,
    options: <String>['先泼一盆水', '把锅盖盖上', '端起来往水池挪'],
    answerIndex: 1,
    explanation: '盖上锅盖，火没了空气，一会儿就灭。',
    wrongHint: '这个法子有点险。',
  );

  ActivityFeed feedOf(ActivityItem item) =>
      ActivityFeed(items: <ActivityItem>[item], rotation: <String>[item.id]);

  Color? feedbackFill(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const Key('activity-feedback')),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  SilentSpeaker speakerOf(AppState state) => state.speaker as SilentSpeaker;

  Future<void> openPlay(
    WidgetTester tester,
    AppState state, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    await pumpSignedIn(tester, state, size: size, textScale: textScale);
    await tester.tap(find.byKey(const Key('primary-play')));
    await settle(tester);
  }

  Future<void> tapVoice(WidgetTester tester, {bool settled = true}) async {
    final finder = find.byKey(const Key('activity-voice'));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    if (settled) {
      await settle(tester);
    } else {
      await tester.pump();
    }
  }

  Future<void> tapOption(WidgetTester tester, int index) async {
    final finder = find.byKey(Key('activity-option-$index'));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  group('the card reads itself', () {
    testWidgets('title then question is spoken once when the card opens', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(trivia);
      final state = buildTestState(api);
      await openPlay(tester, state);

      expect(speakerOf(state).spoken, <String>['一年有几个月\n一年有多少个月呀？']);

      // 再念一遍 says the same thing again, and only once per tap.
      final repeat = find.byKey(const Key('activity-repeat-question'));
      await tester.ensureVisible(repeat);
      await tester.tap(repeat);
      await settle(tester);
      expect(speakerOf(state).spoken, <String>[
        '一年有几个月\n一年有多少个月呀？',
        '一年有几个月\n一年有多少个月呀？',
      ]);

      await disposeApp(tester);
    });
  });

  group('answering out loud', () {
    testWidgets('a spoken number is graded exactly like tapping that option', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '十二';
      final mic = FakeMicrophoneInput();
      final state = buildTestState(api, microphone: mic);
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(mic.startCalls, 1);
      expect(mic.stopCalls, 1);
      expect(api.transcribeCalls, 1);
      expect(api.lastTranscribeAudioB64, mic.captured!.base64);
      expect(api.lastTranscribeAudioMime, 'audio/wav');

      // Same panel, same colour, same sentence as a tap on option 2.
      final sentence = '${L.zh.activityCorrect}\n一年有十二个月。';
      expect(find.text(sentence), findsOneWidget, reason: 'graded as correct');
      expect(feedbackFill(tester), const Color(0xFFE3EFE6));
      expect(speakerOf(state).spoken.last, sentence);
      // The senior can see what was understood.
      expect(find.text(L.zh.activityVoiceHeard('十二')), findsOneWidget);
      // It locked the card: a later tap changes nothing.
      await tapOption(tester, 0);
      expect(find.text(sentence), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a paraphrase picks the right long option', (tester) async {
      final api = FakeApi()
        ..feed = feedOf(fire)
        ..providerStatusValue = configuredAsr
        ..transcript = '盖上锅盖';
      final state = buildTestState(api, microphone: FakeMicrophoneInput());
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(
        find.text('${L.zh.activityCorrect}\n盖上锅盖，火没了空气，一会儿就灭。'),
        findsOneWidget,
      );
      expect(feedbackFill(tester), const Color(0xFFE3EFE6));
      // The right option is visibly marked.
      expect(
        find.descendant(
          of: find.byKey(const Key('activity-option-1')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );

      await disposeApp(tester);
    });

    testWidgets('a transcript that fits nothing shows 没听清 and stays unlocked', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '今天天气不错';
      final state = buildTestState(api, microphone: FakeMicrophoneInput());
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(find.byKey(const Key('activity-voice-missed')), findsOneWidget);
      expect(find.byKey(const Key('activity-feedback')), findsNothing);
      expect(find.text(L.zh.activityVoiceHeard('今天天气不错')), findsOneWidget);
      expect(speakerOf(state).spoken.last, L.zh.activityVoiceMissedSpoken);
      // The reply never grades: it asks to retry or tap.
      expect(find.textContaining(L.zh.activityVoiceMissedHint), findsOneWidget);

      // A tap still works, and clears the amber panel.
      await tapOption(tester, 2);
      expect(find.text('${L.zh.activityCorrect}\n一年有十二个月。'), findsOneWidget);
      expect(find.byKey(const Key('activity-voice-missed')), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('silence shows 没听到声音 instead of a made-up answer', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '';
      final state = buildTestState(api, microphone: FakeMicrophoneInput());
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(find.byKey(const Key('activity-voice-nothing')), findsOneWidget);
      expect(find.byKey(const Key('activity-voice-missed')), findsNothing);
      expect(find.byKey(const Key('activity-feedback')), findsNothing);
      expect(speakerOf(state).spoken.last, L.zh.activityVoiceNothingSpoken);

      await disposeApp(tester);
    });

    testWidgets('no microphone is an honest panel, not a fake transcript', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr;
      // The default test microphone is the unavailable one.
      final state = buildTestState(api);
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(state.micUnavailable, isTrue);
      expect(api.transcribeCalls, 0);
      expect(find.byKey(const Key('activity-voice-nothing')), findsOneWidget);
      expect(find.byKey(const Key('activity-feedback')), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('a dead recogniser (503) keeps the card ungraded and open', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcribeError = const ApiException(
          code: 'provider_unavailable',
          message: 'no recogniser',
          statusCode: 503,
        );
      final state = buildTestState(api, microphone: FakeMicrophoneInput());
      await openPlay(tester, state);

      await tapVoice(tester);

      expect(state.lastError?.code, 'provider_unavailable');
      expect(find.byKey(const Key('activity-feedback')), findsNothing);
      expect(find.byKey(const Key('activity-voice-nothing')), findsOneWidget);
      // The failure is visible (the error banner), so the senior can tap instead.
      expect(find.text(state.lastErrorText!), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('the button is disabled while listening, then works', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '十二'
        ..transcribeGate = gate;
      final mic = FakeMicrophoneInput();
      final state = buildTestState(
        api,
        microphone: mic,
        answerDuration: const Duration(milliseconds: 300),
      );
      await openPlay(tester, state);

      await tapVoice(tester, settled: false);

      // Listening: the label says so, and the button cannot start a second take.
      expect(find.text(L.zh.activityVoiceListening), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activity-voice')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('activity-repeat-question')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const Key('activity-voice')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(mic.startCalls, 1, reason: 'a second tap starts no recording');

      // The clip is closed and being transcribed: "working", still not tappable.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text(L.zh.activityVoiceWorking), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activity-voice')))
            .onPressed,
        isNull,
      );

      gate.complete();
      await settle(tester);
      expect(find.text('${L.zh.activityCorrect}\n一年有十二个月。'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('without a recogniser the button is disabled and says why', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(trivia);
      final state = buildTestState(api);
      await openPlay(tester, state);

      expect(find.text(L.zh.activityVoiceAnswer), findsOneWidget);
      expect(find.text(L.zh.activityVoiceNotReady), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activity-voice')))
            .onPressed,
        isNull,
      );
      // Big enough to be the obvious target for a hand that would rather not tap.
      expect(
        tester.getSize(find.byKey(const Key('activity-voice'))).height,
        greaterThanOrEqualTo(72),
      );

      await disposeApp(tester);
    });
  });

  group('cancelling', () {
    testWidgets('Stop closes the microphone and drops a late transcript', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '十二';
      final mic = FakeMicrophoneInput();
      final state = buildTestState(
        api,
        microphone: mic,
        answerDuration: const Duration(seconds: 2),
      );
      await openPlay(tester, state);

      await tapVoice(tester, settled: false);
      expect(find.text(L.zh.activityVoiceListening), findsOneWidget);

      await tester.tap(find.byKey(const Key('stop-control')));
      await settle(tester);
      expect(state.recording, isFalse);
      expect(mic.cancelCalls, greaterThanOrEqualTo(1));

      // Let the abandoned recording window close: nothing may be transcribed.
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(api.transcribeCalls, 0);
      expect(find.byKey(const Key('activity-feedback')), findsNothing);
      expect(find.byKey(const Key('activity-done')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('finishing the activity also closes the microphone', (
      tester,
    ) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr
        ..transcript = '十二';
      final mic = FakeMicrophoneInput();
      final state = buildTestState(
        api,
        microphone: mic,
        answerDuration: const Duration(seconds: 2),
      );
      await openPlay(tester, state);

      await tapVoice(tester, settled: false);
      expect(find.text(L.zh.activityVoiceListening), findsOneWidget);

      final finish = find.byKey(const Key('activity-finish'));
      await tester.ensureVisible(finish);
      await tester.pump();
      await tester.tap(finish);
      await settle(tester);

      expect(state.recording, isFalse);
      expect(mic.cancelCalls, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 3));
      expect(api.transcribeCalls, 0);
      expect(find.byKey(const Key('activity-done')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('leaving the screen closes the microphone', (tester) async {
      final api = FakeApi()
        ..feed = feedOf(trivia)
        ..providerStatusValue = configuredAsr;
      final mic = FakeMicrophoneInput();
      final state = buildTestState(
        api,
        microphone: mic,
        answerDuration: const Duration(seconds: 2),
      );
      await openPlay(tester, state);

      await tapVoice(tester, settled: false);
      expect(state.recording, isTrue);

      await tester.pageBack();
      await settle(tester);

      expect(state.recording, isFalse);
      expect(mic.cancelCalls, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 3));
      expect(api.transcribeCalls, 0);
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });
  });

  testWidgets('the voice controls survive 1.3x text on a phone', (
    tester,
  ) async {
    final api = FakeApi()
      ..feed = feedOf(trivia)
      ..providerStatusValue = configuredAsr
      ..transcript = '今天天气不错';
    final state = buildTestState(api, microphone: FakeMicrophoneInput());
    await openPlay(tester, state, textScale: 1.3);
    expect(tester.takeException(), isNull);

    await tapVoice(tester);
    expect(tester.takeException(), isNull);

    await tapOption(tester, 2);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  group('AppState.listenForAnswer', () {
    test('returns null without a recogniser and never opens the mic', () async {
      final api = FakeApi();
      final mic = FakeMicrophoneInput();
      final state = buildTestState(api, microphone: mic);

      expect(await state.listenForAnswer(), isNull);
      expect(mic.startCalls, 0);
      expect(api.transcribeCalls, 0);

      state.dispose();
    });

    test('records once, transcribes once and never speaks or chats', () async {
      final api = FakeApi()
        ..providerStatusValue = configuredAsr
        ..transcript = '十二';
      final mic = FakeMicrophoneInput();
      final state = buildTestState(api, microphone: mic)
        ..providers = configuredAsr;

      final words = await state.listenForAnswer();

      expect(words, '十二');
      expect(mic.startCalls, 1);
      expect(mic.stopCalls, 1);
      expect(api.transcribeCalls, 1);
      expect(api.lastTranscribeAudioB64, mic.captured!.base64);
      expect(api.openSessionCalls, 0, reason: 'a card answer is not a chat');
      expect((state.speaker as SilentSpeaker).spoken, isEmpty);
      expect(state.recording, isFalse);

      state.dispose();
    });

    test(
      'a second call while recording does not start a second take',
      () async {
        final api = FakeApi()..providerStatusValue = configuredAsr;
        api.transcript = '十二';
        final mic = FakeMicrophoneInput();
        final state = buildTestState(api, microphone: mic)
          ..providers = configuredAsr;

        final first = state.listenForAnswer();
        final second = await state.listenForAnswer();
        expect(second, isNull);
        expect(await first, '十二');
        expect(mic.startCalls, 1);
        expect(api.transcribeCalls, 1);

        state.dispose();
      },
    );

    test('a missing device reports the same mic state Talk uses', () async {
      final api = FakeApi()..providerStatusValue = configuredAsr;
      final state = buildTestState(api)..providers = configuredAsr;

      expect(await state.listenForAnswer(), isNull);
      expect(state.micUnavailable, isTrue);
      expect(state.micFailed, isTrue);
      expect(api.transcribeCalls, 0);

      state.dispose();
    });

    test('cancelRecording drops the take before it is transcribed', () async {
      final api = FakeApi()..providerStatusValue = configuredAsr;
      final mic = FakeMicrophoneInput();
      final state = buildTestState(api, microphone: mic)
        ..providers = configuredAsr;

      final pending = state.listenForAnswer();
      await state.cancelRecording();

      expect(await pending, isNull);
      expect(mic.cancelCalls, 1);
      expect(api.transcribeCalls, 0);

      state.dispose();
    });

    test('a 503 is reported through lastError, not a transcript', () async {
      final api = FakeApi()
        ..providerStatusValue = configuredAsr
        ..transcribeError = const ApiException(
          code: 'provider_unavailable',
          message: 'no recogniser',
          statusCode: 503,
        );
      final state = buildTestState(api, microphone: FakeMicrophoneInput())
        ..providers = configuredAsr;

      expect(await state.listenForAnswer(), isNull);
      expect(state.lastError?.code, 'provider_unavailable');

      state.dispose();
    });
  });
}
