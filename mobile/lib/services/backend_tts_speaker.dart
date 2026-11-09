import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'speaker.dart';
import 'tts_playback_session.dart';
import 'windows_sapi_speaker.dart';

/// Windows speech with the **backend's neural voice** instead of the robotic
/// Windows SAPI voice.
///
/// A reply is split into sentences and pipelined through **one** long-lived
/// `powershell.exe` child that plays a queue of mp3 files with
/// `System.Windows.Media.MediaPlayer` (`PresentationCore`):
///
/// 1. the child is started immediately, so its ~1.5-1.9 s spawn overlaps the
///    first `POST /api/v1/tts` instead of following it;
/// 2. sentence 1 is fetched, written to a temp `.mp3` and its path is queued on
///    the child's stdin (one base64 line per file, `EOF` to finish);
/// 3. while sentence 1 plays, sentence 2 is already being fetched, and so on —
///    never more than one sentence queued ahead, so %TEMP% never fills up;
/// 4. each mp3 is deleted when the child reports that item finished playing
///    (and again after the child exits, which is when Windows has really
///    released every handle).
///
/// [WindowsSapiSpeaker] (`System.Speech`) stays as the audible fallback: when
/// the **first** sentence cannot be delivered the whole text is spoken by SAPI
/// in one call, and [lastAttemptFailed] then reports `true`. A failure on a
/// *later* sentence is logged, the already queued audio is finished, and no
/// fallback fires mid-reply — SAPI never starts talking in the middle of the
/// neural voice.
///
/// **Never `flutter_tts` on Windows**: its plugin crashes the process natively
/// (0xc0000005), which is why the whole Windows path goes through PowerShell.
///
/// [speak] returns once the first sentence has been handed to the player, so
/// callers never block for the length of the reply. [stop] bumps a generation
/// counter and kills the child — that is how Stop really silences speech, and
/// it guarantees a sentence fetched after Stop is discarded instead of queued.
/// Playback never throws into the UI: speech is an enhancement.
class BackendTtsSpeaker implements Speaker {
  BackendTtsSpeaker({
    required this.api,
    Speaker? fallback,
    this.launcher = const WindowsTtsPlaybackLauncher(),
    this.executable = WindowsSapiSpeaker.defaultExecutable,
    Directory? tempDirectory,
    this.voice,
  }) : fallback = fallback ?? WindowsSapiSpeaker(),
       tempDirectory = tempDirectory ?? Directory.systemTemp;

  /// The very same client the app uses for every other call, so the bearer
  /// token that `AppState.signInDemo` stores on it is what authorises `POST
  /// /tts`. No port and no token are ever hardcoded here.
  final ApiClient api;

  /// The Windows device voice, used only when the first sentence of a reply
  /// cannot be delivered by the neural voice.
  final Speaker fallback;

  /// Spawns the one long-lived player child (a test injects a double here).
  final TtsPlaybackLauncher launcher;

  final String executable;

  /// Where the mp3s are written; the app uses the system temp directory.
  final Directory tempDirectory;

  /// Neural voice id. Null lets the backend use its own default voice (the
  /// SAPI speaker likewise speaks with the installed Windows voice).
  final String? voice;

  /// Temp-file name prefix, so a leaked file is obvious.
  static const String filePrefix = 'anchor-tts';

  /// Sentences shorter than this are merged with a neighbour, so a stray "好。"
  /// does not become its own network round trip.
  static const int minSentenceRunes = 8;

  /// Where a sentence ends. The terminator stays at the end of the sentence
  /// that it closes.
  static const String sentenceTerminators = '。！？；!?;';

  /// One utterance. The child reads base64-encoded absolute mp3 paths from
  /// stdin, one per line, and the literal line `EOF` means "finish the current
  /// item and exit". It reuses a single `MediaPlayer` (`Open`/`Close` per file)
  /// so a sentence costs no process spawn. Nothing but ASCII travels in
  /// `-Command`, so no path, quote or CJK character can break the parse.
  ///
  /// `ANCHOR-TTS PLAY n` / `ANCHOR-TTS DONE n` are the acknowledgements that
  /// `TtsPlaybackSession` maps back to `play()` futures. A corrupt or
  /// undecodable file is closed and acknowledged instead of killing the queue.
  static const String playerScript = r'''
Add-Type -AssemblyName PresentationCore;
$player = New-Object System.Windows.Media.MediaPlayer;
$player.Volume = 1.0;
$reader = [System.Console]::In;
$index = 0;
while ($null -ne ($line = $reader.ReadLine())) {
  $line = $line.Trim();
  if ($line -eq '') { continue }
  if ($line -eq 'EOF') { break }
  try {
    $path = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($line));
    $player.Open([System.Uri]::new($path));
    $player.Play();
    [System.Console]::Out.WriteLine('ANCHOR-TTS PLAY ' + $index);
    [System.Console]::Out.Flush();
    $waited = 0;
    while (-not $player.NaturalDuration.HasTimeSpan -and $waited -lt 5000) { Start-Sleep -Milliseconds 50; $waited += 50 }
    if ($player.NaturalDuration.HasTimeSpan) {
      $total = $player.NaturalDuration.TimeSpan.TotalMilliseconds;
      while ($player.Position.TotalMilliseconds -lt $total -and $waited -lt 600000) { Start-Sleep -Milliseconds 50; $waited += 50 }
    }
  } catch {
  } finally {
    try { $player.Close() } catch { }
    [System.Console]::Out.WriteLine('ANCHOR-TTS DONE ' + $index);
    [System.Console]::Out.Flush();
    $index++
  }
}
$player.Close();
exit 0
''';

