import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'speaker.dart';

/// Handle to one spawned speech process, so [Speaker.stop] can silence it.
class SpeechProcessHandle {
  const SpeechProcessHandle({required this.kill, required this.done});

  /// Terminates the process that is currently speaking.
  final void Function() kill;

  /// Completes when the process is gone (normally or killed).
  final Future<void> done;
}

/// Seam over process spawning so the speaker is unit-testable without a real
/// PowerShell child process.
abstract class SpeechProcessLauncher {
  Future<SpeechProcessHandle> launch(String executable, List<String> arguments);
}

/// Spawns `powershell.exe` (Windows PowerShell 5.1, which ships System.Speech).
class WindowsSapiLauncher implements SpeechProcessLauncher {
  const WindowsSapiLauncher();

  @override
  Future<SpeechProcessHandle> launch(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    // Drain both pipes: an undrained child can block on a full pipe.
    unawaited(process.stdout.drain<void>().catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    return SpeechProcessHandle(
      kill: () {
        try {
          process.kill();
        } catch (error) {
          debugPrint('SAPI kill failed: $error');
        }
      },
      done: process.exitCode.then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

/// Windows-safe speech: one short-lived PowerShell process per utterance that
/// uses `System.Speech.Synthesis` (SAPI), never `flutter_tts`.
///
/// The text is base64-encoded in the private `-Command` script, so no quote,
/// newline or non-ASCII character can break it. Failures (no PowerShell, no
/// audio device, a killed child) are swallowed on purpose: speech is an
/// enhancement, and the UI must never see an exception from it.
class WindowsSapiSpeaker implements Speaker {
  WindowsSapiSpeaker({
    this.launcher = const WindowsSapiLauncher(),
    this.executable = defaultExecutable,
  });

  static const String defaultExecutable = 'powershell.exe';

  /// One utterance; kept so [stop] can interrupt it.
  static const String _scriptTemplate = r'''
Add-Type -AssemblyName System.Speech;
$encoded = '__TEXT_BASE64__';
$text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded));
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer;
$synth.Rate = __RATE__;
try { $synth.Speak($text); } finally { $synth.Dispose(); }
''';

  final SpeechProcessLauncher launcher;
  final String executable;
  SpeechProcessHandle? _process;
  bool _failed = false;
  int _generation = 0;

  @override
  bool get lastAttemptFailed => _failed;

  /// True while a speech process is running.
  bool get speaking => _process != null;

  /// The exact PowerShell script for [text]. Public for the encoding test.
  static String buildScript(String text, {bool slow = true}) {
    final encoded = base64Encode(utf8.encode(text));
    return _scriptTemplate
        .replaceAll('__TEXT_BASE64__', encoded)
        .replaceAll('__RATE__', slow ? '-2' : '0');
  }

  List<String> argumentsFor(String text, {bool slow = true}) => <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    buildScript(text, slow: slow),
  ];

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    if (text.trim().isEmpty) return;
    final generation = ++_generation;
    await _killProcess();
    if (generation != _generation) return; // Stop arrived before we spawned.
    try {
      final handle = await launcher.launch(
        executable,
        argumentsFor(text, slow: slow),
      );
      if (generation != _generation) {
        // Stop arrived while spawning: kill the child right away.
        handle.kill();
        return;
      }
      _process = handle;
      _failed = false;
      unawaited(
        handle.done.whenComplete(() {
          if (identical(_process, handle)) _process = null;
        }),
      );
    } catch (error) {
      // Never rethrow: a missing PowerShell or audio device must not break the UI.
      _failed = true;
      debugPrint('SAPI speech unavailable: $error');
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _killProcess();
  }

  Future<void> _killProcess() async {
    final handle = _process;
    _process = null;
    if (handle == null) return;
    try {
      handle.kill();
    } catch (error) {
      debugPrint('SAPI stop failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
