import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anchor_app/services/android_tts_speaker.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/speaker.dart';
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

/// Audio-player double: keeps the native ExoPlayer out of the test, records the
/// file it was asked to play, and ends when the test tells it to.
///
/// It mirrors the real contract in [SpeechAudioPlayer]: the utterance is over
/// when the file ended, when the player failed, or when [stop] silenced it.
class FakePlayer implements SpeechAudioPlayer {
  FakePlayer({this.autoFinish = false, this.failOnStart = false});

  /// Finish as soon as the file starts (a sentence that plays to its end).
  final bool autoFinish;

  /// Throw from [start] (the platform refused the audio).
  bool failOnStart;

  int startCount = 0;
  int stopCount = 0;
  bool disposed = false;
  String? startedPath;

  final Completer<void> _finished = Completer<void>();

  @override
  Future<void> start(String filePath) async {
    startCount++;
    startedPath = filePath;
    if (failOnStart) throw StateError('no audio device');
    if (!File(filePath).existsSync()) {
      throw StateError('the mp3 must exist before it is played: $filePath');
    }
    if (autoFinish) finish();
  }

  /// The sentence reached its end (or dies with [error] mid-way).
  void finish({Object? error}) {
    if (_finished.isCompleted) return;
    if (error == null) {
      _finished.complete();
    } else {
      _finished.completeError(error);
    }
  }

  @override
  Future<void> get finished => _finished.future;

