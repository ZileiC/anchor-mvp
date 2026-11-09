import 'package:anchor_app/services/backend_bootstrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/backend_fakes.dart';

/// Auto-start contract (SPEC §9 "runtime"): the app is the only thing the user
/// double-clicks, so it must find, start and later stop the bundled backend —
/// and it must never let a failure escape into the UI.
void main() {
  group('ensureReady', () {
    test('a healthy backend is adopted without spawning anything', () async {
      final probe = FakeHealthProbe(<bool>[true]);
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

      final result = await bootstrapper.ensureReady();

      expect(result.status, BackendBootStatus.alreadyRunning);
      expect(result.isReady, isTrue);
      expect(result.needsRetry, isFalse);
      expect(launcher.launches, 0);
      expect(probe.calls, 1);
      expect(bootstrapper.ownsChild, isFalse);
    });

    test(
      'a cold start launches the bundled exe and polls until healthy',
      () async {
        final probe = FakeHealthProbe(<bool>[false, false, true]);
        final launcher = FakeLauncher();
        final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

        final result = await bootstrapper.ensureReady();

        expect(result.status, BackendBootStatus.started);
        expect(launcher.launches, 1);
        expect(launcher.paths.single, testBackendPath);
        // The backend runs from its own folder (that is where its data/ lives).
        expect(launcher.workingDirectories.single, r'C:\AnchorDemo\backend');
        expect(probe.calls, 3);
        expect(bootstrapper.ownsChild, isTrue);
      },
    );

    test(
      'a backend that never answers ends as timeout after the budget',
      () async {
        final probe = FakeHealthProbe(<bool>[false]);
        final launcher = FakeLauncher();
        final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

        final result = await bootstrapper.ensureReady();

        expect(result.status, BackendBootStatus.timeout);
        expect(result.needsRetry, isTrue);
        expect(result.isReady, isFalse);
        expect(result.executablePath, testBackendPath);
        expect(result.message, contains('/api/v1/health'));
        // One initial probe plus one per 500 ms step of a 2 s budget.
        expect(probe.calls, 5);
        expect(launcher.launches, 1);
        // We still own the child: a retry can adopt it, and exit can stop it.
        expect(bootstrapper.ownsChild, isTrue);
      },
    );

    test(
      'a missing executable is reported with its path and never launched',
      () async {
        final probe = FakeHealthProbe(<bool>[false]);
        final launcher = FakeLauncher();
        final bootstrapper = testBootstrapper(
          probe: probe,
          launcher: launcher,
          executableExists: false,
        );

        final result = await bootstrapper.ensureReady();

        expect(result.status, BackendBootStatus.missing);
        expect(result.executablePath, testBackendPath);
        expect(result.message, contains(testBackendPath));
        expect(launcher.launches, 0);
        expect(bootstrapper.ownsChild, isFalse);
      },
    );

    test(
      'a launcher that throws becomes missing instead of an exception',
      () async {
        final probe = FakeHealthProbe(<bool>[false]);
        final launcher = FakeLauncher(error: StateError('access denied'));
        final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

        final result = await bootstrapper.ensureReady();

        expect(result.status, BackendBootStatus.missing);
        expect(result.message, contains('Could not launch'));
        expect(result.message, contains('access denied'));
        expect(launcher.launches, 1);
        expect(bootstrapper.ownsChild, isFalse);
      },
    );

    test('a throwing health probe is treated as "down"', () async {
      final probe = FakeHealthProbe(<bool>[false])..throws = true;
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(
        probe: probe,
        launcher: launcher,
        executableExists: false,
      );

      final result = await bootstrapper.ensureReady();

      expect(result.status, BackendBootStatus.missing);
      expect(probe.calls, 1);
    });

    test(
      'a retry adopts the child it already started instead of spawning twice',
      () async {
        final probe = FakeHealthProbe(<bool>[false]);
        final launcher = FakeLauncher();
        final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

        final first = await bootstrapper.ensureReady();
        expect(first.status, BackendBootStatus.timeout);
        expect(launcher.launches, 1);

        // The backend finally binds its port; the user taps 重试.
        probe.answers = <bool>[true];
        final second = await bootstrapper.ensureReady();

        expect(second.status, BackendBootStatus.started);
        expect(launcher.launches, 1);
        expect(bootstrapper.ownsChild, isTrue);
      },
    );

    test('once we own a child, a healthy backend reports started, not alreadyRunning', () async {
      final probe = FakeHealthProbe(<bool>[false, false, true]);
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

      await bootstrapper.ensureReady();
      probe.answers = <bool>[true];
      final again = await bootstrapper.ensureReady();

      expect(again.status, BackendBootStatus.started);
      expect(launcher.launches, 1);
    });

    test(
      'a platform without a bundled backend is skipped without probing',
      () async {
        final probe = FakeHealthProbe(<bool>[true]);
        final launcher = FakeLauncher();
        final bootstrapper = testBootstrapper(
          probe: probe,
          launcher: launcher,
          supported: false,
        );

        final result = await bootstrapper.ensureReady();

        expect(result.status, BackendBootStatus.skipped);
        expect(result.isReady, isTrue);
        expect(probe.calls, 0);
        expect(launcher.launches, 0);
        expect(bootstrapper.ownsChild, isFalse);
      },
    );
  });

  group('shutdown', () {
    test('terminates the backend we started', () async {
      final probe = FakeHealthProbe(<bool>[false, false, true]);
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

      await bootstrapper.ensureReady();
      await bootstrapper.shutdown();

      expect(launcher.handle.terminateCalls, 1);
      expect(bootstrapper.ownsChild, isFalse);
    });

    test('leaves a backend it did not start alone', () async {
      final probe = FakeHealthProbe(<bool>[true]);
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

      await bootstrapper.ensureReady();
      await bootstrapper.shutdown();

      expect(launcher.launches, 0);
      expect(launcher.handle.terminateCalls, 0);
    });

    test('is idempotent', () async {
      final probe = FakeHealthProbe(<bool>[false, false, true]);
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(probe: probe, launcher: launcher);

      await bootstrapper.ensureReady();
      await bootstrapper.shutdown();
      await bootstrapper.shutdown();

      expect(launcher.handle.terminateCalls, 1);
    });

    test('does nothing when no attempt was made', () async {
      final launcher = FakeLauncher();
      final bootstrapper = testBootstrapper(
        probe: FakeHealthProbe(<bool>[true]),
        launcher: launcher,
      );

      await bootstrapper.shutdown();

      expect(launcher.handle.terminateCalls, 0);
    });
  });

  group('isLocalBackendUrl', () {
    test('accepts loopback backends only', () {
      expect(isLocalBackendUrl('http://127.0.0.1:8077'), isTrue);
      expect(isLocalBackendUrl('http://localhost:8077'), isTrue);
      expect(isLocalBackendUrl('http://[::1]:8077'), isTrue);
      expect(isLocalBackendUrl('http://192.168.1.20:8077'), isFalse);
      expect(isLocalBackendUrl('https://anchor.example.com'), isFalse);
      expect(isLocalBackendUrl('not a url'), isFalse);
    });
  });
}
