import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
// `dart:io` only exists on native platforms: the stub keeps the web build
// compiling and makes auto-start a no-op there.
import 'backend_bootstrapper_stub.dart'
    if (dart.library.io) 'backend_bootstrapper_io.dart'
    as impl;

/// How one [BackendBootstrapper.ensureReady] call ended.
enum BackendBootStatus {
  /// The health endpoint answered before we did anything: a backend someone
  /// else started (the dev workflow, or an orphan from an earlier run).
  alreadyRunning,

  /// We started the bundled backend and it became healthy.
  started,

  /// We started it (or a previous attempt did) but it never answered in time.
  timeout,

  /// There is no executable at the expected path, or it could not be launched.
  missing,

  /// This platform does not bundle a local backend (web, Android, iOS, macOS,
  /// Linux) or the API points at a remote host: nothing to do, carry on.
  skipped,
}

/// The outcome of [BackendBootstrapper.ensureReady].
///
/// [message] is an English diagnostic for logs and the task report; the user
/// facing copy is built from [L] plus [executablePath], which is why the path is
/// carried separately instead of baked into the message.
class BackendBootResult {
  const BackendBootResult(
    this.status, {
    this.message = '',
    this.executablePath = '',
  });

  final BackendBootStatus status;
  final String message;
  final String executablePath;

  /// The app may continue: the backend is reachable, or this platform has none.
  bool get isReady =>
      status == BackendBootStatus.alreadyRunning ||
      status == BackendBootStatus.started ||
      status == BackendBootStatus.skipped;

  /// The app may continue, but the login/home should offer a retry card.
  bool get needsRetry =>
      status == BackendBootStatus.timeout ||
      status == BackendBootStatus.missing;

  @override
  String toString() =>
      'BackendBootResult(${status.name}, path: $executablePath, '
      'message: $message)';
}

/// Seam: answers "is the local backend healthy right now?".
///
/// Implementations must never throw; a refused connection is the normal "not up
/// yet" answer during a cold start.
abstract class BackendHealthProbe {
  Future<bool> isHealthy();
}

/// Seam: starts the backend executable.
///
/// Production goes through `Process.start`; tests inject a fake so no real
/// process is ever spawned.
abstract class BackendProcessLauncher {
  Future<BackendProcessHandle> launch(
    String executablePath, {
    required String workingDirectory,
  });
}

/// Handle on a child process we started. Only termination is needed: the
/// bootstrapper never reads the child's output or exit code.
abstract class BackendProcessHandle {
  Future<void> terminate();
}

/// Resolves `<dir of Platform.resolvedExecutable>/backend/anchor_backend.exe`.
typedef BackendExecutableLocator = String Function();

/// Existence check for the bundled executable (a test seam, so the core file
/// stays free of `dart:io`).
typedef BackendFileCheck = bool Function(String path);

/// Injectable wait, so tests can poll without real time passing.
typedef BackendDelay = Future<void> Function(Duration duration);

/// True when [baseUrl] points at this machine.
///
/// Auto-start only makes sense for a loopback backend: with
/// `--dart-define=ANCHOR_API_BASE=http://192.168.1.20:8077` the backend lives on
/// another machine and there is nothing local to spawn.
bool isLocalBackendUrl(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  return host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';
}

/// Makes sure the local backend is reachable before the UI tries to use it.
///
/// The demo package ships `anchor_app.exe` next to `backend\anchor_backend.exe`;
/// a user must only have to double-click the app. The flow is therefore:
///
/// 1. probe `GET /api/v1/health` once — a live backend (dev workflow, or one
///    left running) is adopted and nothing is spawned;
/// 2. otherwise look for the bundled executable; when it is absent the result is
///    [BackendBootStatus.missing] with the expected path, and the UI offers a
///    retry card instead of crashing;
/// 3. otherwise launch it hidden and poll health every [pollInterval] for up to
///    [startupTimeout], ending as [BackendBootStatus.started] or
///    [BackendBootStatus.timeout].
///
/// Nothing here throws into the UI: every failure is a result value. The handle
/// of a child *we* started is kept so [shutdown] can terminate it — a backend
/// that was already running is never touched.
class BackendBootstrapper {
  BackendBootstrapper({
    required this.healthProbe,
    required this.launcher,
    required this.locateExecutable,
    required this.fileExists,
    this.supported = true,
    this.pollInterval = const Duration(milliseconds: 500),
    this.startupTimeout = const Duration(seconds: 25),
    BackendDelay? delay,
  }) : assert(
         pollInterval > Duration.zero,
         'a zero poll interval could never reach startupTimeout',
       ),
       _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final BackendHealthProbe healthProbe;
  final BackendProcessLauncher launcher;
  final BackendExecutableLocator locateExecutable;
  final BackendFileCheck fileExists;

  /// False on platforms without a bundled backend; [ensureReady] then returns
  /// [BackendBootStatus.skipped] without touching the probe or the launcher.
  final bool supported;

  /// How long one health poll waits between attempts. Also the logical time step
  /// of the timeout budget, so tests can poll with a no-op [delay].
  final Duration pollInterval;

  /// Total time we wait for a freshly launched backend to answer.
  final Duration startupTimeout;

  final BackendDelay _delay;

  BackendProcessHandle? _child;

  /// Whether a process launched by this bootstrapper is still owned by it. Used
  /// by [shutdown] and by the retry path (a retry must not spawn a second one).
  bool get ownsChild => _child != null;

