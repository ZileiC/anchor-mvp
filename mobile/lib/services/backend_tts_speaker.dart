import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'speaker.dart';
import 'speech_audio_format.dart';
import 'windows_sapi_speaker.dart';

/// Deletes speech mp3 files a previous run left in the temp directory.
///
/// Every mp3 is removed right after it plays, so anything still sitting there
/// after ten minutes is debris from a crash or a killed process. Sweeping it at
/// startup keeps `%TEMP%` from slowly filling with the senior's spoken replies.
Future<void> sweepStaleTtsFiles({
  Duration olderThan = const Duration(minutes: 10),
  Directory? directory,
}) async {
  final temp = directory ?? Directory.systemTemp;
  final cutoff = DateTime.now().subtract(olderThan);
  try {
    await for (final entity in temp.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!isSpeechTempName(name, BackendTtsSpeaker.filePrefix)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      } catch (error) {
        debugPrint('Could not sweep ${entity.path}: $error');
      }
    }
  } catch (error) {
    debugPrint('Could not sweep stale speech files: $error');
  }
}

/// Windows speech with the **backend's neural voice** instead of the robotic
/// Windows SAPI voice.
///
/// One utterance is: `POST /api/v1/tts` for the mp3 → write it to a temp file →
/// play that file with one short-lived `powershell.exe` that uses
/// `System.Windows.Media.MediaPlayer` (`PresentationCore`), polls `Position`
/// against `NaturalDuration` until the file ends, then exits.
///
/// [WindowsSapiSpeaker] (`System.Speech`) stays as the audible fallback: when
/// the backend cannot deliver audio the demo still speaks, and
/// [lastAttemptFailed] then reports `true` so nothing claims the neural voice
/// worked when it did not.
///
/// **Never `flutter_tts` on Windows**: its plugin crashes the process natively
/// (0xc0000005), which is why the whole Windows path goes through PowerShell.
///
/// [speak] returns once playback has been *started* (exactly like the SAPI
/// speaker), so callers never block for the length of the sentence. [stop]
/// kills the child process — that is how Stop really silences speech — and the
/// mp3 is removed as soon as the dead child has released it. Playback never
/// throws into the UI: speech is an enhancement.
class BackendTtsSpeaker implements Speaker, SpeechStatusSource {
  @override
  final ValueNotifier<SpeechPhase> playback = ValueNotifier(SpeechPhase.idle);
  BackendTtsSpeaker({
    required this.api,
    Speaker? fallback,
    this.launcher = const WindowsSapiLauncher(),
    this.executable = WindowsSapiSpeaker.defaultExecutable,
    Directory? tempDirectory,
    this.voice,
  }) : fallback = fallback ?? WindowsSapiSpeaker(),
       tempDirectory = tempDirectory ?? Directory.systemTemp;

  /// The very same client the app uses for every other call, so the bearer
  /// token that `AppState.signInDemo` stores on it is what authorises `POST
  /// /tts`. No port and no token are ever hardcoded here.
  final ApiClient api;

  /// The Windows device voice, used only when the neural voice is unavailable.
  final Speaker fallback;

  /// Spawns the PowerShell child (a test injects a double here).
  final SpeechProcessLauncher launcher;

  final String executable;

  /// Where the mp3 is written; the app uses the system temp directory.
  final Directory tempDirectory;

  /// Neural voice id. Null lets the backend use its own default voice (the
  /// SAPI speaker likewise speaks with the installed Windows voice).
  final String? voice;

  /// Temp-file name prefix, so a leaked file is obvious.
  static const String filePrefix = 'anchor-tts';

  /// One utterance. The mp3 path is base64-encoded inside the private
  /// `-Command` script, so no space, quote, backslash or CJK character in a
  /// temp path can break the PowerShell parse. The child exits by itself; the
  /// `exit 3` path means MediaPlayer never got a duration (unplayable file).
  static const String _scriptTemplate = r'''
Add-Type -AssemblyName PresentationCore;
$encoded = '__PATH_BASE64__';
$path = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded));
$player = New-Object System.Windows.Media.MediaPlayer;
$player.Volume = 1.0;
$player.Open([System.Uri]::new($path));
$player.Play();
$waited = 0;
while (-not $player.NaturalDuration.HasTimeSpan -and $waited -lt 5000) { Start-Sleep -Milliseconds 100; $waited += 100 }
if (-not $player.NaturalDuration.HasTimeSpan) { $player.Close(); exit 3 }
$total = $player.NaturalDuration.TimeSpan.TotalMilliseconds;
while ($player.Position.TotalMilliseconds -lt $total -and $waited -lt 600000) { Start-Sleep -Milliseconds 100; $waited += 100 }
$player.Close();
exit 0
''';

