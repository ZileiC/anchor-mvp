import 'dart:async';
import 'dart:convert';

import 'package:anchor_app/services/android_tts_speaker.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/backend_tts_speaker.dart';
import 'package:anchor_app/services/speaker_factory.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/services/windows_sapi_speaker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client double: proves the factory hands the app's own client to the speaker
/// (no socket is ever opened).
class FakeApiClient extends ApiClient {
  FakeApiClient()
    : super(baseUrl: 'http://fake', transport: const UnavailableTransport());
}

/// Launcher double: records the spawned command and whether it was killed, so
/// the SAPI speaker can be tested without ever starting a real PowerShell.
class FakeLauncher implements SpeechProcessLauncher {
  FakeLauncher({this.failOnLaunch = false});

  final bool failOnLaunch;
  int launchCount = 0;
  String? lastExecutable;
  List<String>? lastArguments;
  int killCount = 0;

  @override
  Future<SpeechProcessHandle> launch(
    String executable,
    List<String> arguments,
  ) async {
    launchCount++;
    lastExecutable = executable;
    lastArguments = arguments;
    if (failOnLaunch) {
      throw StateError('powershell.exe is not available');
    }
    return SpeechProcessHandle(
      kill: () => killCount++,
      done: Completer<void>().future,
    );
  }
}

/// Windows must never use flutter_tts (native access violation in
/// flutter_tts_plugin.dll); it must use the SAPI speaker instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('platform selection', () {
    test('maps platform names to a speaker target', () {
      expect(speakerTargetFor('windows'), SpeakerTarget.windows);
      expect(speakerTargetFor('Windows'), SpeakerTarget.windows);
      expect(speakerTargetFor(' android '), SpeakerTarget.android);
      expect(speakerTargetFor('ios'), SpeakerTarget.ios);
      expect(speakerTargetFor('web'), SpeakerTarget.web);
      expect(speakerTargetFor('linux'), SpeakerTarget.other);
      expect(speakerTargetFor('macos'), SpeakerTarget.other);
      expect(speakerTargetFor(null), SpeakerTarget.other);
      expect(speakerTargetFor(''), SpeakerTarget.other);
    });

    test('Windows gets the backend voice with a SAPI fallback, never '
        'flutter_tts', () {
      final speaker = createSpeakerForTarget(SpeakerTarget.windows);
      expect(speaker, isA<BackendTtsSpeaker>());
      expect(speaker, isNot(isA<TtsService>()));
      // The device voice is still there for when the backend cannot deliver.
      final windows = speaker as BackendTtsSpeaker;
      expect(windows.fallback, isA<WindowsSapiSpeaker>());
    });

    test('mobile speaks with the backend voice and keeps the device voice as '
        'its fallback', () {
      final android = createSpeakerForTarget(SpeakerTarget.android);
      expect(android, isA<AndroidTtsSpeaker>());
      expect(
        android,
        isNot(isA<TtsService>()),
        reason: 'the device voice alone is not the Windows feature set',
      );
      expect((android as AndroidTtsSpeaker).fallback, isA<TtsService>());

      final ios = createSpeakerForTarget(SpeakerTarget.ios);
      expect(ios, isA<AndroidTtsSpeaker>());
      expect((ios as AndroidTtsSpeaker).fallback, isA<TtsService>());

      expect(createSpeakerForTarget(SpeakerTarget.web), isA<SilentSpeaker>());
    });

    test('Android gets the app client, so login also authorises POST /tts', () {
      final api = FakeApiClient();
      final speaker = createSpeakerForTarget(SpeakerTarget.android, api: api);

      expect((speaker as AndroidTtsSpeaker).api, same(api));
    });
  });

  group('WindowsSapiSpeaker', () {
    test('stop() is safe when nothing is playing', () async {
      final launcher = FakeLauncher();
      final speaker = WindowsSapiSpeaker(launcher: launcher);

      await speaker.stop();
      await speaker.stop();
      await speaker.dispose();

      expect(launcher.launchCount, 0);
      expect(speaker.speaking, isFalse);
      expect(speaker.lastAttemptFailed, isFalse);
    });

    test('a failed launch never throws into the UI', () async {
      final speaker = WindowsSapiSpeaker(
        launcher: FakeLauncher(failOnLaunch: true),
      );

      await expectLater(speaker.speak('你好'), completes);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(speaker.speaking, isFalse);

      // And stop() after a failure is still safe.
      await expectLater(speaker.stop(), completes);
    });

    test(
      'spawns PowerShell with the text base64-encoded in the script',
      () async {
        final launcher = FakeLauncher();
        final speaker = WindowsSapiSpeaker(launcher: launcher);

        await speaker.speak('你好，今天想聊点什么？');

        expect(launcher.launchCount, 1);
        expect(launcher.lastExecutable, 'powershell.exe');
        final arguments = launcher.lastArguments!;
        expect(arguments, contains('-NoProfile'));
        expect(arguments, contains('-NonInteractive'));
        expect(arguments, contains('-ExecutionPolicy'));
        expect(arguments, contains('Bypass'));
        expect(arguments, contains('-Command'));
        final script = arguments.last;
        expect(script, contains('Add-Type -AssemblyName System.Speech'));
        expect(
          script,
          contains('New-Object System.Speech.Synthesis.SpeechSynthesizer'),
        );
        expect(
          script,
          contains(base64Encode(utf8.encode('你好，今天想聊点什么？'))),
          reason:
              'the utterance must be base64 so quotes and CJK cannot break it',
        );
        expect(script, isNot(contains('你好，今天想聊点什么？')));
        expect(speaker.speaking, isTrue);
        expect(speaker.lastAttemptFailed, isFalse);
      },
    );

    test('slow pace maps to a negative SAPI rate', () async {
      final slowLauncher = FakeLauncher();
      await WindowsSapiSpeaker(launcher: slowLauncher).speak('慢一点', slow: true);
      expect(slowLauncher.lastArguments!.last, contains('Rate = -2'));

      final normalLauncher = FakeLauncher();
      await WindowsSapiSpeaker(launcher: normalLauncher)
          .speak('正常', slow: false);
      expect(normalLauncher.lastArguments!.last, contains('Rate = 0'));
    });

    test('stop() kills the speaking process so Stop silences speech', () async {
      final launcher = FakeLauncher();
      final speaker = WindowsSapiSpeaker(launcher: launcher);
      await speaker.speak('说一句话');
      expect(speaker.speaking, isTrue);

      await speaker.stop();

      expect(launcher.killCount, 1);
      expect(speaker.speaking, isFalse);
    });

    test('a new utterance interrupts the previous one', () async {
      final launcher = FakeLauncher();
      final speaker = WindowsSapiSpeaker(launcher: launcher);

      await speaker.speak('第一句');
      await speaker.speak('第二句');

      expect(launcher.launchCount, 2);
      expect(launcher.killCount, 1, reason: 'the first process is interrupted');
    });

    test('empty text spawns nothing', () async {
      final launcher = FakeLauncher();
      await WindowsSapiSpeaker(launcher: launcher).speak('   ');
      expect(launcher.launchCount, 0);
    });
  });

  group('TtsService safety', () {
    test('refuses to touch the plugin on Windows', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final tts = TtsService();

      await tts.speak('不要调用插件');

      expect(tts.lastAttemptFailed, isTrue);
    });
  });
}
