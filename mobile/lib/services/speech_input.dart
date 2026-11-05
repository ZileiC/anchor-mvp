import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Raised when the microphone cannot be used on this device.
class MicrophoneUnavailable implements Exception {
  const MicrophoneUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'MicrophoneUnavailable: $reason';
}

/// One captured turn. Audio exists only in memory and in a temp file that is
/// deleted immediately after reading — the backend never persists it either.
class RecordedAudio {
  const RecordedAudio({required this.base64, required this.mimeType});

  final String base64;
  final String mimeType;
}

/// Microphone seam: the text fallback stays available whatever happens here.
abstract class MicrophoneInput {
  Future<bool> isAvailable();

  Future<void> startRecording();

  /// Returns `null` when nothing usable was captured.
  Future<RecordedAudio?> stopRecording();

  Future<void> cancel();

  Future<void> dispose();
}

/// Real capture through the `record` plugin (SPEC §9).
///
/// Every plugin call is wrapped: a missing device or denied permission produces
/// [MicrophoneUnavailable] and the Talk screen falls back to typing.
class RecordMicrophoneInput implements MicrophoneInput {
  RecordMicrophoneInput({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _recorder.hasPermission(request: false);
    } catch (error) {
      debugPrint('Microphone probe failed: $error');
      return false;
    }
  }

  @override
  Future<void> startRecording() async {
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        throw const MicrophoneUnavailable('permission denied');
      }
      final directory = await Directory.systemTemp.createTemp('anchor-turn');
      _path = '${directory.path}${Platform.pathSeparator}turn.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
    } on MicrophoneUnavailable {
      rethrow;
    } catch (error) {
      _path = null;
      throw MicrophoneUnavailable('$error');
    }
  }

  @override
  Future<RecordedAudio?> stopRecording() async {
    final path = _path;
    _path = null;
    try {
      final result = await _recorder.stop();
      final filePath = result ?? path;
      if (filePath == null) return null;
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await _cleanUp(file);
      if (bytes.isEmpty) return null;
      return RecordedAudio(base64: base64Encode(bytes), mimeType: 'audio/wav');
    } catch (error) {
      debugPrint('Microphone stop failed: $error');
      return null;
    }
  }

  Future<void> _cleanUp(File file) async {
    try {
      await file.delete();
      final directory = file.parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      debugPrint('Microphone cleanup failed: $error');
    }
  }

  @override
  Future<void> cancel() async {
    _path = null;
    try {
      await _recorder.cancel();
    } catch (error) {
      debugPrint('Microphone cancel failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (error) {
      debugPrint('Microphone dispose failed: $error');
    }
  }
}

/// Fallback used in tests and on devices without a usable microphone.
class UnavailableMicrophoneInput implements MicrophoneInput {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> startRecording() async {
    throw const MicrophoneUnavailable('no microphone');
  }

  @override
  Future<RecordedAudio?> stopRecording() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
