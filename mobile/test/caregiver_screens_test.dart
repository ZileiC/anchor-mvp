import 'dart:async';

import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/screens/caregiver/caregiver_preferences_screen.dart';
import 'package:anchor_app/screens/caregiver/invitation_screen.dart';
import 'package:anchor_app/screens/setup/setup_home_screen.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The two family screens rewritten on 2026-11-11 that no other test opens:
/// the propose-a-schedule form and the invite-code screen. They are reachable
/// from the phone hub, so a broken layout or a dead button here is a broken
/// product — this pins that they open, lay out at 1.6x text and still send what
/// they claim to send.
void main() {
  /// Signs in on the family phone and pushes [screen] over the hub.
  ///
  /// It signs in by handing the app a profile rather than tapping the picker:
  /// at 1.6x text the picker's cards sit below the fold, and this test is about
  /// the family screens, not the login page.
  Future<void> openOnPhone(
    WidgetTester tester,
    FakeApi api,
    AppState state,
    Widget screen, {
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(780, 1688);
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    state.profile = api.profile;
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    expect(find.byType(SetupHomeScreen), findsOneWidget);
    final navigator = Navigator.of(
      tester.element(find.byType(SetupHomeScreen)),
    );
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => screen)));
    await settle(tester);
  }

  testWidgets('the propose form sends the window it shows', (tester) async {
    final api = FakeApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await openOnPhone(
      tester,
      api,
      state,
      CaregiverPreferencesScreen(state: state),
    );

    expect(find.byType(CaregiverPreferencesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Both choices are reachable and the picked one is the one that is sent.
    await tester.tap(find.byKey(const ValueKey<String>('propose-cap-0')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('propose-submit')));
    await tester.tap(find.byKey(const Key('propose-submit')));
    await settle(tester);

    expect(api.proposalList, hasLength(1));
    expect(api.proposalList.single.payload['daily_cap'], 0);
    expect(api.proposalList.single.payload['greeting_start'], '09:00');
    expect(api.proposalList.single.payload['greeting_end'], '11:00');
    expect(find.text(L.zh.caregiverProposeSent), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the propose form lays out at 1.6x text', (tester) async {
    final api = FakeApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await openOnPhone(
      tester,
      api,
      state,
      CaregiverPreferencesScreen(state: state),
      textScale: 1.6,
    );

    expect(find.byType(CaregiverPreferencesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final key in <Key>[
      const Key('propose-greeting-start'),
      const Key('propose-paused'),
      const Key('propose-submit'),
    ]) {
      await tester.ensureVisible(find.byKey(key));
      expect(find.byKey(key), findsOneWidget, reason: '$key');
    }
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('the invite screen refuses a bad code and accepts a good one', (
    tester,
  ) async {
    final api = FakeApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await openOnPhone(tester, api, state, InvitationScreen(state: state));

    expect(find.byType(InvitationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const Key('invitation-token-field')),
      'expired-token',
    );
    await tester.tap(find.byKey(const Key('invitation-accept')));
    await settle(tester);
    expect(find.text(L.zh.caregiverInvalid), findsOneWidget);
    expect(find.text(L.zh.caregiverAccepted), findsNothing);

    await tester.enterText(
      find.byKey(const Key('invitation-token-field')),
      'good-token',
    );
    await tester.tap(find.byKey(const Key('invitation-accept')));
    await settle(tester);
    expect(find.text(L.zh.caregiverAccepted), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
