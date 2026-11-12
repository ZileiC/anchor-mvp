import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/backend_tts_speaker.dart';
import 'package:anchor_app/services/speaker_factory.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/services/windows_sapi_speaker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real mp3 frame header (0xFF 0xFB = MPEG-1 Layer III) followed by padding:
/// enough to prove the exact bytes travel to disk, and invalid UTF-8 on purpose.
Uint8List fakeMp3() => Uint8List.fromList(<int>[
  0xFF,
  0xFB,
  0x90,
  0x64,
  0x00,
  0x00,
  0x00,
  0x00,
  0xFF,
  0xE2,
]);

/// ApiClient double: returns canned mp3 bytes, an error, or a delayed answer,
/// without ever opening a socket.
class FakeTtsApi extends ApiClient {
  FakeTtsApi({Uint8List? audio, this.error})
    : audio = audio ?? fakeMp3(),
      super(baseUrl: 'http://fake', transport: const UnavailableTransport());

  final Uint8List audio;

  /// When set, `ttsSpeech` throws this instead of returning audio.
  Object? error;

  /// When set, `ttsSpeech` waits for it (used to press Stop mid-download).
  Completer<Uint8List>? pending;

  int calls = 0;
  String? lastText;
  String? lastVoice;
  String? lastRate;

  @override
  Future<Uint8List> ttsSpeech({
    required String text,
    String? voice,
    String? rate,
  }) async {
    calls++;
    lastText = text;
    lastVoice = voice;
    lastRate = rate;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return audio;
  }
}

/// Launcher double: records the spawned command, and the fake child stays
/// alive until the test finishes it (so "playing" is observable).
class ControlledLauncher implements SpeechProcessLauncher {
  int launchCount = 0;
  int killCount = 0;
  String? lastExecutable;
  List<String>? lastArguments;
  bool failOnLaunch = false;
  final List<Completer<void>> _exits = <Completer<void>>[];

  @override
  Future<SpeechProcessHandle> launch(
    String executable,
    List<String> arguments,
  ) async {
    launchCount++;
    lastExecutable = executable;
    lastArguments = arguments;
    if (failOnLaunch) throw StateError('cannot start powershell.exe');
    final exit = Completer<void>();
    _exits.add(exit);
    return SpeechProcessHandle(
      kill: () {
        killCount++;
        if (!exit.isCompleted) exit.complete();
      },
      done: exit.future,
    );
  }