  @override
  Future<void> stop() async {
    stopCount++;
    finish();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Factory double: hands out [FakePlayer]s and keeps them for assertions.
class FakePlayerFactory implements SpeechAudioPlayerFactory {
  FakePlayerFactory({this.autoFinish = false, this.failOnStart = false});

  final bool autoFinish;
  final bool failOnStart;
  final List<FakePlayer> players = <FakePlayer>[];

  FakePlayer get last => players.last;

  @override
  SpeechAudioPlayer create() {
    final player = FakePlayer(
      autoFinish: autoFinish,
      failOnStart: failOnStart,
    );
    players.add(player);
    return player;
  }
}

/// The device voice (the production fallback is `TtsService`, which a test
/// cannot drive), recorded so the fallback can be asserted.
class RecordingSpeaker implements Speaker {
  final List<String> spoken = <String>[];
  bool disposed = false;

  @override
  bool get lastAttemptFailed => false;

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('anchor_android_tts_');
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

  Future<void> drainCleanup() => waitUntil(() => tempFiles().isEmpty);

  AndroidTtsSpeaker buildSpeaker({
    FakeTtsApi? api,
    FakePlayerFactory? players,
    RecordingSpeaker? fallback,
    Duration? playbackTimeout,
  }) {
    return AndroidTtsSpeaker(
      api:
          api ??
          FakeTtsApi(),
      fallback: fallback ?? RecordingSpeaker(),
      playerFactory: players ?? FakePlayerFactory(),
      tempDirectory: tempDirectory,
      playbackTimeout: playbackTimeout ?? const Duration(minutes: 5),
    );
  }

  group('Android neural speaker', () {
    test('fetches the mp3, writes it to a temp file and plays that file', () async {
      final api = FakeTtsApi();
      final players = FakePlayerFactory();
      final speaker = buildSpeaker(api: api, players: players);

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

      expect(players.players, hasLength(1));
      expect(players.last.startCount, 1);
      expect(
        players.last.startedPath,
        files.single.path,
        reason: 'the player must be handed exactly that file',
      );
      expect(speaker.speaking, isTrue);
      expect(speaker.lastAttemptFailed, isFalse);

      players.last.finish();
      await drainCleanup();
      expect(speaker.speaking, isFalse);
    });

    test('the temp file is deleted when playback ends by itself', () async {
      final players = FakePlayerFactory(autoFinish: true);
      final speaker = buildSpeaker(players: players);

      await speaker.speak('这一句会自己播完');
      await drainCleanup();

      expect(tempFiles(), isEmpty, reason: 'the mp3 must not stay behind');
      expect(players.last.disposed, isTrue);
      expect(speaker.speaking, isFalse);
    });

    test('slow keeps the server default pace, normal asks for +0%', () async {
      final api = FakeTtsApi();
      final players = FakePlayerFactory(autoFinish: true);
      final speaker = buildSpeaker(api: api, players: players);

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

      await drainCleanup();
    });

    test('stop() silences immediately and leaves no temp file', () async {
      final players = FakePlayerFactory();
      final speaker = buildSpeaker(players: players);

      await speaker.speak('说一句话');
      expect(speaker.speaking, isTrue);
      expect(tempFiles(), hasLength(1));

      await speaker.stop();

      expect(
        players.last.stopCount,
        1,
        reason: 'Stop must silence the voice at once',
      );
      expect(speaker.speaking, isFalse);
      await drainCleanup();
      expect(tempFiles(), isEmpty, reason: 'the mp3 must not stay behind');
      expect(
        speaker.lastAttemptFailed,
        isFalse,
        reason: 'a requested stop is not a playback failure',
      );
    });

    test('a new utterance interrupts the previous one', () async {
      final api = FakeTtsApi();
      final players = FakePlayerFactory();
      final speaker = buildSpeaker(api: api, players: players);

      await speaker.speak('第一句');
      final first = tempFiles().single.path;
      await speaker.speak('第二句');
      await waitUntil(() => tempFiles().length == 1);

      expect(players.players, hasLength(2));
      expect(players.players.first.stopCount, 1);
      expect(players.players.first.disposed, isTrue);
      final remaining = tempFiles();
      expect(remaining, hasLength(1));
      expect(remaining.single.path, isNot(first));
      expect(api.lastText, '第二句');
      expect(speaker.lastAttemptFailed, isFalse);

      await speaker.stop();
      await drainCleanup();
    });

    test('empty text fetches nothing and plays nothing', () async {
      final api = FakeTtsApi();
      final players = FakePlayerFactory();
      final speaker = buildSpeaker(api: api, players: players);

      await speaker.speak('   ');

      expect(api.calls, 0);
      expect(players.players, isEmpty);
      expect(tempFiles(), isEmpty);
      expect(speaker.lastAttemptFailed, isFalse);
    });

    test('dispose() removes the mp3 and releases the player', () async {
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(players: players, fallback: fallback);

      await speaker.speak('说完这句就退出');
      await speaker.dispose();

      expect(tempFiles(), isEmpty, reason: 'no mp3 may outlive the app');
      expect(players.last.disposed, isTrue);
      expect(fallback.disposed, isTrue);
    });
  });

  group('fallback to the device voice', () {
    test('a failing backend falls back and says so', () async {
      final api = FakeTtsApi(
        error: const ApiException(
          code: 'provider_unavailable',
          message: 'TTS unavailable',
          statusCode: 503,
        ),
      );
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(api: api, players: players, fallback: fallback);

      await speaker.speak('后端不可用时也要说话');

      expect(api.calls, 1);
      expect(players.players, isEmpty, reason: 'nothing to play');
      expect(
        fallback.spoken,
        ['后端不可用时也要说话'],
        reason: 'the demo must still speak',
      );
      expect(
        speaker.lastAttemptFailed,
        isTrue,
        reason: 'the neural voice did not run, so this must not look healthy',
      );
      expect(tempFiles(), isEmpty, reason: 'nothing was downloaded');
      expect(speaker.speaking, isFalse);
    });

    test('lastAttemptFailed recovers when the next utterance works', () async {
      final api = FakeTtsApi(
        error: const ApiException(code: 'offline', message: 'no backend'),
      );
      final players = FakePlayerFactory(autoFinish: true);
      final speaker = buildSpeaker(api: api, players: players);

      await speaker.speak('第一句');
      expect(speaker.lastAttemptFailed, isTrue);

      api.error = null;
      await speaker.speak('第二句');
      expect(speaker.lastAttemptFailed, isFalse);

      await drainCleanup();
    });

    test('an empty audio body is a failure, not silence', () async {
      final api = FakeTtsApi(audio: Uint8List(0));
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(api: api, players: players, fallback: fallback);

      await speaker.speak('空音频');

      expect(players.players, isEmpty);
      expect(fallback.spoken, ['空音频']);
      expect(speaker.lastAttemptFailed, isTrue);
      expect(tempFiles(), isEmpty);
    });

    test('a player that cannot start the file falls back and cleans up', () async {
      final api = FakeTtsApi();
      final players = FakePlayerFactory(failOnStart: true);
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(api: api, players: players, fallback: fallback);

      await speaker.speak('没有播放器也要说话');

      expect(players.players, hasLength(1));
      expect(fallback.spoken, ['没有播放器也要说话']);
      expect(speaker.lastAttemptFailed, isTrue);
      await drainCleanup();
      expect(
        tempFiles(),
        isEmpty,
        reason: 'the mp3 written for the failed player is cleaned up',
      );
    });

    test('playback that dies mid-sentence falls back', () async {
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(players: players, fallback: fallback);

      await speaker.speak('播到一半失败了');
      players.last.finish(error: StateError('decoder died'));
      await waitUntil(() => fallback.spoken.isNotEmpty);

      expect(fallback.spoken, ['播到一半失败了']);
      expect(speaker.lastAttemptFailed, isTrue);
      await drainCleanup();
      expect(speaker.speaking, isFalse);
    });

    test(
      'a player that never reports the end is unconfirmed, never re-spoken',
      () async {
        final players = FakePlayerFactory();
        final fallback = RecordingSpeaker();
        final speaker = buildSpeaker(
          players: players,
          fallback: fallback,
          playbackTimeout: const Duration(milliseconds: 50),
        );

        await speaker.speak('这一句不会回报结束');
        await waitUntil(() => tempFiles().isEmpty);

        expect(
          fallback.spoken,
          isEmpty,
          reason: 'the audio probably played; saying it again is worse',
        );
        expect(
          speaker.lastAttemptFailed,
          isTrue,
          reason: 'an unconfirmed utterance must not be reported as healthy',
        );
        expect(players.last.disposed, isTrue);
        expect(speaker.speaking, isFalse);
      },
    );

    test('Stop during the download stays silent instead of falling back', () async {
      final api = FakeTtsApi()..pending = Completer<Uint8List>();
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(api: api, players: players, fallback: fallback);

      final speaking = speaker.speak('用户说了不要再说');
      await pumpEventQueue();
      await speaker.stop();
      api.pending!.complete(api.audio);
      await speaking;

      expect(players.players, isEmpty);
      expect(
        fallback.spoken,
        isEmpty,
        reason: 'Stop must never be followed by speech of any kind',
      );
      expect(tempFiles(), isEmpty);
      expect(speaker.lastAttemptFailed, isFalse);
    });

    test('audio that arrives after Stop is thrown away', () async {
      final api = FakeTtsApi(error: const ApiCancelled());
      final players = FakePlayerFactory();
      final fallback = RecordingSpeaker();
      final speaker = buildSpeaker(api: api, players: players, fallback: fallback);

      await speaker.speak('用户说了不要再说');

      expect(players.players, isEmpty);
      expect(fallback.spoken, isEmpty);
      expect(tempFiles(), isEmpty);
    });
  });
}