  /// The path a bundled backend is expected at, even when it is absent. Never
  /// throws: the locator is a platform callback that could fail on a broken
  /// install, and the UI still needs something to display.
  String get expectedExecutablePath {
    try {
      return locateExecutable();
    } catch (error) {
      debugPrint('Anchor: could not resolve the backend path ($error)');
      return '';
    }
  }

  /// One attempt at "the backend is ready". Safe to call again after a failure:
  /// it probes first, so a backend that came up late is adopted instead of
  /// started twice.
  Future<BackendBootResult> ensureReady() async {
    if (!supported) {
      return const BackendBootResult(
        BackendBootStatus.skipped,
        message: 'Local backend auto-start is not used on this platform.',
      );
    }

    final path = expectedExecutablePath;

    if (await _healthy()) {
      if (_child == null) {
        return BackendBootResult(
          BackendBootStatus.alreadyRunning,
          executablePath: path,
        );
      }
      // We started this one on an earlier attempt (a retry after a timeout).
      return BackendBootResult(
        BackendBootStatus.started,
        executablePath: path,
        message: 'The backend we started is now healthy.',
      );
    }

    if (_child == null) {
      if (!_exists(path)) {
        return BackendBootResult(
          BackendBootStatus.missing,
          executablePath: path,
          message: 'No backend executable at "$path".',
        );
      }
      try {
        _child = await launcher.launch(
          path,
          workingDirectory: _parentDirectory(path),
        );
      } catch (error) {
        _child = null;
        return BackendBootResult(
          BackendBootStatus.missing,
          executablePath: path,
          message: 'Could not launch the backend at "$path": $error',
        );
      }
    }

    final up = await _pollUntilHealthy();
    if (!up) {
      return BackendBootResult(
        BackendBootStatus.timeout,
        executablePath: path,
        message:
            'The backend did not answer /api/v1/health within '
            '${startupTimeout.inSeconds}s.',
      );
    }
    return BackendBootResult(BackendBootStatus.started, executablePath: path);
  }

  /// Terminates the backend **we** started, best effort.
  ///
  /// A backend that was already running (adopted as
  /// [BackendBootStatus.alreadyRunning]) is deliberately left alone: it may be
  /// the developer's own `scripts\run_backend.ps1` process. Safe to call twice.
  ///
  /// On Windows the launcher additionally puts the app in a kill-on-close job
  /// object, so the child is cleaned up even on the exits this method never sees
  /// (closing the window delivers no Dart callback there).
  Future<void> shutdown() async {
    final child = _child;
    if (child == null) return;
    _child = null;
    try {
      await child.terminate();
    } catch (error) {
      debugPrint('Anchor: could not stop the backend ($error)');
    }
  }

  bool _exists(String path) {
    try {
      return fileExists(path);
    } catch (error) {
      debugPrint('Anchor: backend existence check failed ($error)');
      return false;
    }
  }

  /// Polls until healthy or the budget is spent.
  ///
  /// The budget is counted in [pollInterval] steps rather than wall-clock time:
  /// with the real delay that is the same thing, and with a test double it keeps
  /// the loop deterministic and instant.
  Future<bool> _pollUntilHealthy() async {
    var waited = Duration.zero;
    while (waited < startupTimeout) {
      await _delay(pollInterval);
      waited += pollInterval;
      if (await _healthy()) return true;
    }
    return false;
  }

  Future<bool> _healthy() async {
    try {
      return await healthProbe.isHealthy();
    } catch (error) {
      debugPrint('Anchor: backend health probe failed ($error)');
      return false;
    }
  }

  /// The directory that holds [path], using whichever separator it contains.
  static String _parentDirectory(String path) {
    final cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut <= 0 ? path : path.substring(0, cut);
  }
}

/// Real probe: `GET http://127.0.0.1:8077/api/v1/health` with a short timeout.
///
/// A refusal, a timeout or any other error means "not up yet"; the probe never
/// throws, otherwise a cold start would look like a crash.
class HttpBackendHealthProbe implements BackendHealthProbe {
  const HttpBackendHealthProbe({
    this.baseUrl = AnchorConfig.apiBase,
    this.timeout = const Duration(seconds: 1),
  });

  final String baseUrl;
  final Duration timeout;

  Uri get endpoint => Uri.parse('$baseUrl${AnchorConfig.apiPrefix}/health');

  @override
  Future<bool> isHealthy() async {
    try {
      final response = await http.get(endpoint).timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Nothing is listening yet: that is the answer, not an error.
      return false;
    }
  }
}

/// Used by the web/unsupported build, where [BackendBootstrapper.supported] is
/// false and neither of these is ever called.
class DisabledBackendHealthProbe implements BackendHealthProbe {
  const DisabledBackendHealthProbe();

  @override
  Future<bool> isHealthy() async => false;
}

/// Used by the web/unsupported build; never called.
class DisabledBackendProcessLauncher implements BackendProcessLauncher {
  const DisabledBackendProcessLauncher();

  @override
  Future<BackendProcessHandle> launch(
    String executablePath, {
    required String workingDirectory,
  }) async => throw UnsupportedError('No local backend on this platform');
}

/// The bootstrapper this build should use.
///
/// Windows → real probe + real launcher (only when the API is local);
/// web/other → a disabled one that reports [BackendBootStatus.skipped].
BackendBootstrapper createBackendBootstrapper() =>
    impl.createPlatformBackendBootstrapper();
