import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/backend_tts_speaker.dart';
import 'package:anchor_app/services/speaker_factory.dart';
import 'package:anchor_app/services/tts_playback_session.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/services/windows_sapi_speaker.dart';
import 'package:flutter/foundation.dart';
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

/// One fetch the fake API served, with the wall-clock instants the pipeline
/// test needs to prove "sentence 2 is fetched while sentence 1 plays".
class FetchRecord {
  FetchRecord(this.text) : startedAt = DateTime.now();

  final String text;
  final DateTime startedAt;
  DateTime? finishedAt;
}

/// ApiClient double: canned mp3 bytes, errors, delays and a gate that holds the
/// N-th fetch, all without opening a socket.
class FakeTtsApi extends ApiClient {
  FakeTtsApi({Uint8List? audio, this.error})
    : audio = audio ?? fakeMp3(),
      super(baseUrl: 'http://fake', transport: const UnavailableTransport());

  /// Bytes returned for every successful fetch.
  Uint8List audio;

  /// When set, every fetch throws this.
  Object? error;

  /// Per-text failures, so a *later* sentence can fail while the first works.
  final Map<String, Object> errorsByText = <String, Object>{};

  /// Added latency before a fetch answers (pipelining tests).
  Duration delay = Duration.zero;

  /// 1-based call number from which fetches wait for [releaseHolds]. Used to
  /// press Stop while a fetch is genuinely in flight.
  int? holdFromCall;

  final List<Completer<void>> holds = <Completer<void>>[];
  final List<FetchRecord> fetches = <FetchRecord>[];

  int get calls => fetches.length;
  String? lastText;
  String? lastVoice;
  String? lastRate;

  void releaseHolds() {
    for (final hold in holds) {
      if (!hold.isCompleted) hold.complete();
    }
    holds.clear();
  }

  @override
  Future<Uint8List> ttsSpeech({
    required String text,
    String? voice,
    String? rate,
  }) async {
    final record = FetchRecord(text);
    fetches.add(record);
    lastText = text;
    lastVoice = voice;
    lastRate = rate;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final holdFrom = holdFromCall;
    if (holdFrom != null && fetches.length >= holdFrom) {
      final hold = Completer<void>();
      holds.add(hold);
      await hold.future;
    }
    final byText = errorsByText[text];
    if (byText != null) throw byText;
    final failure = error;
    if (failure != null) throw failure;
    record.finishedAt = DateTime.now();
    return audio;
  }
}

/// One fake long-lived player child: records what was queued and when, and
/// lets the test decide when each sentence finishes playing.
class FakePlaybackSession implements TtsPlaybackSession {
  final List<String> paths = <String>[];
  final List<DateTime> playStartedAt = <DateTime>[];
  final List<DateTime> finishedAt = <DateTime>[];
  final List<Completer<void>> _played = <Completer<void>>[];
  final Completer<void> _done = Completer<void>();
  final Completer<bool> _started = Completer<bool>();

  bool _running = true;
  bool _eof = false;
  int killCount = 0;
  int finishCount = 0;
  int playsAfterKill = 0;

  @override
  bool get running => _running;

  @override
  Future<bool> get started => _started.future;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> play(String path) {
    if (!_running) {
      playsAfterKill++;
      return Future<void>.value();
    }
    paths.add(path);
    playStartedAt.add(DateTime.now());
    final completer = Completer<void>();
    _played.add(completer);
    if (!_started.isCompleted) _started.complete(true);
    return completer.future;
  }

  @override
  Future<void> finish() async {
    finishCount++;
    _eof = true;
    _maybeExit();
  }

  @override
  void kill() {
    if (!_running) return;
    killCount++;
    _end();
  }

  /// Simulates the child finishing the playback of queue item [index].
  void finishItem(int index) {
    final completer = _played[index];
    if (!completer.isCompleted) {
      completer.complete();
      finishedAt.add(DateTime.now());
    }
    _maybeExit();
  }

  bool get allPlayed => _played.every((Completer<void> c) => c.isCompleted);

  void _maybeExit() {
    if (!_running || !_eof || !allPlayed) return;
    _end();
  }

  void _end() {
    if (!_running) return;
    _running = false;
    if (!_started.isCompleted) _started.complete(false);
    for (final completer in _played) {
      if (!completer.isCompleted) completer.complete();
    }
    if (!_done.isCompleted) _done.complete();
  }
}