  TtsPlaybackSession? _session;

  /// The player spawned for the utterance that is still fetching its first
  /// sentence. Kept separately from [_session] so Stop can kill it too, before
  /// it has anything to play.
  TtsPlaybackSession? _pendingPlayer;
  Future<void>? _cleanup;
  bool _failed = false;
  int _generation = 0;
  int _counter = 0;

  @override
  bool get lastAttemptFailed => _failed;

  /// True while a PowerShell child is playing, either the neural voice or the
  /// SAPI fallback.
  bool get speaking {
    final deviceVoice = fallback;
    return _session != null ||
        _pendingPlayer != null ||
        (deviceVoice is WindowsSapiSpeaker && deviceVoice.speaking);
  }

  /// The exact PowerShell command line for the player child.
  List<String> argumentsFor() => <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    playerScript,
  ];

  /// Splits a reply into the smallest pieces worth one network round trip.
  ///
  /// Terminators (`。！？；!?;`) stay attached to the sentence they close;
  /// a newline only ends a line (it is not spoken). Empty fragments are
  /// dropped. Fragments shorter than [minSentenceRunes] are merged with the
  /// following fragment (the last short one with the previous sentence), so
  /// short interjections do not each pay the TTS latency and spawn no extra
  /// work. Text without any terminator stays one sentence.
  static List<String> splitSentences(String text) {
    final fragments = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final piece = buffer.toString().trim();
      buffer.clear();
      if (piece.isNotEmpty) fragments.add(piece);
    }

    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D) {
        flush(); // A line break is a boundary, never spoken.
        continue;
      }
      final char = String.fromCharCode(rune);
      buffer.write(char);
      if (sentenceTerminators.contains(char)) flush();
    }
    flush();

    final sentences = <String>[];
    var pending = '';
    for (final fragment in fragments) {
      pending = pending.isEmpty ? fragment : _join(pending, fragment);
      if (_runeLength(pending) >= minSentenceRunes) {
        sentences.add(pending);
        pending = '';
      }
    }
    if (pending.isNotEmpty) {
      if (sentences.isEmpty) {
        sentences.add(pending);
      } else {
        sentences[sentences.length - 1] = _join(sentences.last, pending);
      }
    }
    return sentences;
  }

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    if (text.trim().isEmpty) return;
    final clock = Stopwatch()..start();
    final generation = ++_generation;
    await _silence(); // One voice at a time: interrupt whatever is playing.

    final sentences = splitSentences(text);
    if (sentences.isEmpty) return;

    // Start the single player for this utterance *before* the first fetch: its
    // fixed startup then overlaps the network call instead of being added to
    // the time until the first sound. A failed start still falls back to SAPI.
    final playerFuture = _startPlayer();
    final firstFetch = _fetchSafely(sentences.first, slow);

    TtsPlaybackSession? launched;
    Object? launchError;
    try {
      launched = await playerFuture;
    } catch (error) {
      launchError = error;
    }

    if (generation != _generation) {
      launched?.kill();
      return;
    }
    if (launched == null) {
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'cannot start $executable ($launchError)',
      );
      return;
    }
    final player = launched;
    _pendingPlayer = player;

    final first = await firstFetch;
    if (generation != _generation) {
      _dropPlayer(player);
      return;
    }
    final firstError = first.error;
    if (firstError != null) {
      _dropPlayer(player);
      if (firstError is ApiCancelled) {
        // Stop was pressed while the audio was downloading: stay silent.
        return;
      }
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: '$firstError',
      );
      return;
    }
    final audio = first.audio!;
    if (audio.isEmpty) {
      // A 200 with no audio would otherwise "play" silence.
      _dropPlayer(player);
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'empty mp3 body',
      );
      return;
    }

    debugPrint(
      'TTS: first sentence fetched in ${clock.elapsedMilliseconds} ms '
      '(${_runeLength(sentences.first)} chars, ${sentences.length} sentence(s)).',
    );

    final firstFile = _nextFile();
    try {
      await firstFile.writeAsBytes(audio, flush: true);
    } catch (error) {
      _dropPlayer(player);
      await _deleteQuietly(firstFile);
      if (generation != _generation) return; // Stop arrived while writing.
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'cannot write ${firstFile.path} ($error)',
      );
      return;
    }
    if (generation != _generation) {
      _dropPlayer(player);
      await _deleteQuietly(firstFile);
      return;
    }

    final files = <File>{firstFile};
    Future<void> firstPlayed;
    try {
      _session = player;
      _pendingPlayer = null;
      _failed = false;
      unawaited(
        player.started.then((bool started) {
          if (started) {
            debugPrint(
              'TTS: first audio started ${clock.elapsedMilliseconds} ms '
              'after the reply was ready.',
            );
          }
        }),
      );
      firstPlayed = player.play(firstFile.path);
    } catch (error) {
      _session = null;
      _pendingPlayer = null;
      player.kill();
      files.remove(firstFile);
      await _deleteQuietly(firstFile);
      if (generation != _generation) return; // Stop arrived while cleaning up.
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'cannot queue ${firstFile.path} ($error)',
      );
      return;
    }
    _deleteAfterPlayback(firstPlayed, firstFile, files);

    // Fetches sentence 2, 3, ... while the previous sentence is playing, and
    // closes the queue with EOF when done. Tracked (not awaited: [speak] must
    // not block) but [dispose] waits for it so no mp3 is ever left behind.
    final cleanup = _finishUtterance(
      _pipeline(sentences, generation, player, files, slow, firstPlayed),
      player,
      files,
    );
    _cleanup = cleanup;
    unawaited(cleanup);
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
    if (cleanup != null) {
      try {
        // Stop only signals; let the child exit and its mp3s be removed.
        await cleanup;
      } catch (error) {
        debugPrint('TTS cleanup on dispose failed: $error');
      }
    }
    await fallback.dispose();
  }

  Future<TtsPlaybackSession> _startPlayer() =>
      launcher.start(executable, argumentsFor());

  /// Fetches one sentence. Never throws: a failure (including [ApiCancelled])
  /// is returned so the caller can decide between fallback and "finish what is
  /// queued" without an unhandled async error.
  Future<_SentenceAudio> _fetchSafely(String text, bool slow) async {
    try {
      // edge-tts rate format (`^[+-]\d+%$`): null keeps the server default,
      // which is already slowed down for older adults; '+0%' is normal pace.
      final audio = await api.ttsSpeech(
        text: text,
        voice: voice,
        rate: slow ? null : '+0%',
      );
      return _SentenceAudio.bytes(audio);
    } catch (error) {
      return _SentenceAudio.failure(error);
    }
  }

  /// Fetches every remaining sentence while the previous one plays.
  ///
  /// At most one sentence is queued ahead of the one playing (plus the one
  /// playing), which is enough to hide the fetch behind the sound without
  /// accumulating mp3s in %TEMP%. A later failure is logged and ends the
  /// pipeline with EOF: the already queued audio still plays and SAPI is never
  /// started in the middle of the reply.
  Future<void> _pipeline(
    List<String> sentences,
    int generation,
    TtsPlaybackSession session,
    Set<File> files,
    bool slow,
    Future<void> firstPlayed,
  ) async {
    final playing = <Future<void>>[firstPlayed];
    try {
      for (var index = 1; index < sentences.length; index++) {
        while (playing.length >= 2) {
          await playing.removeAt(0);
          if (!_isCurrent(generation, session)) return;
        }
        final fetchClock = Stopwatch()..start();
        final fetched = await _fetchSafely(sentences[index], slow);
        if (!_isCurrent(generation, session)) return;
        final error = fetched.error;
        if (error != null) {
          if (error is ApiCancelled) return;
          _failed = true;
          debugPrint(
            'TTS: sentence ${index + 1}/${sentences.length} could not be '
            'fetched ($error); finishing ${playing.length} queued item(s), '
            'no SAPI fallback.',
          );
          break;
        }
        final audio = fetched.audio!;
        if (audio.isEmpty) {
          _failed = true;
          debugPrint(
            'TTS: sentence ${index + 1}/${sentences.length} came back empty; '
            'finishing ${playing.length} queued item(s).',
          );
          break;
        }
        debugPrint(
          'TTS: sentence ${index + 1}/${sentences.length} fetched in '
          '${fetchClock.elapsedMilliseconds} ms '
          '(${_runeLength(sentences[index])} chars).',
        );

        final file = _nextFile();
        try {
          await file.writeAsBytes(audio, flush: true);
        } catch (error) {
          _failed = true;
          debugPrint(
            'TTS: sentence ${index + 1}/${sentences.length} could not be '
            'written ($error); finishing ${playing.length} queued item(s).',
          );
          break;
        }
        files.add(file);
        if (!_isCurrent(generation, session)) {
          files.remove(file);
          await _deleteQuietly(file);
          return;
        }
        final played = session.play(file.path);
        playing.add(played);
        _deleteAfterPlayback(played, file, files);
      }
    } catch (error) {
      debugPrint('TTS: sentence pipeline stopped: $error');
    } finally {
      // Always close the queue when this utterance is still the current one, so
      // a failure (or a bug) can never leave the child blocked on stdin. After
      // a Stop the child is already killed, so there is nothing to close.
      if (_isCurrent(generation, session)) {
        try {
          await session.finish();
        } catch (error) {
          debugPrint('TTS: could not finish the player queue: $error');
        }
      }
    }
  }

  /// Waits for the pipeline and the child, then sweeps every mp3 still known to
  /// this utterance. This is the only place that guarantees cleanup even if a
  /// per-item delete could not run (child killed mid-file, drive busy, ...).
  Future<void> _finishUtterance(
    Future<void> pipeline,
    TtsPlaybackSession session,
    Set<File> files,
  ) async {
    try {
      await pipeline;
    } catch (error) {
      debugPrint('TTS: pipeline error: $error');
    }
    try {
      await session.done;
    } catch (error) {
      debugPrint('TTS: player ended with an error: $error');
    }
    if (identical(_session, session)) _session = null;
    for (final file in files.toList(growable: false)) {
      await _deleteWhenReleased(file);
      files.remove(file);
    }
  }

  bool _isCurrent(int generation, TtsPlaybackSession session) =>
      generation == _generation &&
      identical(_session, session) &&
      session.running;

  /// The mp3 of one sentence. Unique, so two quick utterances never share a
  /// file and a kill can never delete the file a later utterance is playing.
  File _nextFile() {
    final name =
        '$filePrefix-${DateTime.now().microsecondsSinceEpoch}-${_counter++}.mp3';
    return File('${tempDirectory.path}${Platform.pathSeparator}$name');
  }

  /// Deletes [file] once its playback has ended (or the child has exited).
  /// [files] is the utterance's live set, so the final sweep never deletes a
  /// file that a later sentence still needs.
  void _deleteAfterPlayback(
    Future<void> played,
    File file,
    Set<File> files,
  ) {
    unawaited(
      played.then(
        (void _) async {
          files.remove(file);
          await _deleteWhenReleased(file);
        },
        onError: (Object error) async {
          debugPrint('TTS: playback of ${file.path} failed: $error');
          files.remove(file);
          await _deleteWhenReleased(file);
        },
      ),
    );
  }

  /// Stops the voice instantly. The mp3s go away through the per-item cleanup
  /// and, if the killed child still held one, through [_finishUtterance].
  Future<void> _silence() async {
    final pending = _pendingPlayer;
    _pendingPlayer = null;
    if (pending != null) pending.kill();
    final session = _session;
    _session = null;
    if (session != null) session.kill();
  }

  /// Kills a player that never reached [_session] (its first sentence failed or
  /// Stop arrived). No mp3 of it can still be needed.
  void _dropPlayer(TtsPlaybackSession player) {
    if (identical(_pendingPlayer, player)) _pendingPlayer = null;
    player.kill();
  }

  /// A file can stay locked for a moment after `MediaPlayer.Close()` (or after
  /// a kill), so a failed delete is retried briefly; the sweep after the child
  /// exits is the backstop.
  Future<void> _deleteWhenReleased(File file) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        await file.delete();
        return;
      } on PathNotFoundException {
        return; // Already gone.
      } on FileSystemException catch (error) {
        if (attempt == 19) {
          debugPrint('Could not delete ${file.path}: $error');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } catch (error) {
        debugPrint('Could not delete ${file.path}: $error');
        return;
      }
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

  Future<void> _speakWithSapi(
    String text, {
    required String language,
    required bool slow,
    required String reason,
  }) async {
    _failed = true;
    debugPrint('Neural voice unavailable ($reason); using Windows SAPI.');
    await fallback.speak(text, language: language, slow: slow);
  }

  static int _runeLength(String text) => text.runes.length;

  /// Joins two fragments without losing the word break between two ASCII words
  /// ("Hello." + "How are you?" becomes "Hello. How are you?"). Chinese text
  /// needs no space and full-width punctuation keeps it that way.
  static String _join(String first, String second) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    final left = first.codeUnitAt(first.length - 1);
    final right = second.codeUnitAt(0);
    final needsSpace = left < 0x80 && right < 0x80;
    return needsSpace ? '$first $second' : '$first$second';
  }
}

/// Result of one sentence fetch: either bytes or the caught error.
class _SentenceAudio {
  const _SentenceAudio.bytes(this.audio) : error = null;

  const _SentenceAudio.failure(this.error) : audio = null;

  final Uint8List? audio;
  final Object? error;
}
