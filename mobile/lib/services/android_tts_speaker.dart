import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart';
// `tts_service.dart` re-exports `speaker.dart`, so the seam comes from there.
import 'tts_service.dart';

/// One mp3 player, exactly as this speaker needs it: start a file, learn when
/// the utterance is over, silence it now.
///
/// This is a seam, not a wrapper for its own sake. The real player talks to a
/// native media service over a platform channel, which a unit test cannot host,
/// so [AndroidTtsSpeaker] is tested against a double while
/// [JustAudioSpeechPlayer] stays a thin adapter that only a real device runs.
abstract class SpeechAudioPlayer {
  /// Loads [filePath] and starts playing it; returns once playback has begun.
  ///
  /// Throws when the platform refuses the audio (unplayable file, no audio
  /// device): the caller then falls back to the device voice instead of
  /// pretending the sentence was spoken.
  Future<void> start(String filePath);

  /// Completes when this utterance is over.
  ///
  /// It completes **normally** when the file played to its end and when [stop]
  /// silenced it early (a stop is the user's wish, not a playback error), and
  /// completes with an **error** only when the platform failed to play it.
  Future<void> get finished;

  /// Silences the voice at once — Stop must not wait for anything. It also
  /// completes [finished], because this player is never reused after a stop.
  Future<void> stop();

  /// Releases the native player. Call after [finished] or [stop].
  Future<void> dispose();
}

/// Creates one player per utterance. A fresh player cannot inherit the stopped
/// state of the previous one, which is exactly what a quick second reply needs.
abstract class SpeechAudioPlayerFactory {
  SpeechAudioPlayer create();
}

/// The real factory: `just_audio`, which is ExoPlayer (androidx.media3) on
/// Android and declares **no Windows implementation at all**, so adding it
/// leaves the Windows build's plugin set unchanged.
class JustAudioSpeechPlayerFactory implements SpeechAudioPlayerFactory {
  const JustAudioSpeechPlayerFactory();

  @override
  SpeechAudioPlayer create() => JustAudioSpeechPlayer();
}

/// `just_audio` adapter. One instance per utterance, disposed right after.
///
/// Completion is taken from [AudioPlayer.processingStateStream], never from
/// `play()`: on Android `play()` resolves when playback *begins*, so awaiting
/// it would return before the senior hears anything. The state stream is
/// subscribed in the constructor, so the `completed` event cannot arrive
/// before anyone is listening.
class JustAudioSpeechPlayer implements SpeechAudioPlayer {
  JustAudioSpeechPlayer({
    AudioPlayer? player,
    this.loadTimeout = const Duration(seconds: 20),
  }) : _player = player ?? AudioPlayer() {
    // An error that arrives after the speaker gave up on this utterance (the
    // timeout) would otherwise surface as an unhandled async error.
    _finished.future.ignore();
    _stateSubscription = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _finish();
    }, onError: (Object error) => _finish(error));
  }

  final AudioPlayer _player;

  /// How long the mp3 may take to load before the load counts as failed. A
  /// local file of one spoken sentence needs a fraction of a second; anywhere
  /// near this bound means the platform is stuck, and waiting in silence is
  /// worse than the device-voice fallback.
  final Duration loadTimeout;

  final Completer<void> _finished = Completer<void>();
  late final StreamSubscription<ProcessingState> _stateSubscription;

  @override
  Future<void> get finished => _finished.future;

  @override
  Future<void> start(String filePath) async {
    await _player.setFilePath(filePath).timeout(loadTimeout);
    // Not awaited: its resolution means "playback started", and an error (for
    // instance a refused audio session) must reach `finished` instead of
    // escaping as an unhandled async error.
    unawaited(
      _player.play().then<void>(
        (_) {},
        onError: (Object error) => _finish(error),
      ),
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (error) {
      debugPrint('Android TTS stop failed: $error');
    } finally {
      _finish();
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _stateSubscription.cancel();
    } catch (error) {
      debugPrint('Android TTS stream cleanup failed: $error');
    }
    try {
      await _player.dispose();
    } catch (error) {
      debugPrint('Android TTS player dispose failed: $error');
    }
  }

  void _finish([Object? error]) {
    if (_finished.isCompleted) return;
    if (error == null) {
      _finished.complete();
    } else {
      _finished.completeError(error);
    }
  }
}

