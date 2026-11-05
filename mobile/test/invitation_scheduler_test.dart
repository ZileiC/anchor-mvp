import 'dart:convert';

import 'package:anchor_app/services/invitation_scheduler.dart';
import 'package:anchor_app/services/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proactive-invitation rules, pure Dart (SPEC §9): greeting window, quiet hours
/// crossing midnight, daily cap, pause/snooze, timezone, DST and restart.
void main() {
  ReminderSettings settings({
    int greetingStart = 9 * 60,
    int greetingEnd = 11 * 60,
    int quietStart = 21 * 60,
    int quietEnd = 8 * 60,
    int dailyCap = 1,
    bool paused = false,
    bool consentActive = true,
    bool designatedDeviceOk = true,
    bool hasActiveSession = false,
    DateTime? snoozedUntilUtc,
  }) => ReminderSettings(
    greetingStartMinute: greetingStart,
    greetingEndMinute: greetingEnd,
    quietStartMinute: quietStart,
    quietEndMinute: quietEnd,
    dailyCap: dailyCap,
    paused: paused,
    consentActive: consentActive,
    hasActiveSession: hasActiveSession,
    designatedDeviceOk: designatedDeviceOk,
    snoozedUntilUtc: snoozedUntilUtc,
  );

  InvitationScheduler scheduler(
    DateTime nowUtc, {
    ReminderSettings? config,
    ReminderState state = ReminderState.empty,
    ZoneSpec zone = ZoneSpec.shanghai,
  }) => InvitationScheduler(
    zone: zone,
    settings: config ?? settings(),
    state: state,
  );

  group('greeting window', () {
    test('is eligible inside the window', () {
      // 02:00 UTC == 10:00 in Asia/Shanghai.
      final decision = scheduler(DateTime.utc(2026, 3, 10, 2))
          .evaluate(DateTime.utc(2026, 3, 10, 2));
      expect(decision.eligible, isTrue);
      expect(decision.blockers, isEmpty);
      expect(decision.capRemaining, 1);
      expect(decision.localTimeLabel, '10:00');
    });

    test('is blocked outside the window when quiet hours do not apply', () {
      final now = DateTime.utc(2026, 3, 10, 4); // 12:00 local
      final decision = scheduler(
        now,
        config: settings(quietStart: 22 * 60, quietEnd: 6 * 60),
      ).evaluate(now);
      expect(decision.eligible, isFalse);
      expect(decision.has(InvitationBlocker.outsideGreetingWindow), isTrue);
      expect(decision.has(InvitationBlocker.quietHours), isFalse);
    });

    test(
      'the next plan lands on the next window even when today already passed',
      () {
        final now = DateTime.utc(2026, 3, 10, 6); // 14:00 local, window is over
        final plan = scheduler(now).nextPlan(now);
        expect(plan, isNotNull);
        expect(plan!.localDate, '2026-03-11');
        expect(plan.localTimeLabel, '09:00');
        expect(plan.utcInstant, DateTime.utc(2026, 3, 11, 1));
      },
    );
  });

  group('quiet hours crossing midnight', () {
    test('blocks at 23:00 and at 07:30 the same night', () {
      final lateEvening = DateTime.utc(2026, 3, 10, 15); // 23:00 local
      final earlyMorning = DateTime.utc(2026, 3, 10, 23, 30); // 07:30 local
      expect(
        scheduler(lateEvening)
            .evaluate(lateEvening)
            .has(InvitationBlocker.quietHours),
        isTrue,
      );
      expect(
        scheduler(earlyMorning)
            .evaluate(earlyMorning)
            .has(InvitationBlocker.quietHours),
        isTrue,
      );
    });

    test('does not block in the middle of the day', () {
      final noon = DateTime.utc(2026, 3, 10, 4); // 12:00 local
      expect(
        scheduler(noon).evaluate(noon).has(InvitationBlocker.quietHours),
        isFalse,
      );
    });

    test(
      'shifts a plan that would start inside quiet hours to the quiet end',
      () {
        final now = DateTime.utc(2026, 3, 10, 0, 30); // 08:30 local
        final configured = settings(
          greetingStart: 7 * 60,
          greetingEnd: 10 * 60,
          quietStart: 21 * 60,
          quietEnd: 8 * 60,
        );
        final plan = scheduler(now, config: configured).nextPlan(now);
        expect(plan, isNotNull);
        expect(plan!.localDate, '2026-03-11');
        expect(plan.localTimeLabel, '08:00');
      },
    );
  });

  group('daily cap', () {
    test('records attempts per local date and caps the day', () {
      final now = DateTime.utc(2026, 3, 10, 2); // 10:00 local
      final state = ReminderState.empty.recordAttempt('2026-03-10');
      final decision = scheduler(now, state: state).evaluate(now);
      expect(decision.has(InvitationBlocker.dailyCapReached), isTrue);
      expect(decision.capRemaining, 0);
    });

    test('next plan skips today when the cap is used and offers tomorrow', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      final state = ReminderState.empty.recordAttempt('2026-03-10');
      final plan = scheduler(now, state: state).nextPlan(now);
      expect(plan!.localDate, '2026-03-11');
      expect(plan.localTimeLabel, '09:00');
    });

    test('cap zero produces no plan at all', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      expect(
        scheduler(now, config: settings(dailyCap: 0)).planNextDays(now),
        isEmpty,
      );
    });
  });

  group('pause and snooze', () {
    test('pause blocks and yields no plan', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      final paused = scheduler(now, config: settings(paused: true));
      expect(paused.evaluate(now).has(InvitationBlocker.paused), isTrue);
      expect(paused.planNextDays(now), isEmpty);
    });

    test('snooze blocks until the chosen instant', () {
      final now = DateTime.utc(2026, 3, 10, 2); // 10:00 local
      final until = now.add(const Duration(hours: 1)); // 11:00 local
      final configured = settings(greetingStart: 9 * 60, greetingEnd: 13 * 60);
      final decision = scheduler(
        now,
        config: configured,
        state: ReminderState.empty.withSnooze(until),
      ).evaluate(now);
      expect(decision.has(InvitationBlocker.snoozed), isTrue);
    });

    test('after snooze ends the plan resumes at the snooze instant', () {
      final now = DateTime.utc(2026, 3, 10, 2); // 10:00 local
      final until = DateTime.utc(2026, 3, 10, 2, 30); // 10:30 local
      final configured = settings(greetingStart: 9 * 60, greetingEnd: 13 * 60);
      final plan = scheduler(
        now,
        config: configured,
        state: ReminderState.empty.withSnooze(until),
      ).nextPlan(now);
      expect(plan, isNotNull);
      expect(plan!.localDate, '2026-03-10');
      expect(plan.localTimeLabel, '10:30');
    });
  });

  group('timezone', () {
    test('the same instant is a different local time per zone', () {
      final instant = DateTime.utc(
        2026,
        3,
        10,
        1,
      ); // 09:00 Shanghai, 02:00 Berlin
      final shanghai = InvitationScheduler(
        zone: ZoneSpec.shanghai,
        settings: settings(quietStart: 22 * 60, quietEnd: 6 * 60),
      );
      final berlin = InvitationScheduler(
        zone: ZoneSpec.berlin,
        settings: settings(quietStart: 22 * 60, quietEnd: 6 * 60),
      );
      expect(shanghai.evaluate(instant).eligible, isTrue);
      final berlinDecision = berlin.evaluate(instant);
      expect(berlinDecision.eligible, isFalse);
      expect(
        berlinDecision.has(InvitationBlocker.outsideGreetingWindow),
        isTrue,
      );
      expect(berlinDecision.localTimeLabel, '02:00');
    });

    test('wall time converts back to the right UTC instant', () {
      expect(
        ZoneSpec.shanghai.toUtc(DateTime(2026, 3, 10, 9, 0)),
        DateTime.utc(2026, 3, 10, 1, 0),
      );
      expect(
        ZoneSpec.berlin.toUtc(DateTime(2026, 3, 28, 9, 0)),
        DateTime.utc(2026, 3, 28, 8, 0),
      );
      expect(
        ZoneSpec.berlin.toUtc(DateTime(2026, 3, 30, 9, 0)),
        DateTime.utc(2026, 3, 30, 7, 0),
      );
    });
  });

  group('daylight saving time', () {
    test('the local slot stays at 09:00 while the UTC instant shifts', () {
      final berlin = InvitationScheduler(
        zone: ZoneSpec.berlin,
        settings: settings(quietStart: 22 * 60, quietEnd: 6 * 60),
      );
      // EU DST starts on the last Sunday of March: 2026-03-29.
      final before = berlin
          .planNextDays(DateTime.utc(2026, 3, 28, 0, 30), days: 3)
          .map((plan) => plan.localDate)
          .toList();
      expect(before.first, '2026-03-28');
      final planBefore = berlin
          .planNextDays(DateTime.utc(2026, 3, 28, 0, 30))
          .first;
      final planAfter = berlin
          .planNextDays(DateTime.utc(2026, 3, 30, 0, 30))
          .first;
      expect(planBefore.localTimeLabel, '09:00');
      expect(planAfter.localTimeLabel, '09:00');
      expect(planBefore.utcInstant, DateTime.utc(2026, 3, 28, 8));
      expect(planAfter.utcInstant, DateTime.utc(2026, 3, 30, 7));
      expect(
        planAfter.utcInstant.difference(planBefore.utcInstant).inHours,
        47,
      );
    });

    test('offset changes exactly on the transition day', () {
      final start = DateTime.utc(2026, 3, 29, 1); // 02:00 CET -> 03:00 CEST
      expect(
        ZoneSpec.berlin.offsetMinutesAt(
          start.subtract(const Duration(minutes: 1)),
        ),
        60,
      );
      expect(ZoneSpec.berlin.offsetMinutesAt(start), 120);
    });
  });

  group('restart', () {
    test('a serialized state keeps the cap after an app restart', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      final state = ReminderState.empty.recordAttempt('2026-03-10');
      final encoded = jsonEncode(state.toJson());
      final restored = ReminderState.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(restored.attemptsOn('2026-03-10'), 1);
      final decision = scheduler(now, state: restored).evaluate(now);
      expect(decision.has(InvitationBlocker.dailyCapReached), isTrue);
    });

    test('the cap resets on the next local date without losing the state', () {
      final state = ReminderState.empty.recordAttempt('2026-03-10');
      final restored = ReminderState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
      );
      expect(restored.attemptsOn('2026-03-11'), 0);
      final nextMorning = DateTime.utc(2026, 3, 11, 1); // 09:00 local
      final schedulerNextDay = scheduler(nextMorning, state: restored);
      expect(schedulerNextDay.evaluate(nextMorning).eligible, isTrue);
    });

    test('an unknown stored timezone falls back to the pilot timezone', () {
      expect(ZoneSpec.byId('Mars/Olympus').id, 'Asia/Shanghai');
      expect(ZoneSpec.byId(null).id, 'Asia/Shanghai');
    });
  });

  group('other gates', () {
    test('consent off and a non-designated device both block', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      final off = scheduler(
        now,
        config: settings(consentActive: false),
      ).evaluate(now);
      expect(off.has(InvitationBlocker.consentOff), isTrue);
      final otherDevice = scheduler(
        now,
        config: settings(designatedDeviceOk: false),
      ).evaluate(now);
      expect(otherDevice.has(InvitationBlocker.notDesignatedDevice), isTrue);
    });

    test('an active conversation blocks the invitation', () {
      final now = DateTime.utc(2026, 3, 10, 2);
      final decision = scheduler(
        now,
        config: settings(hasActiveSession: true),
      ).evaluate(now);
      expect(decision.has(InvitationBlocker.activeSession), isTrue);
    });

    test(
      'window helper matches the backend: half-open and midnight crossing',
      () {
        expect(minutesInWindow(10 * 60, 9 * 60, 11 * 60), isTrue);
        expect(minutesInWindow(11 * 60, 9 * 60, 11 * 60), isFalse);
        expect(minutesInWindow(23 * 60, 21 * 60, 8 * 60), isTrue);
        expect(minutesInWindow(7 * 60, 21 * 60, 8 * 60), isTrue);
        expect(minutesInWindow(8 * 60, 21 * 60, 8 * 60), isFalse);
      },
    );
  });
}
