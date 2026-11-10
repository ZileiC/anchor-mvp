import 'dart:io' show Platform;

import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The two-shapes decision (2026-11-10) is one tiny object; these tests pin the
/// rule itself, so a later screen cannot quietly invent a third shape.
void main() {
  group('PlatformPolicy', () {
    test(
      'a real build is the appliance on Windows and the phone elsewhere',
      () {
        final policy = PlatformPolicy.fromPlatform();
        expect(policy.seniorAppliance, Platform.isWindows);
        expect(policy.setupApp, !Platform.isWindows);
      },
    );

    test('the two named shapes are exact inverses', () {
      const appliance = PlatformPolicy.seniorAppliance();
      expect(appliance.seniorAppliance, isTrue);
      expect(appliance.setupApp, isFalse);

      const phone = PlatformPolicy.setupApp();
      expect(phone.seniorAppliance, isFalse);
      expect(phone.setupApp, isTrue);
    });

    test('is const-constructible, so a screen can be exercised as either', () {
      const explicit = PlatformPolicy(seniorAppliance: false);
      expect(explicit.setupApp, isTrue);
      expect(explicit.seniorAppliance, isFalse);
    });

    test('instance follows the platform and reset restores it', () {
      expect(PlatformPolicy.instance.seniorAppliance, Platform.isWindows);
      PlatformPolicy.instance = const PlatformPolicy.setupApp();
      addTearDown(PlatformPolicy.resetInstance);
      expect(PlatformPolicy.instance.setupApp, isTrue);
      PlatformPolicy.resetInstance();
      expect(PlatformPolicy.instance.seniorAppliance, Platform.isWindows);
    });

    test(
      'an AppState without an explicit policy uses the platform default',
      () {
        PlatformPolicy.instance = const PlatformPolicy.setupApp();
        addTearDown(PlatformPolicy.resetInstance);
        final state = AppState(
          api: FakeApi(),
          speaker: SilentSpeaker(),
          microphone: FakeMicrophoneInput(),
          dialer: FakeDialer(),
        );
        expect(state.policy.setupApp, isTrue);
        expect(state.voiceAllowed, isFalse);
      },
    );
  });
}
