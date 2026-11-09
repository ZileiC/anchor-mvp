@TestOn('windows')
library;

import 'dart:io';

import 'package:anchor_app/services/backend_bootstrapper.dart';
import 'package:anchor_app/services/backend_bootstrapper_io.dart';
import 'package:anchor_app/services/backend_bootstrapper_win32.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Windows wiring itself: the health URL the SPEC freezes, and the
/// `anchor_app.exe`-relative location the demo package stages the backend at.
///
/// Everything here is pure string/path work — no socket is opened and no process
/// is started; the process-launching path is covered by doubles instead.
void main() {
  test('the health probe asks the frozen SPEC §6 health URL', () {
    final probe = HttpBackendHealthProbe();

    expect(probe.endpoint.toString(), 'http://127.0.0.1:8077/api/v1/health');
    expect(probe.timeout, const Duration(seconds: 1));
  });

  test('the bundled backend is expected next to the running executable', () {
    final appDirectory = File(Platform.resolvedExecutable).parent.path;
    final expected = '$appDirectory\\backend\\anchor_backend.exe';

    expect(backendExecutablePath(), expected);
    expect(backendExecutablePath(), endsWith(r'\backend\anchor_backend.exe'));
    expect(File(backendExecutablePath()).isAbsolute, isTrue);
  });

  test('a missing executable is reported instead of thrown', () {
    expect(
      backendExecutableExists(
        r'C:\Anchor\this-path-does-not-exist\anchor_backend.exe',
      ),
      isFalse,
    );
  });

  test('the Windows build boots a local backend when the API is local', () {
    final bootstrapper = createPlatformBackendBootstrapper();

    expect(bootstrapper.supported, isTrue);
    expect(
      bootstrapper.expectedExecutablePath,
      endsWith(r'\backend\anchor_backend.exe'),
    );
  });

  test('the app joins a kill-on-close job before it starts the backend', () {
    // This is what makes the backend die with the app even though Windows
    // delivers no Dart exit callback when the window is closed. It must engage
    // on the demo platform, and asking twice must not create a second job.
    final engaged = WindowsKillOnCloseJob.keepAppInJob();

    expect(engaged, isTrue);
    expect(WindowsKillOnCloseJob.keepAppInJob(), isTrue);
  });
}
