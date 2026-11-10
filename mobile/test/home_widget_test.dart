import 'package:anchor_app/app.dart';
import 'package:anchor_app/config.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/screens/caregiver/caregiver_home.dart';
import 'package:anchor_app/screens/login_screen.dart';
import 'package:anchor_app/screens/senior/call_screen.dart';
import 'package:anchor_app/screens/senior/home_screen.dart';
import 'package:anchor_app/screens/senior/settings_screen.dart';
import 'package:anchor_app/screens/senior/talk_screen.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Layout contract (SPEC §9, S4/S5/S7): three primary actions plus Settings, a
/// persistent Stop control, one-tap reachability, >=56 px targets, >=24 px text,
/// no overflow on phone or tablet — including at 1.3x text scale.
void main() {
  late FakeApi api;
  late AppState state;

  setUp(() {
    api = FakeApi()
      ..feed = threeActivityFeed()
      ..contactList = <Contact>[
        const Contact(id: 1, label: '美', phone: '13800000000'),
      ]
      ..scheduleValue = const CheckinSchedule(
        entries: <CheckinEntry>[
          CheckinEntry(
            date: '2026-03-11',
            localTime: '09:00',
            title: '早上好',
            body: '今天想聊聊天吗？',
          ),
        ],
        note: '',
      );
    state = buildTestState(api);
  });

  testWidgets('the login picker comes first and has no stop control', (
    tester,
  ) async {
    await tester.pumpWidget(AnchorApp(state: state));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('login-senior')), findsOneWidget);
    expect(find.byKey(const Key('login-caregiver')), findsOneWidget);
    expect(find.byKey(const Key('stop-control')), findsNothing);
  });

  testWidgets(
    'the appliance home shows three primary actions and Stop, never Settings',
    (tester) async {
      await pumpSignedIn(tester, state, size: const Size(390, 844));

      expect(find.byType(SeniorHomeScreen), findsOneWidget);
      // Redesign 2026-11-10: one voice disc (the primary action) plus two quiet
      // bars. The three tasks are still one tap away; they just no longer look
      // like three equal buttons.
      expect(find.byKey(const Key('primary-talk')), findsOneWidget);
      // Activities moved into the conversation: no separate Play door.
      expect(find.byKey(const Key('primary-play')), findsNothing);
      expect(find.byKey(const Key('primary-call')), findsOneWidget);
      // Architecture change 2026-11-10: the senior's computer has no settings UI.
      expect(find.byKey(const Key('primary-settings')), findsNothing);
      // Nothing on this page is running, so there is no Stop pill here.
      expect(find.byKey(const Key('stop-control')), findsNothing);

      await disposeApp(tester);
    },
  );

  testWidgets('every primary action opens its screen in one tap (phone)', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));

    Future<void> visit(Key key, Type screen) async {
      await tester.tap(find.byKey(key));
      await settle(tester);
      expect(find.byType(screen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(SeniorHomeScreen), findsOneWidget);
    }

    await visit(const Key('primary-talk'), TalkScreen);
    await visit(const Key('primary-call'), CallScreen);

    await disposeApp(tester);
  });

  testWidgets('every primary action opens its screen in one tap (tablet)', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(800, 1200));

    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byType(TalkScreen), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.byKey(const Key('primary-call')));
    await settle(tester);
    expect(find.byType(CallScreen), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('main text is at least 24 px and buttons at least 56 px', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));

    final mainText = tester.widget<Text>(find.byKey(const Key('main-text')));
    expect(mainText.style?.fontSize, greaterThanOrEqualTo(24));
    expect(
      mainText.style?.fontSize,
      greaterThanOrEqualTo(AnchorTheme.baseTextSize),
    );

    final greeting = tester.widget<Text>(
      find.byKey(const Key('home-greeting')),
    );
    expect(greeting.style?.fontSize, greaterThanOrEqualTo(24));

    for (final key in <Key>[
      const Key('primary-talk'),
      const Key('primary-call'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(56), reason: '$key height');
      expect(size.width, greaterThanOrEqualTo(56), reason: '$key width');
    }

    await disposeApp(tester);
  });

  testWidgets('phone layout renders without overflow at 1.3x text', (
    tester,
  ) async {
    await pumpSignedIn(
      tester,
      state,
      size: const Size(390, 844),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);

    for (final key in <Key>[
      const Key('primary-talk'),
      const Key('primary-call'),
    ]) {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'opening $key at 1.3x');
      await tester.pageBack();
      await settle(tester);
    }
    await disposeApp(tester);
  });

  testWidgets('tablet layout renders without overflow at 1.3x text', (
    tester,
  ) async {
    await pumpSignedIn(
      tester,
      state,
      size: const Size(800, 1200),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);

    for (final key in <Key>[
      const Key('primary-talk'),
      const Key('primary-call'),
    ]) {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await settle(tester);
    }
    await disposeApp(tester);
  });

  testWidgets('sharing topics start private and can be enabled by the senior', (
    tester,
  ) async {
    // Settings are the family/setup phone's job now (architecture change
    // 2026-11-10): the senior signs in there and opens them from the hub.
    state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.ensureVisible(find.byKey(const Key('setup-settings')));
    await tester.tap(find.byKey(const Key('setup-settings')));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    const moodKey = ValueKey<String>('share-mood');
    await tester.ensureVisible(find.byKey(moodKey));
    expect(tester.widget<SwitchListTile>(find.byKey(moodKey)).value, isFalse);

    await tester.ensureVisible(find.byKey(const Key('consent-cloud')));
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('consent-cloud')))
          .value,
      isFalse,
    );

    await tester.ensureVisible(find.byKey(moodKey));
    await tester.tap(find.byKey(moodKey));
    await settle(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(moodKey)).value, isTrue);
    expect(state.consent.shareTopicAllowed('mood'), isTrue);

    await disposeApp(tester);
  });

  testWidgets('the senior can make this device the check-in device', (
    tester,
  ) async {
    state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    expect(state.preferences?.designatedDeviceId, isNull);

    await tester.ensureVisible(find.byKey(const Key('setup-settings')));
    await tester.tap(find.byKey(const Key('setup-settings')));
    await settle(tester);

    final key = find.byKey(const Key('settings-designated-device'));
    await tester.ensureVisible(key);
    await tester.tap(key);
    await settle(tester);

    expect(state.preferences?.designatedDeviceId, AnchorConfig.deviceId);
    // With the device designated, the proactive-invitation gate can open.
    expect(state.invitationScheduler.settings.designatedDeviceOk, isTrue);

    await disposeApp(tester);
  });

  testWidgets('offline Talk explains recovery and Stop still works', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));

    api.offline = true;
    await state.refresh();
    await tester.pump();
    expect(state.offline, isTrue);

    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);

    expect(find.text(L.zh.offlineTitle), findsOneWidget);
    expect(find.byKey(const Key('talk-type-instead')), findsOneWidget);
    expect(find.byKey(const Key('talk-text-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-control')));
    await settle(tester);
    expect(find.byKey(const Key('talk-stopped-panel')), findsOneWidget);
    expect(state.session, isNull);

    await disposeApp(tester);
  });

  testWidgets('caregiver mode has no senior stop control', (tester) async {
    api.asCaregiver();
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );
    expect(find.byType(CaregiverHomeScreen), findsOneWidget);
    expect(find.byType(SeniorHomeScreen), findsNothing);
    expect(find.byKey(const Key('stop-control')), findsNothing);
    expect(find.byKey(const Key('caregiver-digest')), findsOneWidget);
    expect(find.byKey(const Key('caregiver-prefs')), findsOneWidget);
    expect(find.byKey(const Key('caregiver-invite')), findsOneWidget);
    await disposeApp(tester);
  });

  group('foreground invitation', () {
    testWidgets('an eligible invitation offers two large actions and chats', (
      tester,
    ) async {
      api.eligibilityValue = eligibleNow();
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await settle(tester);

      expect(find.byKey(const Key('invitation-card')), findsOneWidget);
      expect(find.byKey(const Key('invitation-title')), findsOneWidget);
      // Still exactly three actions reachable: the invitation is not a fourth one.
      expect(find.byKey(const Key('primary-talk')), findsOneWidget);
      // Activities moved into the conversation: no separate Play door.
      expect(find.byKey(const Key('primary-play')), findsNothing);
      expect(find.byKey(const Key('primary-call')), findsOneWidget);

      for (final key in <Key>[
        const Key('invitation-accept'),
        const Key('invitation-dismiss'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(56), reason: '$key height');
        expect(size.width, greaterThanOrEqualTo(56), reason: '$key width');
      }

      await tester.tap(find.byKey(const Key('invitation-accept')));
      await settle(tester);

      expect(api.checkinOutcomes, <String>['accepted']);
      expect(api.sessionOrigins, contains('proactive'));
      expect(find.byType(TalkScreen), findsOneWidget);
      expect(state.session, isNotNull);
      // The proactive greeting is played through the same device voice.
      final speaker = state.speaker as SilentSpeaker;
      expect(speaker.spoken, isNotEmpty);

      await disposeApp(tester);
    });

    testWidgets('dismissing the invitation hides it and records the answer', (
      tester,
    ) async {
      api.eligibilityValue = eligibleNow();
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await settle(tester);
      expect(find.byKey(const Key('invitation-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('invitation-dismiss')));
      await settle(tester);

      expect(api.checkinOutcomes, <String>['dismissed']);
      expect(find.byKey(const Key('invitation-card')), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('a designated-device mismatch shows a hint, never an invite', (
      tester,
    ) async {
      api.eligibilityValue = blockedNow(<String>['designated_device_mismatch']);
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await settle(tester);

      expect(find.byKey(const Key('invitation-card')), findsNothing);
      expect(find.byKey(const Key('invitation-device-hint')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets(
      'no invitation is rendered without a fresh eligibility answer',
      (tester) async {
        api.eligibilityValue = blockedNow(<String>['outside_greeting_window']);
        await pumpSignedIn(tester, state, size: const Size(390, 844));
        await settle(tester);

        expect(find.byKey(const Key('invitation-card')), findsNothing);
        expect(find.byKey(const Key('invitation-device-hint')), findsNothing);

        await disposeApp(tester);
      },
    );

    testWidgets('Repeat replays the proactive greeting after accepting', (
      tester,
    ) async {
      api.eligibilityValue = eligibleNow();
      await pumpSignedIn(tester, state, size: const Size(390, 844));
      await settle(tester);
      await tester.tap(find.byKey(const Key('invitation-accept')));
      await settle(tester);
      expect(find.byType(TalkScreen), findsOneWidget);

      final speaker = state.speaker as SilentSpeaker;
      expect(speaker.spoken, hasLength(1));
      final greeting = speaker.spoken.single;
      expect(greeting, isNotEmpty);
      expect(state.lastAnchorText, greeting);

      await tester.ensureVisible(find.byKey(const Key('talk-repeat')));
      await tester.tap(find.byKey(const Key('talk-repeat')));
      await settle(tester);

      expect(speaker.spoken, hasLength(2));
      expect(speaker.spoken.last, greeting);

      await disposeApp(tester);
    });

    testWidgets('the invitation card survives 1.3x text on a phone', (
      tester,
    ) async {
      api.eligibilityValue = eligibleNow();
      await pumpSignedIn(
        tester,
        state,
        size: const Size(390, 844),
        textScale: 1.3,
      );
      await settle(tester);

      expect(find.byKey(const Key('invitation-card')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });
  });
}
