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

  /// Why the last [startRecording] failed, for the log and for the operator.
  ///
  /// Null once a recording starts successfully. Never shown raw to the older
  /// adult — the UI keeps a plain sentence — but it is what makes a failure
  /// diagnosable on the machine where it happened.
  String? get lastError;
}

/// Real capture through the `record` plugin (SPEC §9).
///
/// Every plugin call is wrapped: a missing device or denied permission produces
/// [MicrophoneUnavailable] and the Talk screen falls back to typing.
///
/// Windows needs more than one attempt. The `record` plugin opens the *default*
/// capture endpoint, and on this class of machine that default is often a
/// Bluetooth headset in Hands-Free mode which refuses 16 kHz mono, or a device
/// another app is holding. So the recorder walks a list of candidates — default
/// device at 16 kHz, then each enumerated input device at 16 kHz, then the
/// default again at 44.1 kHz — and keeps the first one that actually starts.
/// Every attempt is logged, with the reason, to `anchor_app.log`.
class RecordMicrophoneInput implements MicrophoneInput {
  RecordMicrophoneInput({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  String? _lastError;

  @override
  String? get lastError => _lastError;

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
    _lastError = null;
    final allowed = await _hasPermission();
    if (!allowed) {
      _lastError = 'microphone permission denied';
      throw const MicrophoneUnavailable('permission denied');
    }
    final directory = await Directory.systemTemp.createTemp('anchor-turn');
    final path = '${directory.path}${Platform.pathSeparator}turn.wav';
    final errors = <String>[];
    for (final config in await _candidates()) {
      final error = await _tryStart(config, path);
      if (error == null) {
        _path = path;
        _lastError = null;
        // Always log which device/rate actually opened: with several audio
        // endpoints on this machine (Bluetooth hands-free ones included) the
        // "default" is not stable, and a wrong-but-open device records clipping.
        debugPrint(
          'Microphone started with device=${config.device?.id ?? "default"} '
          'rate=${config.sampleRate} '
          'aec=${config.echoCancel} ns=${config.noiseSuppress} '
          '${errors.isEmpty ? "first try" : "after ${errors.length} failed attempt(s)"}',
        );
        return;
      }
      errors.add(error);
      await _reset();
    }
    _path = null;
    _lastError = errors.join(' | ');
    debugPrint('Microphone unavailable: $_lastError');
    try {
      await directory.delete(recursive: true);
    } catch (_) {
      // The temp directory is cleaned on the next successful turn or by the OS.
    }
    throw MicrophoneUnavailable(_lastError ?? 'no capture device');
  }

  /// Permission, asking for it once when the passive check says no.
  Future<bool> _hasPermission() async {
    try {
      if (await _recorder.hasPermission(request: false)) return true;
      return await _recorder.hasPermission(request: true);
    } catch (error) {
      debugPrint('Microphone permission check failed: $error');
      return false;
    }
  }

  /// Candidate configurations, most likely first.
  Future<List<RecordConfig>> _candidates() async {
    const base = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );
    // Preferred: ask the device to cancel its own speaker and suppress steady
    // noise (Windows implements this through WASAPI when the driver offers it).
    // The plain config stays right behind it, so a device that rejects these
    // flags still records — the attempt simply falls through to the next entry.
    const echoCancelled = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
    );
    final configs = <RecordConfig>[echoCancelled, base];
    List<InputDevice> devices = const <InputDevice>[];
    try {
      devices = await _recorder.listInputDevices();
      debugPrint(
        'Microphone inputs: ${devices.map((d) => '${d.id}:${d.label}').join(', ')}',
      );
    } catch (error) {
      debugPrint('Listing microphone inputs failed: $error');
    }
    for (final device in devices) {
      configs.add(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          device: device,
        ),
      );
    }
    // Last resort: some endpoints only accept 44.1 kHz. The backend ASR accepts
    // any WAV, so a wider rate is fine when it is the only thing that opens.
    configs.add(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );
    return configs;
  }

  /// Starts one candidate; returns null on success, else the failure reason.
  Future<String?> _tryStart(RecordConfig config, String path) async {
    try {
      await _recorder.start(config, path: path);
      return null;
    } catch (error) {
      return '${config.device?.id ?? 'default'}/'
          '${config.sampleRate}Hz: $error';
    }
  }

  Future<void> _reset() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing to cancel after a failed start.
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
      // 16 kHz mono 16-bit is 32 KB/s, so this line says how long the clip was
      // and whether the device actually delivered anything — the two numbers
      // that separate "mic never opened" from "mic opened but heard silence".
      // The peak separates "the person spoke" from "the input is muted": it is
      // measured on the samples only, never stored, so no audio is kept.
      if (bytes.isEmpty) {
        debugPrint(
          'Microphone captured 0 bytes (device opened but wrote nothing)',
        );
        return null;
      }
      final peak = _peak(bytes);
      debugPrint(
        'Microphone captured ${bytes.length} bytes '
        '(~${(bytes.length / 32000).toStringAsFixed(1)}s at 16 kHz mono, '
        'peak=$peak)',
      );
      if (peak >= 30000) {
        // Full-scale samples: the input is clipping, which smears consonants and
        // makes the recogniser answer with nonsense. Logged so it is visible.
        debugPrint(
          'Microphone audio is clipped (peak=$peak/32767); '
          'the input gain is too high or the speaker is bleeding into the mic',
        );
      }
      return RecordedAudio(base64: base64Encode(bytes), mimeType: 'audio/wav');
    } catch (error) {
      debugPrint('Microphone stop failed: $error');
      return null;
    }
  }

  /// Peak absolute sample of a 16-bit WAV payload (0…32768), header skipped.
  ///
  /// Purely diagnostic: the value is logged as a number and the audio is thrown
  /// away, so an operator can tell "the senior spoke" (peak in the thousands)
  /// from "the input is muted or the wrong device" (peak under a few hundred).
  static int _peak(List<int> bytes) {
    var peak = 0;
    for (var i = 44; i + 1 < bytes.length; i += 2) {
      final raw = bytes[i] | (bytes[i + 1] << 8);
      final value = raw >= 0x8000 ? 0x10000 - raw : raw;
      if (value > peak) peak = value;
    }
    return peak;
  }

  Future<void> _cleanUp(File file) async {
    // Two independent attempts: a missing/held file must never keep the
    // recording's temp directory on disk (it holds the senior's voice).
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Microphone cleanup failed: $error');
    }
    try {
      final directory = file.parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      debugPrint('Microphone directory cleanup failed: $error');
    }
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    try {
      await _recorder.cancel();
    } catch (error) {
      debugPrint('Microphone cancel failed: $error');
    }
    // An abandoned recording must not leave its WAV in %TEMP%: the app promises
    // that captured audio is never kept, and Cancel is a normal way to end a
    // turn (the senior changes their mind). Delete whatever was on disk.
    if (path != null) await _cleanUp(File(path));
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
  String? get lastError => 'no microphone';

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
