import 'dart:async';

import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/screens/senior/ai_providers_screen.dart';
import 'package:anchor_app/screens/senior/home_screen.dart';
import 'package:anchor_app/screens/senior/settings_screen.dart';
import 'package:anchor_app/screens/setup/setup_home_screen.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The two shapes decided on 2026-11-10, asserted on both sides of the split:
///
/// * Windows is the older adult's appliance — Talk / Play / Call / Stop, and no
///   Settings or AI 接入 anywhere, not even from a hand-built route.
/// * The phone is the family/setup app — AI 接入, family and records, and no
///   conversation UI; its voice calls are no-ops that never open the mic.
const ProviderStatus _configuredRecogniser = ProviderStatus(
  llm: ProviderSectionStatus(
    configured: false,
    mode: 'offline',
    engine: 'offline-rule',
    model: 'deepseek-chat',
  ),
  asr: ProviderSectionStatus(
    configured: true,
    mode: 'offline',
    engine: 'windows-sapi',
    model: 'whisper-1',
  ),
);

void main() {
  group('the Windows appliance', () {
    late FakeApi api;
    late AppState state;

    setUp(() {
      api = FakeApi();
      state = buildTestState(api);
    });

    testWidgets('Home has no Settings tile and keeps the four senior actions', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));

      expect(find.byType(SeniorHomeScreen), findsOneWidget);
      expect(find.byKey(const Key('primary-settings')), findsNothing);
      // Nothing else was taken away from the senior.
      expect(find.byKey(const Key('primary-talk')), findsOneWidget);
      expect(find.byKey(const Key('primary-play')), findsOneWidget);
      expect(find.byKey(const Key('primary-call')), findsOneWidget);
      expect(find.byKey(const Key('stop-control')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a route that names Settings falls back to Home', (
      tester,
    ) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));

      // A deep link or a restored route can still name the screen by hand.
      final navigator = Navigator.of(
        tester.element(find.byType(SeniorHomeScreen)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(state: state)),
        ),
      );
      await settle(tester);

      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(SeniorHomeScreen), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a route that names AI 接入 falls back to Home', (tester) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));

      final navigator = Navigator.of(
        tester.element(find.byType(SeniorHomeScreen)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AiProvidersScreen(state: state),
          ),
        ),
      );
      await settle(tester);

      // No provider key field is ever shown on the appliance.
      expect(find.byType(AiProvidersScreen), findsNothing);
      expect(find.byKey(const Key('ai-llm-key')), findsNothing);
      expect(find.byType(SeniorHomeScreen), findsOneWidget);

      await disposeApp(tester);
    });
  });

  group('the family/setup phone', () {
    testWidgets(
      'the caregiver hub shows setup, AI and records — no Talk/Play',
      (tester) async {
        final api = FakeApi()..asCaregiver();
        final state = buildTestState(
          api,
          policy: const PlatformPolicy.setupApp(),
        );
        await pumpSignedIn(
          tester,
          state,
          caregiver: true,
          size: const Size(390, 844),
        );

        expect(find.byType(SetupHomeScreen), findsOneWidget);
        // No conversation UI at all on the phone.
        expect(find.byKey(const Key('primary-talk')), findsNothing);
        expect(find.byKey(const Key('primary-play')), findsNothing);
        expect(find.byKey(const Key('primary-call')), findsNothing);
        expect(find.byKey(const Key('stop-control')), findsNothing);
        // The four things the phone is for.
        expect(find.byKey(const Key('setup-device-note')), findsOneWidget);
        expect(find.text(L.zh.setupDeviceTitle), findsOneWidget);
        expect(find.byKey(const Key('setup-ai')), findsOneWidget);
        expect(find.byKey(const Key('setup-invite')), findsOneWidget);
        expect(find.byKey(const Key('setup-records-digest')), findsOneWidget);

        await disposeApp(tester);
      },
    );

    testWidgets('the hub still lays out at 1.6x text', (tester) async {
      // Signed in directly: the login picker itself needs scrolling at 1.6x and
      // this test is about the hub, not the picker.
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(780, 1688);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final api = FakeApi()..asCaregiver();
      final state = buildTestState(api, policy: const PlatformPolicy.setupApp())
        ..profile = api.profile;
      await tester.pumpWidget(AnchorApp(state: state));
      await settle(tester);

      expect(find.byType(SetupHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Everything on the hub is still reachable by scrolling at that scale.
      for (final key in <Key>[
        const Key('setup-ai'),
        const Key('setup-records-digest'),
        const Key('setup-refresh'),
      ]) {
        await tester.ensureVisible(find.byKey(key));
      }
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });

    testWidgets('the senior account may still open Settings, still no voice', (
      tester,
    ) async {
      final state = buildTestState(
        FakeApi(),
        policy: const PlatformPolicy.setupApp(),
      );
      await pumpSignedIn(tester, state, size: const Size(390, 844));

      expect(find.byType(SetupHomeScreen), findsOneWidget);
      expect(find.byKey(const Key('primary-talk')), findsNothing);
      expect(find.byKey(const Key('setup-settings')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('setup-settings')));
      await tester.tap(find.byKey(const Key('setup-settings')));
      await settle(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      // Stop belongs to a device that can talk; the phone has no Stop control.
      expect(find.byKey(const Key('stop-control')), findsNothing);

      await disposeApp(tester);
    });
  });

  group('voice is a no-op on the phone', () {
    test(
      'startRecording returns false and never touches the microphone',
      () async {
        final mic = FakeMicrophoneInput();
        final state =
            buildTestState(
                FakeApi(),
                microphone: mic,
                policy: const PlatformPolicy.setupApp(),
              )
              // A configured recogniser on purpose: the *platform* is the only
              // reason the mic stays shut.
              ..providers = _configuredRecogniser;

        expect(state.asrConfigured, isTrue);
        expect(state.voiceAllowed, isFalse);

        expect(await state.startRecording(), isFalse);
        expect(mic.startCalls, 0);
        expect(mic.stopCalls, 0);
        expect(state.recording, isFalse);

        // Every other voice entry point is gated the same way.
        expect(await state.listenForAnswer(), isNull);
        expect(await state.captureProbeClip(), isNull);
        await state.speakFeedback('你好');
        expect(mic.startCalls, 0);
        expect(mic.stopCalls, 0);
        expect((state.speaker as SilentSpeaker).spoken, isEmpty);

        state.dispose();
      },
    );

    test(
      'the appliance still records — nothing was taken from Windows',
      () async {
        final mic = FakeMicrophoneInput();
        final state = buildTestState(FakeApi(), microphone: mic)
          ..providers = _configuredRecogniser;

        expect(state.voiceAllowed, isTrue);
        expect(await state.startRecording(), isTrue);
        expect(mic.startCalls, 1);
        expect(state.recording, isTrue);

        // A probe clip is still recorded on the appliance (the ASR check lives
        // there in principle, even though the phone owns that screen now).
        await state.cancelRecording();
        expect(await state.captureProbeClip(), isNotNull);
        expect(mic.startCalls, 2);

        await state.stopAll();
        state.dispose();
      },
    );
  });
}
