import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One long-lived `powershell.exe` child that plays a **queue of mp3 files**
/// from its stdin, so sentence-by-sentence speech does not pay the ~1.5-1.9 s
/// process-spawn cost once per sentence.
///
/// Protocol (the child side is in `BackendTtsSpeaker.playerScript`):
///
/// * stdin, one line per item: the base64-encoded UTF-8 absolute path of the
///   mp3 to play. Base64 keeps spaces, quotes, backslashes and CJK characters
///   out of the command line entirely.
/// * stdin, the literal line `EOF`: finish after the item being played and exit
///   0. Closing stdin is equivalent (the child's `ReadLine` returns null).
/// * stdout, `ANCHOR-TTS PLAY <n>`: the child has just called `Play()` for item
///   `<n>` (queue index, 0-based). Used for the "time to first audio" figure.
/// * stdout, `ANCHOR-TTS DONE <n>`: item `<n>` finished playing (or the file
///   could not be played) and the child has closed it. Used to delete the mp3
///   as soon as it is no longer needed.
///
/// Anything else the child writes is logged, not interpreted.
abstract class TtsPlaybackSession {
  /// Queues [path] for playback. The returned future completes when the child
  /// reports that this item finished (or when the child exits, whichever comes
  /// first), so the caller can delete the file.
  Future<void> play(String path);

  /// Signals the end of the queue: `EOF` on stdin, then closes it. The child
  /// finishes the item it is playing and exits; [done] then completes.
  Future<void> finish();

  /// Kills the child immediately. That is how Stop silences speech.
  void kill();

  /// True while the child process is still running.
  bool get running;

  /// Completes when the child is gone (normally, at EOF, or killed).
  Future<void> get done;

  /// Completes `true` once the child reports it started playing; `false` if it
  /// exited first. Only feeds the latency log, so it never blocks the caller.
  Future<bool> get started;
}

/// Seam over spawning the long-lived player, so the speaker is unit-testable
/// without a real PowerShell child process.
abstract class TtsPlaybackLauncher {
  Future<TtsPlaybackSession> start(String executable, List<String> arguments);
}

/// The real launcher: one `powershell.exe`, stdin/stdout pipes attached.
class WindowsTtsPlaybackLauncher implements TtsPlaybackLauncher {
  const WindowsTtsPlaybackLauncher();

  @override
  Future<TtsPlaybackSession> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    return _ProcessTtsPlaybackSession(process);
  }
}

/// Protocol markers shared with `BackendTtsSpeaker.playerScript`. Public so the
/// script text and the parser can be asserted against each other in a test.
const String ttsPlayerPlayMarker = 'ANCHOR-TTS PLAY ';
const String ttsPlayerDoneMarker = 'ANCHOR-TTS DONE ';
const String ttsPlayerEndMarker = 'EOF';

class _ProcessTtsPlaybackSession implements TtsPlaybackSession {
  _ProcessTtsPlaybackSession(this._process) {
    final decoder = const Utf8Decoder(allowMalformed: true);
    _stdout = _process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object error) => debugPrint('TTS player stdout: $error'),
          cancelOnError: false,
        );
    _stderr = _process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) {
            final text = line.trim();
            if (text.isNotEmpty) debugPrint('TTS player stderr: $text');
          },
          onError: (Object error) => debugPrint('TTS player stderr: $error'),
          cancelOnError: false,
        );
    unawaited(
      _process.exitCode.then(
        (int code) => _endProcess(exitCode: code),
        onError: (Object error) => _endProcess(error: error),
      ),
    );
  }

  final Process _process;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;

  IOSink get _stdin => _process.stdin;

  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};
  final Completer<void> _done = Completer<void>();
  final Completer<bool> _started = Completer<bool>();
  bool _running = true;
  int _nextIndex = 0;

  @override
  Future<void> play(String path) {
    if (!_running) return Future<void>.value();
    final index = _nextIndex++;
    final completer = Completer<void>();
    _pending[index] = completer;
    try {
      _stdin.writeln(base64Encode(utf8.encode(path)));
      unawaited(
        _stdin.flush().catchError((Object error) {
          debugPrint('TTS player stdin flush failed: $error');
        }),
      );
    } catch (error) {
      debugPrint('TTS player could not queue $path: $error');
      _pending.remove(index)?.complete();
    }
    return completer.future;
  }

  @override
  Future<void> finish() async {
    if (!_running) return;
    try {
      _stdin.writeln(ttsPlayerEndMarker);
      await _stdin.flush();
    } catch (error) {
      debugPrint('TTS player could not send EOF: $error');
    }
    try {
      // Closing the pipe makes the child's next `ReadLine` return null even if
      // the EOF line itself was lost, so it can never wait forever.
      await _stdin.close();
    } catch (error) {
      debugPrint('TTS player could not close stdin: $error');
    }
  }

  @override
  void kill() {
    try {
      _process.kill();
    } catch (error) {
      debugPrint('TTS player kill failed: $error');
    }
  }

  @override
  bool get running => _running;

  @override
  Future<void> get done => _done.future;

  @override
  Future<bool> get started => _started.future;

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.startsWith(ttsPlayerPlayMarker)) {
      if (!_started.isCompleted) _started.complete(true);
      return;
    }
    if (line.startsWith(ttsPlayerDoneMarker)) {
      final index = int.tryParse(line.substring(ttsPlayerDoneMarker.length));
      if (index != null) _pending.remove(index)?.complete();
      return;
    }
    if (line.isNotEmpty) debugPrint('TTS player: $line');
  }

  void _endProcess({int? exitCode, Object? error}) {
    if (!_running) return;
    _running = false;
    if (exitCode != null && exitCode != 0) {
      debugPrint('TTS player exited with code $exitCode');
    }
    if (error != null) debugPrint('TTS player ended with an error: $error');
    if (!_started.isCompleted) _started.complete(false);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
    // The process is gone, so no further stdout/stderr can matter. Cancel late
    // to avoid dropping the final lines on a fast exit.
    unawaited(_stdout.cancel());
    unawaited(_stderr.cancel());
  }
}