/// Android speech with the **backend's neural voice**, with the same semantics
/// as the Windows speaker: `POST /api/v1/tts` for the mp3 → write it to a temp
/// file → play that file to its end with a real audio player → delete the file.
/// [stop] silences immediately.
///
/// [TtsService] (the device voice, `flutter_tts`) stays as the audible
/// fallback: when the backend cannot deliver audio or the platform refuses it,
/// the demo still speaks, and [lastAttemptFailed] then reports `true`, so
/// nothing claims the neural voice worked when it did not.
///
/// The public shape mirrors the Windows speaker on purpose (`api`, `fallback`,
/// `voice`, `speaking`, `lastAttemptFailed`), so the platform factory and its
/// tests treat both implementations the same way.
class AndroidTtsSpeaker implements Speaker {
  AndroidTtsSpeaker({
    required this.api,
    Speaker? fallback,
    SpeechAudioPlayerFactory? playerFactory,
    Directory? tempDirectory,
    this.voice,
    this.playbackTimeout = const Duration(minutes: 5),
  }) : fallback = fallback ?? TtsService(),
       playerFactory = playerFactory ?? const JustAudioSpeechPlayerFactory(),
       tempDirectory = tempDirectory ?? Directory.systemTemp;

  /// The same client the app uses for every other call, so the bearer token
  /// `AppState.signInDemo` stores on it is what authorises `POST /tts`. Neither
  /// the base URL nor the token is hardcoded here: on a phone the backend is a
  /// LAN address that comes from `--dart-define=ANCHOR_API_BASE`.
  final ApiClient api;

  /// The device voice, used only when the neural voice is unavailable.
  final Speaker fallback;

  /// Builds the audio player of one utterance (a test injects a double here).
  final SpeechAudioPlayerFactory playerFactory;

  /// Where the mp3 is written; the app uses the system temp directory, which is
  /// the app's own cache directory on Android.
  final Directory tempDirectory;

  /// Neural voice id. Null lets the backend use its own default voice.
  final String? voice;

  /// Safety net for a player that never reports the end of an utterance: after
  /// this long the file is deleted, the player released, and
  /// [lastAttemptFailed] says the outcome was not confirmed instead of holding
  /// the mp3 forever.
  final Duration playbackTimeout;

  /// Temp-file name prefix. Identical to the Windows speaker's, so a single
  /// sweep (`sweepStaleTtsFiles`) can clean up after both builds.
  static const String filePrefix = 'anchor-tts';

  SpeechAudioPlayer? _player;
  Future<void>? _cleanup;
  bool _failed = false;
  int _generation = 0;
  int _counter = 0;

  @override
  bool get lastAttemptFailed => _failed;

  /// True while the neural voice is in this app's player. (The device-voice
  /// fallback keeps its own state inside [TtsService].)
  bool get speaking => _player != null;

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    if (text.trim().isEmpty) return;
    final generation = ++_generation;
    await _silence(); // One voice at a time: interrupt whatever is playing.

    Uint8List audio;
    try {
      // edge-tts rate format (`^[+-]\d+%$`): null keeps the server default,
      // which is already slowed down for older adults; '+0%' is normal pace.
      audio = await api.ttsSpeech(
        text: text,
        voice: voice,
        rate: slow ? null : '+0%',
      );
    } on ApiCancelled {
      // Stop was pressed while the audio was downloading: stay silent.
      return;
    } catch (error) {
      if (generation != _generation) return;
      await _speakWithDeviceVoice(
        text,
        language: language,
        slow: slow,
        reason: '$error',
      );
      return;
    }
    if (generation != _generation) return; // Stop arrived with the audio.
    if (audio.isEmpty) {
      // A 200 with no audio would otherwise "play" silence.
      await _speakWithDeviceVoice(
        text,
        language: language,
        slow: slow,
        reason: 'empty mp3 body',
      );
      return;
    }

    final file = _nextFile();
    try {
      await file.writeAsBytes(audio, flush: true);
    } catch (error) {
      await _speakWithDeviceVoice(
        text,
        language: language,
        slow: slow,
        reason: 'cannot write ${file.path} ($error)',
      );
      return;
    }
    if (generation != _generation) {
      await _deleteQuietly(file);
      return;
    }

