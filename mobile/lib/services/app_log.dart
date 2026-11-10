import 'dart:io';

import 'package:flutter/foundation.dart';

/// A tiny on-disk log for the Windows demo build.
///
/// Why this exists: the app used to report failures only through `debugPrint`,
/// which goes to a console nobody sees in a windowed double-click launch. When
/// the microphone would not open there was no way to learn *why* — the operator
/// got "这个设备的麦克风用不了" and the real exception was lost. This writes the
/// same lines to `%LOCALAPPDATA%\Anchor\anchor_app.log` (and to the console), so
/// a failure can be diagnosed from the machine it happened on.
///
/// Device logs are small: the older file is deleted once it passes [_maxBytes].
class AppLog {
  AppLog({required this.file});

  static const int _maxBytes = 2 * 1024 * 1024;
  static AppLog? _instance;

  final File file;

  /// Opens (or creates) the log and redirects `debugPrint` into it.
  ///
  /// Never throws: if the directory cannot be created the app keeps running with
  /// console output only — a logging failure must not break the product.
  static AppLog? install({Directory? directory}) {
    if (_instance != null) return _instance;
    try {
      final base =
          directory ??
          Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
            '${Platform.pathSeparator}Anchor',
          );
      base.createSync(recursive: true);
      final file = File('${base.path}${Platform.pathSeparator}anchor_app.log');
      if (file.existsSync() && file.lengthSync() > _maxBytes) file.deleteSync();
      final log = AppLog(file: file);
      _instance = log;
      log._hook();
      log.write('--- anchor app start ---');
      return log;
    } catch (_) {
      return null;
    }
  }

  void _hook() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      write(message ?? '');
    };
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      write('FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}');
      previous?.call(details);
    };
  }

  void write(String message) {
    try {
      file.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Best effort only.
    }
  }
}
