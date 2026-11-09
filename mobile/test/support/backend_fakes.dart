import 'dart:async';

import 'package:anchor_app/services/backend_bootstrapper.dart';

/// The path a demo package would use; the core code only treats it as a string.
const String testBackendPath = r'C:\AnchorDemo\backend\anchor_backend.exe';

/// Probe double: answers a scripted list, repeating the last entry.
///
/// No socket is ever opened, so a test can describe a cold start purely as
/// "down, down, up".
class FakeHealthProbe implements BackendHealthProbe {
  FakeHealthProbe([List<bool>? answers]) : answers = answers ?? <bool>[true];

  List<bool> answers;
  bool throws = false;
  int calls = 0;

  @override
  Future<bool> isHealthy() async {
    calls++;
    if (throws) throw StateError('probe exploded');
    if (answers.isEmpty) return false;
    final index = calls - 1 < answers.length ? calls - 1 : answers.length - 1;
    return answers[index];
  }
}

/// Probe that stays pending until the test calls [setHealthy], so the splash can
/// be inspected mid-flight.
class ControlledHealthProbe implements BackendHealthProbe {
  final Completer<bool> _answer = Completer<bool>();
  int calls = 0;

  bool get answered => _answer.isCompleted;

  void setHealthy() {
    if (!_answer.isCompleted) _answer.complete(true);
  }

  @override
  Future<bool> isHealthy() {
    calls++;
    return _answer.future;
  }
}

/// Handle double: records termination instead of signaling a process.
class FakeProcessHandle implements BackendProcessHandle {
  int terminateCalls = 0;

  @override
  Future<void> terminate() async {
    terminateCalls++;
  }
}

/// Launcher double: records the call and hands back a [FakeProcessHandle]; no
/// process is spawned anywhere in the test suite.
class FakeLauncher implements BackendProcessLauncher {
  FakeLauncher({FakeProcessHandle? handle, this.error})
    : handle = handle ?? FakeProcessHandle();

  FakeProcessHandle handle;
  Object? error;
  int launches = 0;
  final List<String> paths = <String>[];
  final List<String> workingDirectories = <String>[];

  @override
  Future<BackendProcessHandle> launch(
    String executablePath, {
    required String workingDirectory,
  }) async {
    launches++;
    paths.add(executablePath);
    workingDirectories.add(workingDirectory);
    final failure = error;
    if (failure != null) throw failure;
    return handle;
  }
}

/// A bootstrapper wired to doubles: no real process, no real network, and no
/// real waiting (the polling delay is a no-op).
BackendBootstrapper testBootstrapper({
  required BackendHealthProbe probe,
  required BackendProcessLauncher launcher,
  bool supported = true,
  bool executableExists = true,
  bool Function(String path)? exists,
  Duration startupTimeout = const Duration(seconds: 2),
}) => BackendBootstrapper(
  supported: supported,
  healthProbe: probe,
  launcher: launcher,
  locateExecutable: () => testBackendPath,
  fileExists: exists ?? (String _) => executableExists,
  pollInterval: const Duration(milliseconds: 500),
  startupTimeout: startupTimeout,
  delay: (Duration _) async {},
);