/// Launcher double for the Windows SAPI fallback (a one-shot child process).
class FakeSapiLauncher implements SpeechProcessLauncher {
  int launchCount = 0;
  int killCount = 0;
  List<String>? lastArguments;
  final List<Completer<void>> _exits = <Completer<void>>[];

  @override
  Future<SpeechProcessHandle> launch(
    String executable,
    List<String> arguments,
  ) async {
    launchCount++;
    lastArguments = arguments;
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
}

/// Launcher double: hands out one [FakePlaybackSession] per utterance and
/// records the exact powershell command line.
class FakePlaybackLauncher implements TtsPlaybackLauncher {
  int startCount = 0;
  bool failOnStart = false;
  String? lastExecutable;
  List<String>? lastArguments;
  final List<FakePlaybackSession> sessions = <FakePlaybackSession>[];

  @override
  Future<TtsPlaybackSession> start(
    String executable,
    List<String> arguments,
  ) async {
    startCount++;
    lastExecutable = executable;
    lastArguments = arguments;
    if (failOnStart) throw StateError('cannot start powershell.exe');
    final session = FakePlaybackSession();
    sessions.add(session);
    return session;
  }

  FakePlaybackSession get session => sessions.last;

  FakePlaybackSession sessionAt(int index) => sessions[index];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('anchor_tts_test_');
  });

  tearDown(() async {
    // Every test must leave %TEMP% clean. Give a per-item delete that was
    // still in flight a moment, then fail loudly instead of hiding a leak
    // behind the directory teardown.
    List<File> leftovers() =>
        tempDirectory.listSync().whereType<File>().toList(growable: false);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (leftovers().isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(leftovers(), isEmpty, reason: 'this test leaked a temp mp3 behind');
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
  Future<void> waitUntil(bool Function() condition, {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'condition still false after 5 s${reason == null ? '' : ': $reason'}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Lets every pending cleanup finish before the directory goes away, so a
  /// half-done delete can never become a teardown race. Fails the test if a
  /// file is really left behind.
  Future<void> drainCleanup() => waitUntil(
    () => tempFiles().isEmpty,
    reason: 'a temp mp3 was left behind',
  );

  /// Plays the whole queue the way the real child would: item by item, in
  /// order, until EOF has been read and everything queued has finished.
  Future<void> playEverything(FakePlaybackSession player) async {
    var next = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!player.running) return;
      if (next < player.paths.length) {
        player.finishItem(next);
        next++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('the fake player never finished its queue');
  }

  test('sentence splitting', () {
    expect(
      BackendTtsSpeaker.splitSentences('第一句话已经足够长了。第二句话也已经足够长了！'),
      <String>['第一句话已经足够长了。', '第二句话也已经足够长了！'],
      reason: 'each terminator stays on the sentence it closes',
    );
    expect(BackendTtsSpeaker.splitSentences('好。今天想出去走走吗？'), <String>[
      '好。今天想出去走走吗？',
    ], reason: 'a 2-character fragment must not become its own TTS request');
    expect(BackendTtsSpeaker.splitSentences('今天天气非常好。好的。'), <String>[
      '今天天气非常好。好的。',
    ], reason: 'a short last fragment is merged backwards');
    expect(BackendTtsSpeaker.splitSentences('这是一段没有句号的文字'), <String>[
      '这是一段没有句号的文字',
    ], reason: 'no punctuation means one sentence, never a word-by-word split');
    expect(BackendTtsSpeaker.splitSentences('第一句话在这里。\n第二句话在这里。'), <String>[
      '第一句话在这里。',
      '第二句话在这里。',
    ], reason: 'newlines end a sentence and are not spoken');
    expect(
      BackendTtsSpeaker.splitSentences('第一句话已经足够长了。\n\n   \n第二句话也已经足够长了。'),
      <String>['第一句话已经足够长了。', '第二句话也已经足够长了。'],
      reason: 'empty fragments are dropped',
    );
    expect(BackendTtsSpeaker.splitSentences('   '), isEmpty);
    expect(BackendTtsSpeaker.splitSentences(''), isEmpty);
  });

  group('one long-lived player for the whole utterance', () {
    test('plays a sentence through the stdin queue without embedding paths '
        'in the command line', () async {
      final api = FakeTtsApi();
      final launcher = FakePlaybackLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('早上好，今天想聊点什么？');

      expect(api.calls, 1);
      expect(api.lastText, '早上好，今天想聊点什么？');
      expect(launcher.startCount, 1, reason: 'one child for the utterance');
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
        contains('ReadLine'),
        reason: 'the queue comes from stdin',
      );
      expect(
        script,
        contains("'$ttsPlayerEndMarker'"),
        reason: 'EOF ends the queue',
      );
      expect(script, contains('FromBase64String'));
      expect(script, contains('NaturalDuration'));
      expect(
        script,
        contains(r'$player.Position'),
        reason: 'polls the position',
      );
      expect(
        script,
        contains("'$ttsPlayerPlayMarker'"),
        reason: 'start ack must match the Dart parser',
      );
      expect(
        script,
        contains("'$ttsPlayerDoneMarker'"),
        reason: 'per-item ack must match the Dart parser',
      );
      expect(script, contains('exit 0'));
      expect(
        script,
        isNot(contains('"')),
        reason: 'double quotes would have to survive -Command escaping',
      );
      expect(
        script.runes.every((int rune) => rune < 0x80),
        isTrue,
        reason: 'only ASCII travels in -Command',
      );

      final player = launcher.session;
      expect(player.paths, hasLength(1));
      final file = tempFiles().single;
      expect(player.paths.single, file.path);
      expect(
        script,
        isNot(contains(file.path)),
        reason: 'the mp3 path is sent over stdin, never in the script',
      );
      expect(
        script,
        isNot(contains(base64Encode(utf8.encode(file.path)))),
        reason: 'the path is not baked into the command line either',
      );
      expect(file.readAsBytesSync(), api.audio);
      expect(speaker.speaking, isTrue);
      expect(speaker.lastAttemptFailed, isFalse);

      player.finishItem(0);
      await waitUntil(() => !speaker.speaking);
      await drainCleanup();
    });

    test(
      'fetches the next sentence while the previous one is still playing',
      () async {
        const text = '第一句话已经足够长了。第二句话也已经足够长了！第三句话同样非常足够长？';
        final api = FakeTtsApi()..delay = const Duration(milliseconds: 30);
        final launcher = FakePlaybackLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          tempDirectory: tempDirectory,
        );

        await speaker.speak(text);
        final player = launcher.session;
        // Sentence 2 is fetched and queued while sentence 1 is still playing.
        await waitUntil(() => player.paths.length >= 2);
        expect(
          player.finishedAt,
          isEmpty,
          reason: 'a fetch must not wait for the previous playback to end',
        );
        // Both queued files are on disk, each still needed.
        expect(tempFiles(), hasLength(2));
        final secondFetchStartedAt = api.fetches[1].startedAt;
        player.finishItem(0);
        expect(
          secondFetchStartedAt.isBefore(player.finishedAt.single),
          isTrue,
          reason: 'fetch 2 began before playback 1 finished',
        );
        expect(
          launcher.startCount,
          1,
          reason: 'the child is reused per sentence',
        );
        expect(api.calls, greaterThanOrEqualTo(2));

        await playEverything(player);
        await drainCleanup();
        expect(player.paths, hasLength(3));
        expect(tempFiles(), isEmpty);
      },
    );

    test(
      'deletes each mp3 as soon as its sentence has finished playing',
      () async {
        const text = '第一句话已经足够长了。第二句话也已经足够长了。';
        final api = FakeTtsApi();
        final launcher = FakePlaybackLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          tempDirectory: tempDirectory,
        );

        await speaker.speak(text);
        final player = launcher.session;
        await waitUntil(() => player.paths.length == 2);
        expect(tempFiles(), hasLength(2));

        player.finishItem(0);
        await waitUntil(() => tempFiles().length == 1);
        expect(
          player.running,
          isTrue,
          reason: 'sentence 2 still needs its file; the child is still playing',
        );

        player.finishItem(1);
        await waitUntil(() => !player.running);
        await drainCleanup();
        expect(tempFiles(), isEmpty);
      },
    );

    test('logs time to first audio and per-sentence fetch times', () async {
      const text = '第一句话已经足够长了。第二句话也已经足够长了。';
      final api = FakeTtsApi();
      final launcher = FakePlaybackLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      try {
        await speaker.speak(text);
        await playEverything(launcher.session);
        await waitUntil(() => !speaker.speaking);
        await drainCleanup();
      } finally {
        debugPrint = original;
      }

      expect(
        lines.any((String l) => l.contains('TTS: first sentence fetched in')),
        isTrue,
      );
      expect(
        lines.any((String l) => l.contains('TTS: first audio started')),
        isTrue,
      );
      expect(
        lines.any((String l) => l.contains('TTS: sentence 2/2 fetched in')),
        isTrue,
      );
    });
  });

  group('Stop and failures', () {
    test(
      'Stop mid-utterance kills the child and never queues a late sentence',
      () async {
        const text = '第一句话已经足够长了。第二句话也已经足够长了！第三句话同样非常足够长？';
        final api = FakeTtsApi()..holdFromCall = 2;
        final launcher = FakePlaybackLauncher();
        final sapi = FakeSapiLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          fallback: WindowsSapiSpeaker(launcher: sapi),
          tempDirectory: tempDirectory,
        );

        await speaker.speak(text);
        final player = launcher.session;
        await waitUntil(() => api.calls >= 2 && api.holds.isNotEmpty);

        expect(
          player.paths,
          hasLength(1),
          reason: 'sentence 2 is still in flight',
        );
        await speaker.stop();
        expect(player.killCount, 1, reason: 'Stop must silence the voice');
        expect(speaker.speaking, isFalse);

        api.releaseHolds(); // The late sentence 2 audio arrives after Stop.
        await waitUntil(() => !player.running);
        // Give the discarded fetch time to be processed.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(player.paths, hasLength(1), reason: 'no path after Stop');
        expect(player.playsAfterKill, 0, reason: 'never queue after the kill');
        expect(
          sapi.launchCount,
          0,
          reason: 'Stop must never be followed by speech',
        );
        await drainCleanup();
        expect(tempFiles(), isEmpty);
      },
    );

    test(
      'a first-sentence failure falls back to SAPI once with the full text',
      () async {
        const text = '第一句在这里。第二句也在这里。';
        final api = FakeTtsApi(
          error: const ApiException(
            code: 'provider_unavailable',
            message: 'TTS unavailable',
            statusCode: 503,
          ),
        );
        final launcher = FakePlaybackLauncher();
        final sapi = FakeSapiLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          fallback: WindowsSapiSpeaker(launcher: sapi),
          tempDirectory: tempDirectory,
        );

        await speaker.speak(text);

        expect(api.calls, 1, reason: 'only sentence 1 was attempted');
        expect(launcher.startCount, 1, reason: 'the player was started early');
        expect(launcher.session.killCount, 1, reason: 'and killed on fallback');
        expect(launcher.session.paths, isEmpty);
        expect(sapi.launchCount, 1, reason: 'the demo must still speak');
        final script = sapi.lastArguments!.last;
        expect(script, contains('Add-Type -AssemblyName System.Speech'));
        expect(
          script,
          contains(base64Encode(utf8.encode(text))),
          reason: 'SAPI gets the whole reply in one call, not one sentence',
        );
        expect(speaker.lastAttemptFailed, isTrue);
        expect(
          speaker.speaking,
          isTrue,
          reason: 'the fallback is speaking now',
        );
        expect(tempFiles(), isEmpty);

        await speaker.stop();
      },
    );

    test('a later-sentence failure does not fall back and finishes what is '
        'queued', () async {
      const first = '第一句话已经足够长了。';
      const second = '第二句话也已经足够长了。';
      const third = '第三句话同样非常足够长。';
      final api = FakeTtsApi()
        ..errorsByText[second] = const ApiException(
          code: 'provider_unavailable',
          message: 'TTS unavailable',
        );
      final launcher = FakePlaybackLauncher();
      final sapi = FakeSapiLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('$first$second$third');
      final player = launcher.session;
      await waitUntil(() => player.finishCount == 1);
      expect(player.paths, hasLength(1), reason: 'sentence 2 was never queued');
      expect(api.calls, 2, reason: 'sentence 3 is never attempted');
      expect(
        sapi.launchCount,
        0,
        reason: 'no fallback in the middle of a reply',
      );
      expect(
        speaker.lastAttemptFailed,
        isTrue,
        reason: 'part of the reply was never spoken, so this is not healthy',
      );

      player.finishItem(0);
      await waitUntil(() => !player.running);
      await drainCleanup();
      expect(tempFiles(), isEmpty);
    });

    test('an empty audio body is a failure, not silence', () async {
      final api = FakeTtsApi(audio: Uint8List(0));
      final launcher = FakePlaybackLauncher();
      final sapi = FakeSapiLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('空音频');

      expect(sapi.launchCount, 1);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(launcher.session.paths, isEmpty);
      expect(tempFiles(), isEmpty);
    });

    test('a launcher that cannot start PowerShell also falls back', () async {
      final api = FakeTtsApi();
      final launcher = FakePlaybackLauncher()..failOnStart = true;
      final sapi = FakeSapiLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        fallback: WindowsSapiSpeaker(launcher: sapi),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('没有 PowerShell 也要说话');

      expect(launcher.startCount, 1);
      expect(sapi.launchCount, 1);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(tempFiles(), isEmpty);
    });

    test(
      'Stop during the first fetch stays silent instead of falling back',
      () async {
        final api = FakeTtsApi()..holdFromCall = 1;
        final launcher = FakePlaybackLauncher();
        final sapi = FakeSapiLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          fallback: WindowsSapiSpeaker(launcher: sapi),
          tempDirectory: tempDirectory,
        );

        final speaking = speaker.speak('用户说了不要再说');
        await waitUntil(() => api.holds.isNotEmpty);
        expect(
          launcher.startCount,
          1,
          reason: 'the player is spawned in parallel',
        );
        await speaker.stop();
        expect(
          launcher.session.killCount,
          1,
          reason: 'Stop must kill the player even before its first sentence',
        );
        expect(speaker.speaking, isFalse);
        api.releaseHolds();
        await speaking;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          sapi.launchCount,
          0,
          reason: 'Stop must never be followed by speech of any kind',
        );
        expect(launcher.session.paths, isEmpty);
        expect(tempFiles(), isEmpty);
        expect(speaker.lastAttemptFailed, isFalse);
      },
    );

    test(
      'a new utterance interrupts the previous one and cleans it up',
      () async {
        final api = FakeTtsApi();
        final launcher = FakePlaybackLauncher();
        final speaker = BackendTtsSpeaker(
          api: api,
          launcher: launcher,
          tempDirectory: tempDirectory,
        );

        await speaker.speak('第一句话足够长了。');
        final firstPlayer = launcher.sessionAt(0);
        expect(firstPlayer.paths, hasLength(1));
        expect(tempFiles(), hasLength(1));

        await speaker.speak('第二句话也足够长了。');
        expect(launcher.startCount, 2);
        expect(
          firstPlayer.killCount,
          1,
          reason: 'the first child is interrupted',
        );
        expect(launcher.sessionAt(1).paths, hasLength(1));

        await playEverything(launcher.sessionAt(1));
        await drainCleanup();
        expect(tempFiles(), isEmpty);
      },
    );

    test('slow keeps the server default pace, normal asks for +0%', () async {
      final api = FakeTtsApi();
      final launcher = FakePlaybackLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
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

    test('empty text fetches nothing and spawns nothing', () async {
      final api = FakeTtsApi();
      final launcher = FakePlaybackLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        tempDirectory: tempDirectory,
      );

      await speaker.speak('   ');

      expect(api.calls, 0);
      expect(launcher.startCount, 0);
      expect(tempFiles(), isEmpty);
      expect(speaker.lastAttemptFailed, isFalse);
    });

    test('lastAttemptFailed recovers when the next utterance works', () async {
      final api = FakeTtsApi(
        error: const ApiException(code: 'offline', message: 'no backend'),
      );
      final launcher = FakePlaybackLauncher();
      final speaker = BackendTtsSpeaker(
        api: api,
        launcher: launcher,
        fallback: WindowsSapiSpeaker(launcher: FakeSapiLauncher()),
        tempDirectory: tempDirectory,
      );

      await speaker.speak('第一句话失败');
      expect(speaker.lastAttemptFailed, isTrue);

      api.error = null;
      await speaker.speak('第二句话成功');
      expect(speaker.lastAttemptFailed, isFalse);

      await speaker.stop();
      await drainCleanup();
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
      expect(windows.launcher, isA<WindowsTtsPlaybackLauncher>());
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