  SpeechProcessHandle? _process;
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
    return _process != null ||
        (deviceVoice is WindowsSapiSpeaker && deviceVoice.speaking);
  }

  /// The exact PowerShell script for [filePath]. Public for the encoding test.
  static String buildScript(String filePath) => _scriptTemplate.replaceAll(
    '__PATH_BASE64__',
    base64Encode(utf8.encode(filePath)),
  );

  List<String> argumentsFor(String filePath) => <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    buildScript(filePath),
  ];

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    if (text.trim().isEmpty) return;
    final generation = ++_generation;
    await _silence(); // One voice at a time: interrupt whatever is playing.
    if (generation != _generation) return;
    playback.value = SpeechPhase.preparing;

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
      await _speakWithSapi(
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
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'empty mp3 body',
      );
      return;
    }

    final file = _nextFile(audio);
    try {
      await file.writeAsBytes(audio, flush: true);
    } catch (error) {
      await _speakWithSapi(
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

    try {
      final handle = await launcher.launch(executable, argumentsFor(file.path));
      if (generation != _generation) {
        // Stop arrived while spawning: kill the child at once, say nothing.
        handle.kill();
        await _deleteQuietly(file);
        return;
      }
      _process = handle;
      playback.value = SpeechPhase.playing;
      _failed = false;
      // Tracked (not awaited here: speak() must not block), but dispose() waits
      // for it so the app never leaves an mp3 behind on exit.
      _cleanup = _afterPlayback(
        handle,
        file,
        text: text,
        language: language,
        slow: slow,
        generation: generation,
      );
      unawaited(_cleanup);
    } catch (error) {
      await _deleteQuietly(file);
      await _speakWithSapi(
        text,
        language: language,
        slow: slow,
        reason: 'cannot start $executable ($error)',
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    playback.value = SpeechPhase.idle;
    await fallback.stop();
    await _silence();
  }

  @override
  Future<void> dispose() async {
    await stop();
    final cleanup = _cleanup;
    if (cleanup != null) {
      try {
        // Stop only signals; let the child exit and its mp3 be removed.
        await cleanup;
      } catch (error) {
        debugPrint('TTS cleanup on dispose failed: $error');
      }
    }
    await fallback.dispose();
  }

  /// The audio file of one utterance. Unique, so two quick utterances never
  /// share a file and a kill can never delete the file a later utterance is
  /// playing.
  ///
  /// The extension follows the container we were actually handed (2026-11-14):
  /// edge-tts answers mp3, DeepSeek answers WAV, and the Windows player opens
  /// the path as a file rather than sniffing its contents.
  File _nextFile(Uint8List audio) {
    final extension = speechFileExtension(audio);
    final name =
        '$filePrefix-${DateTime.now().microsecondsSinceEpoch}-${_counter++}.$extension';
    return File('${tempDirectory.path}${Platform.pathSeparator}$name');
  }

  /// Waits for the child to exit (playing to the end, or killed by [stop]),
  /// then removes its file.
  ///
  /// This is the **only** place that deletes a launched mp3: deleting it from
  /// two places at once makes Windows answer one of them with "access denied"
  /// while the file is in its pending-delete state, and it cannot work earlier
  /// anyway because the child holds the file open until it dies.
  Future<void> _afterPlayback(
    SpeechProcessHandle handle,
    File file, {
    String? text,
    String language = 'zh-CN',
    bool slow = true,
    int generation = -1,
  }) async {
    var exitCode = 0;
    try {
      await handle.done;
      exitCode = await (handle.exitCode ?? Future<int>.value(0));
    } catch (error) {
      debugPrint('TTS playback process ended with an error: $error');
      exitCode = -1;
    }
    if (identical(_process, handle)) _process = null;
    // A killed child (Stop, or a newer utterance took over) is not a failure.
    final superseded = generation != _generation;
    if (!superseded) {
      playback.value = exitCode == 0 ? SpeechPhase.idle : SpeechPhase.fallback;
    }
    if (!superseded && exitCode != 0) {
      // The MediaPlayer script exits 0 only after really playing the file; 3
      // means it never opened it (missing codec, unreadable temp dir, no audio
      // device). Silence must not be mistaken for "spoken": say it once through
      // the device voice and leave lastAttemptFailed true so nothing claims the
      // neural voice worked.
      debugPrint(
        'Neural voice did not play (exit $exitCode); '
        'falling back to Windows SAPI.',
      );
      _failed = true;
      if (text != null && text.trim().isNotEmpty) {
        try {
          await fallback.speak(text, language: language, slow: slow);
        } catch (error) {
          debugPrint('SAPI fallback failed too: $error');
        }
      }
    }
    await _deleteQuietly(file);
  }

  /// Stops the voice instantly. The mp3 goes away through [_afterPlayback]
  /// once the killed child has really exited.
  Future<void> _silence() async {
    final handle = _process;
    _process = null;
    if (handle == null) return;
    try {
      handle.kill();
    } catch (error) {
      debugPrint('TTS kill failed: $error');
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
    playback.value = SpeechPhase.fallback;
    debugPrint('Neural voice unavailable ($reason); using Windows SAPI.');
    await fallback.speak(text, language: language, slow: slow);
  }
}
