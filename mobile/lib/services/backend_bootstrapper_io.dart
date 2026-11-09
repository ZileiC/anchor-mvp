import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'backend_bootstrapper.dart';
import 'backend_bootstrapper_win32.dart';

/// Native build: on Windows the demo package ships the backend next to the app,
/// so the app can start it itself. Anywhere else (or when the API points at
/// another machine) the bootstrapper is disabled and the app carries on.
BackendBootstrapper createPlatformBackendBootstrapper() => BackendBootstrapper(
  supported: Platform.isWindows && isLocalBackendUrl(AnchorConfig.apiBase),
  healthProbe: const HttpBackendHealthProbe(),
  launcher: const ProcessBackendLauncher(),
  locateExecutable: backendExecutablePath,
  fileExists: backendExecutableExists,
);

/// `<dir of anchor_app.exe>\backend\anchor_backend.exe`, the layout
/// `scripts/package_windows.ps1` stages.
///
/// `Platform.resolvedExecutable` is the running `anchor_app.exe` in the packaged
/// demo and the Flutter runner in `build\windows\...` during development — in
/// the latter case the file is absent, which the dev workflow never notices
/// because `scripts\run_backend.ps1` already made the health probe succeed.
String backendExecutablePath() {
  final appDirectory = File(Platform.resolvedExecutable).parent.path;
  final separator = Platform.pathSeparator;
  return '$appDirectory${separator}backend${separator}anchor_backend.exe';
}

bool backendExecutableExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// Starts the bundled backend as a child process.
///
/// The packaged backend is a windowed executable (no console), so a plain
/// `Process.start` shows no window. Its pipes are drained even though we ignore
/// the output: a backend that writes a log must never block on a full pipe.
class ProcessBackendLauncher implements BackendProcessLauncher {
  const ProcessBackendLauncher();

  @override
  Future<BackendProcessHandle> launch(
    String executablePath, {
    required String workingDirectory,
  }) async {
    // Before spawning: join a kill-on-close job so the backend tree dies with
    // this app even on an abrupt exit (closing a Flutter Windows window delivers
    // no Dart callback). Children inherit the job, so it must exist first.
    WindowsKillOnCloseJob.keepAppInJob();

    final process = await Process.start(
      executablePath,
      const <String>[],
      workingDirectory: workingDirectory,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    // Drain and discard: never let a chatty child stall on a full pipe.
    unawaited(process.stdout.drain<void>().catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    return IoBackendProcessHandle(process);
  }
}

/// The handle [BackendBootstrapper.shutdown] terminates when the app exits.
class IoBackendProcessHandle implements BackendProcessHandle {
  IoBackendProcessHandle(this.process);

  final Process process;

  /// Kills the backend **tree**, best effort.
  ///
  /// `anchor_backend.exe` is a PyInstaller one-file executable: the process we
  /// started is a bootloader and the server that owns port 8077 is its child, so
  /// signaling only our pid would leave the server running. `taskkill /T` takes
  /// down the whole tree; the direct kill is the fallback when taskkill is not
  /// available.
  @override
  Future<void> terminate() async {
    try {
      final result = await Process.run('taskkill.exe', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]);
      if (result.exitCode != 0) {
        debugPrint('Anchor: taskkill exited ${result.exitCode}');
      }
      return;
    } catch (error) {
      debugPrint('Anchor: taskkill unavailable ($error)');
    }
    try {
      process.kill();
    } catch (error) {
      // An already dead child (or one we may not signal) is not a problem for
      // shutdown: the job object still cleans up when this process ends.
      debugPrint('Anchor: could not signal the backend ($error)');
    }
  }
}
