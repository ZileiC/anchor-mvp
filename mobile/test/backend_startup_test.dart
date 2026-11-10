import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/screens/login_screen.dart';
import 'package:anchor_app/screens/senior/home_screen.dart';
import 'package:anchor_app/services/backend_bootstrapper.dart';
import 'package:anchor_app/state/backend_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/backend_fakes.dart';
import 'support/fakes.dart';

/// Startup UX contract: a small splash while the bundled backend starts, the
/// login picker afterwards, and — when it cannot start — a retry card that never
/// takes Stop, Settings or the login picker away.
void main() {
  BackendStartup startupWith(
    BackendHealthProbe probe,
    BackendProcessLauncher launcher, {
    bool supported = true,
    bool executableExists = true,
  }) => BackendStartup(
    bootstrapper: testBootstrapper(
      probe: probe,
      launcher: launcher,
      supported: supported,
      executableExists: executableExists,
    ),
  );

  Future<void> pumpApp(
    WidgetTester tester,
    BackendStartup startup, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    addTearDown(tester.view.reset);
    addTearDown(startup.dispose);
    await tester.pumpWidget(
      AnchorApp(state: buildTestState(FakeApi()), startup: startup),
    );
  }

  testWidgets('the splash shows while the check runs, then the login picker', (
    tester,
  ) async {
    final probe = ControlledHealthProbe();
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher);

    await pumpApp(tester, startup);
    await tester.pump();

    expect(find.byKey(const Key('backend-splash')), findsOneWidget);
    expect(find.text(L.zh.backendPreparing), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(probe.answered, isFalse);

    probe.setHealthy();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('backend-splash')), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(launcher.launches, 0);

    await disposeApp(tester);
  });

  testWidgets('a backend that is already running comes up with no spawn', (
    tester,
  ) async {
    final probe = FakeHealthProbe(<bool>[true]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher);

    await pumpApp(tester, startup);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('backend-problem')), findsNothing);
    expect(launcher.launches, 0);
    expect(probe.calls, 1);

    await disposeApp(tester);
  });

  testWidgets('a missing backend shows the retry card and the expected path', (
    tester,
  ) async {
    final probe = FakeHealthProbe(<bool>[false]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher, executableExists: false);

    await pumpApp(tester, startup);
    await tester.pump();
    await tester.pump();

    expect(find.text(L.zh.backendUnavailableTitle), findsOneWidget);
    expect(find.textContaining('anchor_backend.exe'), findsOneWidget);
    expect(find.text(L.zh.backendRetry), findsOneWidget);
    // The login picker is still there: nothing crashed.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('login-senior')), findsOneWidget);
    expect(launcher.launches, 0);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('tapping 重试 runs the check again and can succeed', (
    tester,
  ) async {
    final probe = FakeHealthProbe(<bool>[false]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher, executableExists: false);

    await pumpApp(tester, startup);
    await tester.pump();
    await tester.pump();
    expect(find.text(L.zh.backendUnavailableTitle), findsOneWidget);

    // Someone started the backend by hand (or the exe finished unpacking).
    probe.answers = <bool>[true];

    await tester.tap(find.text(L.zh.backendRetry));
    await tester.pump();
    await tester.pump();

    expect(find.text(L.zh.backendUnavailableTitle), findsNothing);
    expect(find.byKey(const Key('backend-problem')), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    // And the demo login works again.
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);
    expect(find.byType(SeniorHomeScreen), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a dead backend never blocks Stop', (tester) async {
    final probe = FakeHealthProbe(<bool>[false]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher, executableExists: false);

    await pumpApp(tester, startup);
    await tester.pump();
    await tester.pump();
    expect(find.text(L.zh.backendUnavailableTitle), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);
    expect(find.byType(SeniorHomeScreen), findsOneWidget);

    // The card follows the user into Home, but Stop still works.
    expect(find.text(L.zh.backendUnavailableTitle), findsOneWidget);
    expect(find.byKey(const Key('stop-control')), findsOneWidget);
    // ...and the appliance has no settings UI at all (architecture change
    // 2026-11-10), so there is no Settings entry to lose in the first place.
    expect(find.byKey(const Key('primary-settings')), findsNothing);

    await tester.tap(find.byKey(const Key('stop-control')));
    await settle(tester);
    expect(find.text(L.zh.stoppedTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('a timeout also ends on the retry card', (tester) async {
    final probe = FakeHealthProbe(<bool>[false]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher);

    await pumpApp(tester, startup);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text(L.zh.backendUnavailableTitle), findsOneWidget);
    expect(find.textContaining(L.zh.backendTimeoutBody), findsOneWidget);
    expect(find.textContaining('anchor_backend.exe'), findsOneWidget);
    expect(launcher.launches, 1);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('a platform without a local backend never shows the splash', (
    tester,
  ) async {
    final probe = FakeHealthProbe(<bool>[true]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher, supported: false);

    await pumpApp(tester, startup);
    await tester.pump();

    expect(find.byKey(const Key('backend-splash')), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(probe.calls, 0);
    expect(launcher.launches, 0);

    await disposeApp(tester);
  });

  testWidgets('the health check runs once, not on every rebuild', (
    tester,
  ) async {
    final probe = FakeHealthProbe(<bool>[true]);
    final launcher = FakeLauncher();
    final startup = startupWith(probe, launcher);

    await pumpApp(tester, startup);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(probe.calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);

    await disposeApp(tester);
  });
}
