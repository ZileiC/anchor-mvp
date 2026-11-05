import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speaker.dart';

export 'speaker.dart';

/// Device TTS through `flutter_tts` (SPEC §9 "playback via device voice").
///
/// **Never use this on Windows.** The Windows implementation of the plugin
/// crashes the app with an access violation (0xc0000005 in
/// `flutter_tts_plugin.dll`) as soon as `speak()` runs. Windows is served by
/// `WindowsSapiSpeaker` instead; the platform factory picks it automatically and
/// the guard below stops an accidental call from killing the process.
class TtsService implements Speaker {
  TtsService({FlutterTts? engine}) : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;
  bool _configured = false;
  bool _failed = false;
  int _generation = 0;

  @override
  bool get lastAttemptFailed => _failed;

  Future<bool> _ensureConfigured() async {
    if (_configured) return true;
    try {
      await _engine.awaitSpeakCompletion(true);
      _configured = true;
      return true;
    } catch (error) {
      _failed = true;
      debugPrint('TTS unavailable: $error');
      return false;
    }
  }

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    if (text.trim().isEmpty) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Defensive: flutter_tts crashes natively on Windows (see class docs).
      _failed = true;
      debugPrint('TTS skipped on Windows; use WindowsSapiSpeaker instead.');
      return;
    }
    final generation = ++_generation;
    if (!await _ensureConfigured()) return;
    try {
      await _engine.stop();
      await _engine.setLanguage(language);
      await _engine.setSpeechRate(slow ? 0.42 : 0.55);
      await _engine.setVolume(1.0);
      await _engine.setPitch(1.0);
      if (generation != _generation) return; // Stop arrived while configuring.
      await _engine.speak(text);
      _failed = false;
    } catch (error) {
      _failed = true;
      debugPrint('TTS speak failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _engine.stop();
    } catch (error) {
      debugPrint('TTS stop failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