  /// The child finishes on its own (the mp3 ended).
  void finish(int index) {
    if (!_exits[index].isCompleted) _exits[index].complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('anchor_tts_test_');
  });

  tearDown(() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        if (!tempDirectory.existsSync()) return;
        tempDirectory.deleteSync(recursive: true);
        return;
      } catch (_) {
        // A file still being deleted must not fail the test.
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  List<File> tempFiles() =>
      tempDirectory.listSync().whereType<File>().toList(growable: false);

  /// Waits for real async work (file I/O happens on the IO thread, so a bare
  /// `pumpEventQueue()` can return before a delete has landed).
  Future<void> waitUntil(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition still false after 5 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Lets every pending cleanup finish before the directory goes away, so a
  /// half-done delete can never become a teardown race. Fails the test if a
  /// file is really left behind.
  Future<void> drainCleanup() => waitUntil(() => tempFiles().isEmpty);

  test('playback status follows preparation, launch and Stop', () async {
    final api = FakeTtsApi()..pending = Completer<Uint8List>();
    final launcher = ControlledLauncher();
    final speaker = BackendTtsSpeaker(
      api: api,
      launcher: launcher,
      fallback: SilentSpeaker(),
      tempDirectory: tempDirectory,
    );
    final pending = speaker.speak('Hello');
    await pumpEventQueue();
    expect(speaker.playback.value, SpeechPhase.preparing);
    api.pending!.complete(fakeMp3());
    await pending;
    expect(speaker.playback.value, SpeechPhase.playing);
    await speaker.stop();
    expect(speaker.playback.value, SpeechPhase.idle);
    await speaker.dispose();
  });

  group('Windows neural speaker', () {
    test(
      'fetches the mp3, writes it to a temp file and plays it with PowerShell',
      () async {
        final api = FakeTtsApi();
        final launcher = ControlledLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          tempDirectory: tempDirectory,
        );

        await speaker.speak('早上好，今天想聊点什么？');

        expect(api.calls, 1);
        expect(api.lastText, '早上好，今天想聊点什么？');

        final files = tempFiles();
        expect(files, hasLength(1));
        expect(files.single.path, endsWith('.mp3'));
        expect(
          files.single.readAsBytesSync(),
          api.audio,
          reason: 'the mp3 bytes must reach the file untouched',
        );

        expect(launcher.launchCount, 1);
        expect(launcher.lastExecutable, 'powershell.exe');
        final arguments = launcher.lastArguments!;
        expect(arguments, contains('-NoProfile'));
        expect(arguments, contains('-NonInteractive'));
        expect(arguments, contains('-ExecutionPolicy'));
        expect(arguments, contains('Bypass'));
        expect(arguments, contains('-Command'));

        final script = arguments.last;
        expect(script, contains('Add-Type -AssemblyName PresentationCore'));
        expect(script, contains('System.Windows.Media.MediaPlayer'));
        expect(
          script,
          contains(base64Encode(utf8.encode(files.single.path))),
          reason: 'the child must be told exactly which file to play',
        );
        expect(
          script,
          isNot(contains(files.single.path)),
          reason:
              'the path is base64, so no quote/CJK char can break the script',
        );
        expect(script, contains('NaturalDuration'));
        expect(script, contains(r'$player.Position'));
        expect(
          script,
          contains(r'$player.Position.TotalMilliseconds -lt $total'),
          reason: 'the child polls Position against the duration and exits',
        );

        expect(speaker.speaking, isTrue);
        expect(speaker.lastAttemptFailed, isFalse);

        await speaker.stop();
        await drainCleanup();
      },
    );

    test('slow keeps the server default pace, normal asks for +0%', () async {
      final api = FakeTtsApi();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: ControlledLauncher(),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('慢一点', slow: true);
      expect(
        api.lastRate,
        isNull,
        reason: 'null lets the backend use its slowed-for-seniors default',
      );

      await speaker.speak('正常语速', slow: false);
      expect(
        api.lastRate,
        '+0%',
        reason: 'edge-tts only accepts the signed form (-12% / +0%)',
      );

      await speaker.stop();
      await drainCleanup();
    });

    test('the temp file is deleted when playback ends by itself', () async {
      final api = FakeTtsApi();
      final launcher = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('这一句会自己播完');
      expect(tempFiles(), hasLength(1));

      launcher.finish(0);
      await waitUntil(() => !speaker.speaking && tempFiles().isEmpty);

      expect(tempFiles(), isEmpty, reason: 'the mp3 must not stay behind');
    });

    test('stop() kills the child and leaves no temp file', () async {
      final api = FakeTtsApi();
      final launcher = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('说一句话');
      expect(speaker.speaking, isTrue);
      expect(tempFiles(), hasLength(1));

      await speaker.stop();

      expect(launcher.killCount, 1, reason: 'Stop must silence the voice');
      expect(speaker.speaking, isFalse);
      await drainCleanup();
      expect(
        tempFiles(),
        isEmpty,
        reason: 'the mp3 goes away once the killed child has released it',
      );
    });

    test('a new utterance interrupts the previous one', () async {
      final api = FakeTtsApi();
      final launcher = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('第一句');
      final first = tempFiles().single.path;
      await speaker.speak('第二句');
      // The interrupted utterance's child is killed, so only the new file stays.
      await waitUntil(() => tempFiles().length == 1);

      expect(launcher.launchCount, 2);
      expect(launcher.killCount, 1);
      final remaining = tempFiles();
      expect(remaining, hasLength(1));
      expect(remaining.single.path, isNot(first));
      expect(api.lastText, '第二句');

      await speaker.stop();
      await drainCleanup();
    });

    test('empty text fetches nothing and spawns nothing', () async {
      final api = FakeTtsApi();
      final launcher = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('   ');

      expect(api.calls, 0);
      expect(launcher.launchCount, 0);
      expect(tempFiles(), isEmpty);
      expect(speaker.lastAttemptFailed, isFalse);
    });
  });

  group('fallback to the Windows device voice', () {
    test('a failing backend falls back to SAPI and says so', () async {
      final api = FakeTtsApi(
        error: const ApiException(
          code: 'provider_unavailable',
          message: 'TTS unavailable',
          statusCode: 503,
        ),
      );
      final primary = ControlledLauncher();
      final sapi = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        launcher: primary,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('后端不可用时也要说话');

      expect(api.calls, 1);
      expect(primary.launchCount, 0);
      expect(sapi.launchCount, 1, reason: 'the demo must still speak');
      final script = sapi.lastArguments!.last;
      expect(script, contains('Add-Type -AssemblyName System.Speech'));
      expect(script, contains(base64Encode(utf8.encode('后端不可用时也要说话'))));
      expect(
        speaker.lastAttemptFailed,
        isTrue,
        reason: 'the neural voice did not run, so this must not look healthy',
      );
      expect(speaker.speaking, isTrue, reason: 'the fallback is speaking now');
      expect(tempFiles(), isEmpty, reason: 'nothing was downloaded');
    });

    test('lastAttemptFailed recovers when the next utterance works', () async {
      final api = FakeTtsApi(
        error: const ApiException(code: 'offline', message: 'no backend'),
      );
      final speaker = BackendTtsSpeaker(
        api: api,
        fallback: WindowsSapiSpeaker(launcher: ControlledLauncher()),
        launcher: ControlledLauncher(),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('第一句');
      expect(speaker.lastAttemptFailed, isTrue);

      api.error = null;
      await speaker.speak('第二句');
      expect(speaker.lastAttemptFailed, isFalse);

      await speaker.stop();
      await drainCleanup();
    });

    test('an empty audio body is a failure, not silence', () async {
      final api = FakeTtsApi(audio: Uint8List(0));
      final sapi = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        launcher: ControlledLauncher(),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('空音频');

      expect(sapi.launchCount, 1);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(tempFiles(), isEmpty);
    });

    test('a launcher that cannot start PowerShell also falls back', () async {
      final api = FakeTtsApi();
      final primary = ControlledLauncher()..failOnLaunch = true;
      final sapi = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        launcher: primary,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('没有 PowerShell 也要说话');

      expect(primary.launchCount, 1);
      expect(sapi.launchCount, 1);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(
        tempFiles(),
        isEmpty,
        reason: 'the mp3 written for the failed launch is cleaned up',
      );
    });

    test(
      'Stop during the download stays silent instead of falling back',
      () async {
        final api = FakeTtsApi(error: const ApiCancelled());
        final primary = ControlledLauncher();
        final sapi = ControlledLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          fallback: WindowsSapiSpeaker(launcher: sapi),
          launcher: primary,
          tempDirectory: tempDirectory,
        );

        await speaker.speak('用户说了不要再说');

        expect(primary.launchCount, 0);
        expect(
          sapi.launchCount,
          0,
          reason: 'Stop must never be followed by speech of any kind',
        );
        expect(tempFiles(), isEmpty);
      },
    );

    test('audio that arrives after Stop is thrown away', () async {
      final api = FakeTtsApi()..pending = Completer<Uint8List>();
      final launcher = ControlledLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      final speaking = speaker.speak('晚到的音频');
      await pumpEventQueue();
      await speaker.stop();
      api.pending!.complete(api.audio);
      await speaking;

      expect(launcher.launchCount, 0);
      expect(launcher.killCount, 0);
      expect(tempFiles(), isEmpty);
      expect(speaker.speaking, isFalse);
    });
  });

  group('factory wiring', () {
    test('Windows gets the neural speaker with the app client and a SAPI '
        'fallback, never flutter_tts', () {
      final api = FakeTtsApi();
      final speaker = createSpeakerForTarget(SpeakerTarget.windows, api: api);

      expect(speaker, isA<BackendTtsSpeaker>());
      expect(speaker, isNot(isA<TtsService>()));
      final windows = speaker as BackendTtsSpeaker;
      expect(
        identical(windows.api, api),
        isTrue,
        reason: 'the speaker must use the client whose token login fills in',
      );
      expect(windows.fallback, isA<WindowsSapiSpeaker>());
    });

    test(
      'createSpeaker without a client still builds a usable Windows speaker',
      () {
        final speaker = createSpeakerForTarget(SpeakerTarget.windows);
        expect(speaker, isA<BackendTtsSpeaker>());
        expect(
          (speaker as BackendTtsSpeaker).fallback,
          isA<WindowsSapiSpeaker>(),
        );
      },
    );
  });
}