    SpeechAudioPlayer? player;
    try {
      player = playerFactory.create();
      await player.start(file.path);
      if (generation != _generation) {
        // Stop arrived while the player was loading: silence it at once, say
        // nothing, leave no file behind.
        await player.stop();
        await player.dispose();
        await _deleteQuietly(file);
        return;
      }
      _player = player;
      _failed = false;
      // Tracked, not awaited here: speak() must not block for the length of the
      // sentence. dispose() waits for it, so the mp3 never outlives the app.
      _cleanup = _afterPlayback(
        player,
        file,
        generation,
        text: text,
        language: language,
        slow: slow,
      );
      unawaited(_cleanup);
    } catch (error) {
      await _disposeQuietly(player);
      await _deleteQuietly(file);
      await _speakWithDeviceVoice(
        text,
        language: language,
        slow: slow,
        reason: 'cannot play ${file.path} ($error)',
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await fallback.stop();
    await _silence();
  }

  @override
  Future<void> dispose() async {
    await stop();
    final cleanup = _cleanup;
    _cleanup = null;
    if (cleanup != null) {
      try {
        // Stop only signals; let the cleanup delete the mp3 and release the
        // player before the app goes away.
        await cleanup;
      } catch (error) {
        debugPrint('TTS cleanup on dispose failed: $error');
      }
    }
    await fallback.dispose();
  }

  /// The mp3 of one utterance. Unique, so two quick utterances never share a
  /// file and a stop can never delete the file a later utterance is playing.
  File _nextFile() {
    final name =
        '$filePrefix-${DateTime.now().microsecondsSinceEpoch}-${_counter++}.mp3';
    return File('${tempDirectory.path}${Platform.pathSeparator}$name');
  }

  /// Waits for the utterance to be over (its own end, a [stop], or the
  /// timeout), then releases the player and removes its file.
  ///
  /// This is the **only** place that deletes a launched mp3: deleting from two
  /// places at once would race a player that still has the file open.
  Future<void> _afterPlayback(
    SpeechAudioPlayer player,
    File file,
    int generation, {
    required String text,
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    var unconfirmed = false;
    Object? failure;
    try {
      await player.finished.timeout(
        playbackTimeout,
        onTimeout: () => throw const _PlaybackUnconfirmed(),
      );
    } on _PlaybackUnconfirmed {
      unconfirmed = true;
    } catch (error) {
      failure = error;
      debugPrint('Neural voice playback ended with an error: $error');
    }
    if (identical(_player, player)) _player = null;
    // A stopped or superseded player is not a failure: Stop is the user's wish.
    final superseded = generation != _generation;
    await _disposeQuietly(player);
    await _deleteQuietly(file);
    if (superseded) return;
    if (unconfirmed) {
      // The audio most likely did play; saying it a second time in the device
      // voice would be worse than saying nothing. Report it as unconfirmed
      // instead of healthy.
      _failed = true;
      debugPrint(
        'Neural voice did not report the end of the sentence within '
        '$playbackTimeout; treating it as unconfirmed.',
      );
      return;
    }
    if (failure != null) {
      // 200 OK but nothing came out of the speaker must not pass for spoken.
      _failed = true;
      debugPrint(
        'Neural voice did not play; falling back to the device voice.',
      );
      await _speakWithDeviceVoice(
        text,
        language: language,
        slow: slow,
        reason: 'playback failed',
      );
    }
  }

  /// Silences the neural voice instantly; its cleanup then deletes the file.
  Future<void> _silence() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (error) {
      debugPrint('Android TTS silence failed: $error');
    }
  }

  Future<void> _disposeQuietly(SpeechAudioPlayer? player) async {
    if (player == null) return;
    try {
      await player.dispose();
    } catch (error) {
      debugPrint('Android TTS player cleanup failed: $error');
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    } catch (error) {
      debugPrint('Could not delete ${file.path}: $error');
    }
  }

  Future<void> _speakWithDeviceVoice(
    String text, {
    required String language,
    required bool slow,
    required String reason,
  }) async {
    _failed = true;
    debugPrint('Neural voice unavailable ($reason); using the device voice.');
    try {
      await fallback.speak(text, language: language, slow: slow);
    } catch (error) {
      debugPrint('Device-voice fallback failed too: $error');
    }
  }
}

/// Thrown by [AndroidTtsSpeaker._afterPlayback] when no end of the utterance
/// was ever reported. A distinct type, because it is neither success nor a
/// playback error: the app cannot tell whether the senior heard it.
class _PlaybackUnconfirmed implements Exception {
  const _PlaybackUnconfirmed();

  @override
  String toString() => 'playback completion not reported';
}
