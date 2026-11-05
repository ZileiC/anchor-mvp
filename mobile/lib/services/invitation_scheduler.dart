import 'reminders.dart';

/// Why a proactive invitation may not happen right now. The set and order mirror
/// the backend eligibility rules (SPEC §6.2), so UI and server agree.
enum InvitationBlocker {
  consentOff,
  notDesignatedDevice,
  paused,
  snoozed,
  dailyCapReached,
  quietHours,
  outsideGreetingWindow,
  activeSession,
}

/// Result of evaluating the local schedule at one instant.
class InvitationDecision {
  const InvitationDecision({
    required this.eligible,
    required this.blockers,
    required this.localNow,
    required this.capRemaining,
    this.nextPlan,
  });

  final bool eligible;
  final List<InvitationBlocker> blockers;
  final DateTime localNow;
  final int capRemaining;
  final ReminderPlan? nextPlan;

  bool has(InvitationBlocker blocker) => blockers.contains(blocker);

  String get localTimeLabel => clockLabel(localNow);
}

/// Pure-Dart proactive-invitation scheduler (SPEC §9, S1/S7).
///
/// It owns no I/O and no clock: the caller passes `nowUtc`, which makes the
/// window, quiet-hours-crossing-midnight, daily-cap, snooze, timezone and DST
/// behaviour directly unit-testable (see `test/invitation_scheduler_test.dart`).
class InvitationScheduler {
  InvitationScheduler({
    required this.zone,
    required this.settings,
    this.state = ReminderState.empty,
    this.title = '',
    this.body = '',
  });

  final ZoneSpec zone;
  final ReminderSettings settings;
  final ReminderState state;
  final String title;
  final String body;

  static const int _horizonDays = 8;

  InvitationScheduler copyWith({
    ZoneSpec? zone,
    ReminderSettings? settings,
    ReminderState? state,
  }) => InvitationScheduler(
    zone: zone ?? this.zone,
    settings: settings ?? this.settings,
    state: state ?? this.state,
    title: title,
    body: body,
  );

  /// Every gate currently blocking an invitation, in the backend's order.
  List<InvitationBlocker> blockersAt(DateTime nowUtc) {
    final wall = zone.wallTime(nowUtc);
    final minute = wall.hour * 60 + wall.minute;
    final attempts = state.attemptsOn(localDateLabel(wall));
    final blockers = <InvitationBlocker>[];

    if (!settings.consentActive) blockers.add(InvitationBlocker.consentOff);
    if (!settings.designatedDeviceOk) {
      blockers.add(InvitationBlocker.notDesignatedDevice);
    }
    if (settings.paused) blockers.add(InvitationBlocker.paused);
    if (state.isSnoozedAt(nowUtc)) blockers.add(InvitationBlocker.snoozed);
    if (settings.dailyCap <= 0 || attempts >= settings.dailyCap) {
      blockers.add(InvitationBlocker.dailyCapReached);
    }
    if (minutesInWindow(
      minute,
      settings.quietStartMinute,
      settings.quietEndMinute,
    )) {
      blockers.add(InvitationBlocker.quietHours);
    }
    if (!minutesInWindow(
      minute,
      settings.greetingStartMinute,
      settings.greetingEndMinute,
    )) {
      blockers.add(InvitationBlocker.outsideGreetingWindow);
    }
    if (settings.hasActiveSession) {
      blockers.add(InvitationBlocker.activeSession);
    }
    return blockers;
  }

  InvitationDecision evaluate(DateTime nowUtc) {
    final wall = zone.wallTime(nowUtc);
    final blockers = blockersAt(nowUtc);
    final attempts = state.attemptsOn(localDateLabel(wall));
    final remaining = settings.dailyCap - attempts;
    return InvitationDecision(
      eligible: blockers.isEmpty,
      blockers: List<InvitationBlocker>.unmodifiable(blockers),
      localNow: wall,
      capRemaining: remaining < 0 ? 0 : remaining,
      nextPlan: blockers.isEmpty ? null : nextPlan(nowUtc),
    );
  }

  /// The next invitation that would actually be shown.
  ReminderPlan? nextPlan(DateTime nowUtc) {
    final plans = planNextDays(nowUtc, days: _horizonDays);
    return plans.isEmpty ? null : plans.first;
  }

  /// Planned invitations for the next `days` local days, honouring the window,
  /// quiet hours, the daily cap, snooze and the daylight-saving shift.
  List<ReminderPlan> planNextDays(DateTime nowUtc, {int days = 7}) {
    if (!settings.consentActive || settings.paused || settings.dailyCap <= 0) {
      return const <ReminderPlan>[];
    }
    final nowWall = zone.wallTime(nowUtc);
    final plans = <ReminderPlan>[];

    for (var offset = 0; offset <= days; offset++) {
      if (plans.length >= days) break;
      final day = DateTime(nowWall.year, nowWall.month, nowWall.day + offset);
      final date = localDateLabel(day);
      if (state.attemptsOn(date) >= settings.dailyCap) continue;

      var minute = settings.greetingStartMinute;
      final snoozeUntil = state.snoozedUntilUtc;
      if (snoozeUntil != null && snoozeUntil.isAfter(nowUtc)) {
        final snoozeWall = zone.wallTime(snoozeUntil);
        final snoozeDate = localDateLabel(snoozeWall);
        final order = snoozeDate.compareTo(date);
        if (order > 0) continue; // The whole day is still snoozed.
        if (order == 0) {
          final snoozeMinute = snoozeWall.hour * 60 + snoozeWall.minute;
          if (snoozeMinute > minute) minute = snoozeMinute;
        }
      }

      // Quiet hours win over the window: shift to the end of quiet time.
      if (minutesInWindow(
        minute,
        settings.quietStartMinute,
        settings.quietEndMinute,
      )) {
        minute = settings.quietEndMinute;
      }
      if (!minutesInWindow(
        minute,
        settings.greetingStartMinute,
        settings.greetingEndMinute,
      )) {
        continue;
      }

      final wall = DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      );
      final utc = zone.toUtc(wall);
      if (!utc.isAfter(nowUtc)) continue;
      plans.add(
        ReminderPlan(
          localDate: localDateLabel(wall),
          wallTime: wall,
          utcInstant: utc,
          title: title,
          body: body,
        ),
      );
    }
    return plans;
  }

  /// Records one invitation attempt in the local state (used after an invitation
  /// was actually shown). Returned state can be serialized and restored.
  ReminderState recordAttempt(DateTime nowUtc) =>
      state.recordAttempt(localDateLabel(zone.wallTime(nowUtc)));
}
