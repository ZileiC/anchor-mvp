import 'package:flutter/material.dart';

import 'screens/caregiver/caregiver_home.dart';
import 'screens/login_screen.dart';
import 'screens/senior/home_screen.dart';
import 'state/app_state.dart';
import 'state/backend_startup.dart';
import 'theme.dart';
import 'widgets/backend_startup_gate.dart';

/// Provides [AppState] to the widget tree and rebuilds dependants on change.
class AnchorScope extends InheritedNotifier<AppState> {
  const AnchorScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AnchorScope>();
    assert(scope != null, 'AnchorScope is missing above this widget');
    return scope!.notifier!;
  }
}

/// Route observer used by the Home screen to know whether it is the visible route,
/// so foreground invitations only act while Home is on top (SPEC §5.2).
final RouteObserver<ModalRoute<void>> anchorRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// The Anchor application: one app, two modes (SPEC §9).
class AnchorApp extends StatelessWidget {
  const AnchorApp({super.key, required this.state, this.startup});

  final AppState state;

  /// Waits for the bundled backend before the first screen is usable.
  ///
  /// Null means "no local backend to wait for" (widget tests, and any build that
  /// has nothing to prepare), so the app goes straight to [RootScreen].
  final BackendStartup? startup;

  @override
  Widget build(BuildContext context) {
    final startup = this.startup;
    return AnchorScope(
      state: state,
      child: MaterialApp(
        title: 'Anchor',
        debugShowCheckedModeBanner: false,
        theme: AnchorTheme.build(),
        navigatorObservers: <NavigatorObserver>[anchorRouteObserver],
        // The design targets 26 px; give the user room to grow text but never
        // shrink it, and clamp so a 3x system setting cannot break the layout.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.6,
          child: child ?? const SizedBox.shrink(),
        ),
        home: startup == null
            ? const RootScreen()
            : BackendStartupGate(startup: startup, child: const RootScreen()),
      ),
    );
  }
}

/// Chooses the mode from the authenticated profile: senior home, caregiver home,
/// or the demo role picker.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    if (!state.signedIn) {
      return LoginScreen(state: state);
    }
    if (state.isSenior) {
      return SeniorHomeScreen(state: state);
    }
    return CaregiverHomeScreen(state: state);
  }
}
