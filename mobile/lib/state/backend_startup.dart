import 'dart:async';
// `AppExitResponse` lives in `dart:ui` and is not re-exported by the widgets
// library, so the exit hook needs it directly (works on every Flutter target).
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../services/backend_bootstrapper.dart';

/// Owns the one-time "is the local backend up?" question for the UI.
///
/// The widget layer stays dumb: it asks [start] once, renders a splash while
/// [waiting], and a retry card while [failed]. Shutdown travels the other way:
/// [attachLifecycle] hooks the app's exit so a backend child *we* started does
/// not outlive the window. Those hooks are the portable mechanism; Windows does
/// not deliver an exit request when a window is closed, so the Windows launcher
/// also joins a kill-on-close job object (see `WindowsKillOnCloseJob`), which is
/// what actually guarantees cleanup there.
class BackendStartup extends ChangeNotifier with WidgetsBindingObserver {
  BackendStartup({required this.bootstrapper});

  final BackendBootstrapper bootstrapper;

  BackendBootResult? _result;
  bool _busy = false;
  AppLifecycleListener? _lifecycle;

  /// The last (or current) attempt's outcome; null before the first attempt.
  BackendBootResult? get result => _result;

  /// True while [start] or [retry] is running.
  bool get busy => _busy;

  /// Whether this build has a local backend to wait for at all.
  bool get applies => bootstrapper.supported;

  /// Nothing to show yet: the splash is up and the health check is running.
  bool get waiting => applies && _result == null;

  /// The backend is not ready and the user can retry.
  bool get failed => applies && (_result?.needsRetry ?? false);

  /// The backend is reachable (or this platform has none).
  bool get ready => !applies || (_result?.isReady ?? false);

  /// The path the login/home card shows when the backend is missing.
  String get expectedExecutablePath =>
      _result?.executablePath ?? bootstrapper.expectedExecutablePath;

  /// Runs the first check. Safe to call more than once.
  Future<void> start() => _run(force: false);

  /// Runs the check again after a failure (the retry card).
  Future<void> retry() => _run(force: true);

  Future<void> _run({required bool force}) async {
    if (!applies) {
      _result ??= const BackendBootResult(
        BackendBootStatus.skipped,
        message: 'No local backend on this platform.',
      );
      notifyListeners();
      return;
    }
    if (_busy) return;
    if (!force && (_result?.isReady ?? false)) return;
    _busy = true;
    notifyListeners();
    // ensureReady never throws, but a broken injected seam could: the UI must
    // still get a result it can render.
    BackendBootResult result;
    try {
      result = await bootstrapper.ensureReady();
    } catch (error) {
      result = BackendBootResult(
        BackendBootStatus.missing,
        message: 'Unexpected failure while preparing the backend: $error',
        executablePath: bootstrapper.expectedExecutablePath,
      );
    }
    _result = result;
    _busy = false;
    notifyListeners();
  }

  /// Stops the backend child we started, best effort. Called on app exit.
  Future<void> shutdown() => bootstrapper.shutdown();

  /// Registers the exit hooks. Only the real app calls this; widget tests do not
  /// need it, and it requires an initialized [WidgetsBinding].
  void attachLifecycle() {
    if (_lifecycle != null) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await shutdown();
        return AppExitResponse.exit;
      },
      onDetach: () => unawaited(shutdown()),
    );
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await shutdown();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Detached is the last lifecycle state a platform may report, but Windows
    // does not report anything at all when its window is closed, which is why
    // the Windows launcher relies on a kill-on-close job object as well.
    if (state == AppLifecycleState.detached) unawaited(shutdown());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(shutdown());
    super.dispose();
  }
}
