import 'package:anchor_app/state/invitation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Foreground proactive invitations (SPEC §6.2, guide §3.3/§5.2).
///
/// Every rule is the server's: the controller asks `GET /checkins/eligibility`
/// on a schedule and honours `eligible` + `reasons` verbatim. These tests drive
/// it with a fake API, a frozen clock and a manual ticker — no network, no timer.
void main() {
  late FakeApi api;
  late ManualTicker ticker;
  late DateTime clock;
  late List<String> greetings;

  setUp(() {
    api = FakeApi();
    ticker = ManualTicker();
    clock = DateTime.utc(2026, 3, 10, 1, 30); // 09:30 Asia/Shanghai
    greetings = <String>[];
  });

  InvitationController build() => InvitationController(
    api: api,
    now: () => clock,
    ticker: ticker,
    onGreeting: (String text) async => greetings.add(text),
  );

  /// Signs the controller in and brings Home on screen, letting the first poll
  /// complete.
  Future<InvitationController> onHome(InvitationController controller) async {
    controller.start();
    controller.setHomeVisible(true);
    await pumpEventQueue();
    return controller;
  }

  test('an eligible answer offers exactly one invitation', () async {
    api.eligibilityValue = eligibleNow();
    final controller = await onHome(build());

    expect(controller.offerVisible, isTrue);
    expect(api.eligibilityCalls, 1);

    // Polling again while the offer is up does not duplicate it.
    await controller.pollOnce();
    expect(controller.offerVisible, isTrue);
    expect(api.eligibilityCalls, 1);
    controller.dispose();
  });

  test(
    'accept records accepted, opens a proactive session and speaks',
    () async {
      api.eligibilityValue = eligibleNow();
      final controller = await onHome(build());

      final session = await controller.accept();

      expect(api.checkinOutcomes, <String>['accepted']);
      expect(api.sessionOrigins, <String>['proactive']);
      expect(session, isNotNull);
      expect(session!.greetingText, isNotNull);
      expect(greetings, <String>[session.greetingText!]);
      expect(controller.offerVisible, isFalse);
      expect(controller.attemptedToday, isTrue);
      controller.dispose();
    },
  );

  test(
    'after accepting, no second invitation is offered the same day',
    () async {
      api.eligibilityValue = eligibleNow();
      final controller = await onHome(build());
      await controller.accept();

      clock = clock.add(const Duration(minutes: 5));
      await controller.pollOnce();

      expect(controller.offerVisible, isFalse);
      expect(api.eligibilityCalls, 1, reason: 'no further polling after today');
      controller.dispose();
    },
  );

  test('dismissing records dismissed and never re-offers today', () async {
    api.eligibilityValue = eligibleNow();
    final controller = await onHome(build());

    await controller.dismiss();

    expect(api.checkinOutcomes, <String>['dismissed']);
    expect(controller.offerVisible, isFalse);
    expect(controller.dismissedToday, isTrue);

    clock = clock.add(const Duration(minutes: 5));
    await controller.pollOnce();
    expect(controller.offerVisible, isFalse);
    expect(api.eligibilityCalls, 1, reason: 'a dismissal is final for the day');
    controller.dispose();
  });

  test('the next local day may invite again', () async {
    api.eligibilityValue = eligibleNow();
    final controller = await onHome(build());
    await controller.dismiss();

    clock = clock.add(const Duration(hours: 24));
    api.eligibilityValue = eligibleNow(localDate: '2026-03-11');
    ticker.tick();
    await pumpEventQueue();

    expect(api.eligibilityCalls, 2);
    expect(controller.offerVisible, isTrue);
    controller.dispose();
  });

  test(
    'cap_remaining == 0 never invites, even if the server says eligible',
    () async {
      api.eligibilityValue = eligibleNow(capRemaining: 0);
      final controller = await onHome(build());
      expect(controller.offerVisible, isFalse);
      controller.dispose();
    },
  );

  test('every blocking reason suppresses the invitation verbatim', () async {
    const reasons = <String>[
      'quiet_hours',
      'outside_greeting_window',
      'paused',
      'snoozed',
      'daily_cap_reached',
      'active_session',
      'consent_off',
      'no_designated_device',
    ];

    for (final reason in reasons) {
      api.eligibilityValue = blockedNow(<String>[reason]);
      clock = clock.add(const Duration(seconds: 61));
      final fresh = InvitationController(
        api: api,
        now: () => clock,
        ticker: ManualTicker(),
      );
      await onHome(fresh);
      expect(fresh.offerVisible, isFalse, reason: reason);
      fresh.dispose();
    }
  });

  test(
    'a designated-device mismatch shows a hint, not an invitation',
    () async {
      api.eligibilityValue = blockedNow(<String>['designated_device_mismatch']);
      final controller = await onHome(build());

      expect(controller.offerVisible, isFalse);
      expect(controller.hint, InvitationHint.designatedDevice);
      controller.dispose();
    },
  );

  test('polling never happens faster than the injected interval', () async {
    api.eligibilityValue = blockedNow(<String>['outside_greeting_window']);
    final controller = await onHome(build());
    expect(api.eligibilityCalls, 1);

    await controller.pollOnce(); // same instant
    expect(api.eligibilityCalls, 1);

    clock = clock.add(const Duration(seconds: 59));
    await controller.pollOnce();
    expect(api.eligibilityCalls, 1);

    clock = clock.add(const Duration(seconds: 2));
    await controller.pollOnce();
    expect(api.eligibilityCalls, 2);
    controller.dispose();
  });

  test('the ticker is what drives ongoing polls', () async {
    api.eligibilityValue = blockedNow(<String>['outside_greeting_window']);
    final controller = await onHome(build());
    expect(api.eligibilityCalls, 1);

    clock = clock.add(const Duration(seconds: 61));
    ticker.tick();
    await pumpEventQueue();
    expect(api.eligibilityCalls, 2);

    controller.stop();
    expect(ticker.isRunning, isFalse);
    ticker.tick();
    await pumpEventQueue();
    expect(api.eligibilityCalls, 2);
    controller.dispose();
  });

  test('nothing is offered while Home is not the visible screen', () async {
    api.eligibilityValue = eligibleNow();
    final controller = build()..start();

    await controller.pollOnce();
    expect(controller.offerVisible, isFalse);
    expect(api.eligibilityCalls, 0);

    controller.setHomeVisible(false);
    await controller.pollOnce();
    expect(api.eligibilityCalls, 0);

    controller.setHomeVisible(true);
    await pumpEventQueue();
    expect(controller.offerVisible, isTrue);
    controller.dispose();
  });

  test('leaving Home pauses polling while a pending offer is kept', () async {
    api.eligibilityValue = eligibleNow();
    final controller = await onHome(build());
    expect(controller.offerVisible, isTrue);

    controller.setHomeVisible(false);
    clock = clock.add(const Duration(seconds: 61));
    await controller.pollOnce();
    expect(api.eligibilityCalls, 1);
    // An unanswered invitation is not thrown away; it is simply not shown.
    expect(controller.offerVisible, isTrue);
    controller.dispose();
  });

  test('accept resumes an already-open session instead of failing', () async {
    api.eligibilityValue = eligibleNow();
    api.conflictOnOpen = true;
    final controller = await onHome(build());

    final session = await controller.accept();

    expect(api.checkinOutcomes, <String>['accepted']);
    expect(session, isNotNull);
    expect(session!.sessionId, 'existing-1');
    expect(controller.offerVisible, isFalse);
    controller.dispose();
  });

  test('an offline poll surfaces the error and offers nothing', () async {
    api.offline = true;
    final controller = await onHome(build());
    expect(controller.offerVisible, isFalse);
    expect(controller.lastError, isNotNull);
    controller.dispose();
  });

  test('caregiver sign-in never starts the invitation loop', () async {
    api.asCaregiver();
    final state = buildTestState(api);

    await state.signInDemo(2);
    await pumpEventQueue();

    expect(state.invitations.running, isFalse);
    // Even if a Home-like screen reported visibility, nothing is polled.
    state.invitations.setHomeVisible(true);
    await pumpEventQueue();
    expect(api.eligibilityCalls, 0);
    state.dispose();
  });

  test('senior sign-in starts the invitation loop', () async {
    final state = buildTestState(api);
    await state.signInDemo(1);
    await pumpEventQueue();
    expect(state.invitations.running, isTrue);
    state.dispose();
  });
}
