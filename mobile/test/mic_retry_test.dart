import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The microphone used to be a one-strike failure: the first `startRecording()`
/// error set a flag that hid the mic button for the rest of the app run, so a
/// busy Bluetooth headset killed voice input until a restart. These tests pin
/// the retry behaviour that replaces it.
void main() {
  late FakeApi api;
  late FakeMicrophoneInput mic;
  late AppState state;

  setUp(() {
    api = FakeApi()..feed = threeActivityFeed();
    api.providerStatusValue = const ProviderStatus(
      llm: ProviderSectionStatus(
        configured: true,
        mode: 'http',
        engine: 'http',
        model: 'deepseek-chat',
      ),
      asr: ProviderSectionStatus(
        configured: true,
        mode: 'http',
        engine: 'http',
        model: 'whisper-1',
      ),
    );
    mic = FakeMicrophoneInput();
    state = buildTestState(api, microphone: mic);
  });

  testWidgets('a failed start is retryable without restarting the app', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    expect(state.asrConfigured, isTrue);

    mic.failStartWith = 'default/16000Hz: device busy';
    expect(await state.startRecording(), isFalse);
    expect(state.micUnavailable, isTrue);
    expect(state.recording, isFalse);

    // The other app let go of the microphone: the very next tap must work.
    mic.failStartWith = null;
    expect(await state.startRecording(), isTrue);
    expect(state.recording, isTrue);
    expect(state.micUnavailable, isFalse);
  });

  testWidgets('the mic button stays tappable after a failure', (tester) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);

    mic.failStartWith = 'default/16000Hz: device busy';
    await tester.tap(find.byKey(const Key('talk-mic')));
    await settle(tester);
    expect(state.micUnavailable, isTrue);

    // The control is still on screen, so the older adult can simply try again.
    expect(find.byKey(const Key('talk-mic')), findsOneWidget);
  });
}
