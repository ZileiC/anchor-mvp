import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/reminders.dart' show ZoneSpec, localDateLabel;

/// Timer seam so the polling loop is fully controllable in tests.
abstract class InvitationTicker {
  void start(Duration interval, void Function() onTick);

  void stop();
}

/// Production ticker: a periodic timer, cancelled when polling stops.
class PeriodicInvitationTicker implements InvitationTicker {
  Timer? _timer;

  @override
  void start(Duration interval, void Function() onTick) {
    stop();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Why the senior should be pointed at settings instead of being invited.
enum InvitationHint { designatedDevice }

/// Foreground proactive invitation (SPEC §6.2, guide §3.3/§5.2).
///
/// A small [ChangeNotifier] owned by `AppState` (not a screen, not the state
/// object itself): it owns the polling loop, the "already offered today" flags and
/// the offer lifecycle, while `Home` owns rendering/navigation and `AppState`
/// supplies the greeting playback. Every check-in rule is decided by the server —
/// this class only honours `eligible` and the returned `reasons` verbatim.
class InvitationController extends ChangeNotifier {
  InvitationController({
    required this.api,
    required this.now,
    ZoneSpec Function()? zone,
    this.deviceId = AnchorConfig.deviceId,
    this.interval = const Duration(seconds: 60),
    InvitationTicker? ticker,
    Future<void> Function(String greetingText)? onGreeting,
  }) : _zone = zone ?? (() => ZoneSpec.shanghai),
       _ticker = ticker ?? PeriodicInvitationTicker() {
    _onGreeting = onGreeting;
  }

  final ApiClient api;
  final DateTime Function() now;
  final String deviceId;
  final Duration interval;
  final ZoneSpec Function() _zone;
  final InvitationTicker _ticker;
  Future<void> Function(String greetingText)? _onGreeting;

  bool _running = false;
  bool _disposed = false;
  bool _homeVisible = false;
  bool _offerVisible = false;
  bool _polling = false;
  bool _busy = false;
  DateTime? _lastPollAt;
  String _localDate = '';
  String _dismissedOn = '';
  String _attemptedOn = '';
  InvitationHint? _hint;
  ApiException? _lastError;

  bool get running => _running;

  bool get homeVisible => _homeVisible;

  /// True while the Home screen should render the two-action invitation.
  bool get offerVisible => _offerVisible;

  /// True while an accept/dismiss call is in flight (buttons disabled).
  bool get busy => _busy;

  InvitationHint? get hint => _hint;

  ApiException? get lastError => _lastError;

  /// Local calendar day of the last eligibility answer (or of `now`).
  String get localDate => _localDate;

  /// Today's local calendar date, read from the clock so a day boundary is
  /// honoured even while the app keeps running overnight.
  String get _todayLocal => localDateLabel(_zone().wallTime(now()));

  bool get dismissedToday =>
      _dismissedOn.isNotEmpty && _dismissedOn == _todayLocal;

  bool get attemptedToday =>
      _attemptedOn.isNotEmpty && _attemptedOn == _todayLocal;

  /// AppState wires this so a proactive greeting is played through the same
  /// [Speaker] the conversation uses (SPEC §9).
  void setGreetingPlayer(Future<void> Function(String greetingText) player) {
    _onGreeting = player;
  }

  /// Starts polling. Idempotent; safe to call on every `refresh()`.
  void start() {
    if (_running) return;
    _running = true;
    _ticker.start(interval, _onTick);
    if (_homeVisible) unawaited(pollOnce());
    _notify();
  }

  void stop({bool reset = false}) {
    _ticker.stop();
    _running = false;
    _offerVisible = false;
    if (reset) {
      _hint = null;
      _lastError = null;
      _lastPollAt = null;
      _dismissedOn = '';
      _attemptedOn = '';
      _localDate = '';
    }
    _notify();
  }

  /// Called by the Home screen: invitations only act while Home is visible.
  void setHomeVisible(bool visible) {
    if (_homeVisible == visible) return;
    _homeVisible = visible;
    if (visible) {
      unawaited(pollOnce());
    }
  }

  void _onTick() {
    unawaited(pollOnce());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.stop();
    super.dispose();
  }

  /// One eligibility check. Public so tests can pump it deterministically.
  Future<void> pollOnce() async {
    if (!_running || !_homeVisible || _offerVisible || _polling || _busy) {
      return;
    }
    if (dismissedToday || attemptedToday) return;
    final at = now();
    final previous = _lastPollAt;
    // Never ask the server more often than the configured interval.
    if (previous != null && at.difference(previous) < interval) return;
    _polling = true;
    _lastPollAt = at;
    try {
      final eligibility = await api.checkinEligibility(deviceId: deviceId);
      _applyEligibility(eligibility);
    } on ApiException catch (error) {
      _lastError = error;
      _notify();
    } finally {
      _polling = false;
    }
  }

  void _applyEligibility(CheckinEligibility eligibility) {
    final fallbackDate = localDateLabel(_zone().wallTime(now()));
    _localDate = eligibility.localDate.isEmpty
        ? fallbackDate
        : eligibility.localDate;
    if (eligibility.eligible &&
        eligibility.capRemaining > 0 &&
        !dismissedToday &&
        !attemptedToday) {
      _hint = null;
      _lastError = null;
      _offerVisible = true;
    } else {
      _offerVisible = false;
      _hint = _hintFor(eligibility.reasons);
      if (eligibility.eligible && eligibility.capRemaining == 0) {
        // Defensive: the server said eligible but gave no room for today.
        _offerVisible = false;
      }
    }
    _notify();
  }

  InvitationHint? _hintFor(List<String> reasons) {
    if (reasons.contains('designated_device_mismatch') ||
        reasons.contains('no_designated_device')) {
      return InvitationHint.designatedDevice;
    }
    return null;
  }

  /// "聊一会儿": record the attempt as accepted, then open a proactive session.
  /// Returns the opened session, or null when the offer is gone / the call failed.
  Future<ConversationSession?> accept() async {
    if (!_offerVisible || _busy) return null;
    _busy = true;
    _notify();
    try {
      await api.recordCheckinAttempt(outcome: 'accepted', deviceId: deviceId);
      final session = await api.openSession(
        origin: 'proactive',
        deviceId: deviceId,
      );
      _offerVisible = false;
      _attemptedOn = _todayLocal;
      _lastError = null;
      final greeting = session.greetingText;
      final player = _onGreeting;
      if (greeting != null && greeting.isNotEmpty && player != null) {
        await player(greeting);
      }
      return session;
    } on ApiException catch (error) {
      if (error.code == 'conflict' && error.conflictSessionId != null) {
        // Someone (or a previous run) already has a session open: continue with
        // it rather than failing the invitation the senior just accepted.
        try {
          final existing = await api.session(error.conflictSessionId!);
          _offerVisible = false;
          _attemptedOn = _todayLocal;
          _lastError = null;
          return existing;
        } on ApiException catch (retryError) {
          _lastError = retryError;
        }
      } else {
        _lastError = error;
      }
      _offerVisible = false;
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// "今天不用": record the dismissal and never re-offer on this local day. The
  /// local flag stands even if the server call fails, because the senior said no.
  Future<bool> dismiss() async {
    if (_busy) return false;
    _offerVisible = false;
    _dismissedOn = _todayLocal;
    _notify();
    try {
      await api.recordCheckinAttempt(outcome: 'dismissed', deviceId: deviceId);
      _lastError = null;
      return true;
    } on ApiException catch (error) {
      _lastError = error;
      return false;
    } finally {
      _notify();
    }
  }
}
