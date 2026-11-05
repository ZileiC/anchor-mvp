import 'dart:async';

import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/dialer.dart';
import 'package:anchor_app/services/speech_input.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/state/invitation_controller.dart';
import 'package:anchor_app/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anchor_app/app.dart';

/// Ticker double: tests decide when a poll happens, and no real timer leaks.
class ManualTicker implements InvitationTicker {
  Duration? interval;
  void Function()? onTick;
  int startCount = 0;
  int stopCount = 0;

  bool get isRunning => onTick != null;

  @override
  void start(Duration interval, void Function() onTick) {
    this.interval = interval;
    this.onTick = onTick;
    startCount++;
  }

  @override
  void stop() {
    onTick = null;
    stopCount++;
  }

  void tick() => onTick?.call();
}

/// Dialer double: records numbers instead of opening `tel:`.
class FakeDialer implements Dialer {
  FakeDialer({this.launched = true});

  bool launched;
  final List<String> dialled = <String>[];

  @override
  Future<DialResult> dial(String phone) async {
    dialled.add(phone);
    return DialResult(
      launched: launched,
      phone: phone,
      error: launched ? null : 'test_refused',
    );
  }
}

/// In-memory API double. It answers every endpoint the screens touch and mirrors
/// two behaviours of the real client that the UI depends on: the late-response
/// nonce guard and the offline error shape.
class FakeApi extends ApiClient {
  FakeApi()
    : super(baseUrl: 'http://fake', transport: const UnavailableTransport());

  Profile profile = const Profile(
    id: 1,
    role: 'senior',
    displayName: '林秀兰',
    timezone: 'Asia/Shanghai',
    locale: 'zh-CN',
    seniorId: 1,
    relationshipStatus: null,
  );

  Preferences prefs = Preferences.defaults;
  ConsentSnapshot consentSnapshot = ConsentSnapshot.privateDefault;
  List<MemoryItem> memoryList = <MemoryItem>[];
  ActivityFeed feed = ActivityFeed.empty;
  DigestList digestList = DigestList.empty;
  List<Contact> contactList = <Contact>[];
  List<Relationship> relationshipList = <Relationship>[];
  List<ScheduleProposal> proposalList = <ScheduleProposal>[];
  CheckinSchedule scheduleValue = CheckinSchedule.empty;
  CheckinEligibility eligibilityValue = CheckinEligibility.unknown;

  bool offline = false;
  bool digestMissing = false;
  bool conflictOnOpen = false;
  final List<String> stoppedSessions = <String>[];
  final List<String> sessionOrigins = <String>[];
  final List<String> checkinOutcomes = <String>[];
  int openSessionCalls = 0;
  int eligibilityCalls = 0;

  /// When set, `turn` waits for it — used to test that Stop discards a late reply.
  Completer<TurnResult>? pendingTurn;

  ApiException get offlineError => const ApiException(
    code: 'offline',
    message: 'no connection',
    recovery: <String>['retry', 'type_instead'],
  );

  void asCaregiver({String name = 'Mei'}) {
    profile = Profile(
      id: 2,
      role: 'caregiver',
      displayName: name,
      timezone: 'Asia/Shanghai',
      locale: 'zh-CN',
      seniorId: 1,
      relationshipStatus: 'accepted',
    );
  }

  // -- identity ------------------------------------------------------------
  @override
  Future<AuthToken> devLogin(int userId) async {
    if (offline) throw offlineError;
    return AuthToken(
      accessToken: 'token-$userId',
      tokenType: 'bearer',
      expiresIn: 3600,
    );
  }

  @override
  Future<Profile> me() async {
    if (offline) throw offlineError;
    return profile;
  }

  // -- senior data ---------------------------------------------------------
  @override
  Future<Preferences> preferences() async {
    if (offline) throw offlineError;
    return prefs;
  }

  @override
  Future<ConsentSnapshot> consents() async {
    if (offline) throw offlineError;
    return consentSnapshot;
  }

  @override
  Future<List<MemoryItem>> memories() async => memoryList;

  @override
  Future<ActivityFeed> activities() async {
    if (offline) throw offlineError;
    return feed;
  }

  @override
  Future<DigestList> digests() async {
    if (offline) throw offlineError;
    if (digestMissing) {
      throw const ApiException(
        code: 'not_found',
        message: 'Not Found',
        statusCode: 404,
      );
    }
    return digestList;
  }

  @override
  Future<List<Contact>> contacts() async {
    if (offline) throw offlineError;
    return contactList;
  }

  @override
  Future<CheckinSchedule> checkinSchedule() async {
    if (offline) throw offlineError;
    return scheduleValue;
  }

  @override
  Future<CheckinEligibility> checkinEligibility({String? deviceId}) async {
    eligibilityCalls++;
    if (offline) throw offlineError;
    return eligibilityValue;
  }

  /// Emulates the server: an attempt consumes today's cap.
  @override
  Future<CheckinAttempt> recordCheckinAttempt({
    required String outcome,
    String? deviceId,
  }) async {
    if (offline) throw offlineError;
    checkinOutcomes.add(outcome);
    eligibilityValue = CheckinEligibility(
      eligible: false,
      reasons: const <String>['daily_cap_reached'],
      capRemaining: 0,
      localTime: eligibilityValue.localTime,
      localDate: eligibilityValue.localDate,
      designatedDeviceOk: eligibilityValue.designatedDeviceOk,
    );
    return CheckinAttempt(
      recorded: true,
      outcome: outcome,
      capRemaining: 0,
      localDate: eligibilityValue.localDate,
    );
  }

  @override
  Future<List<ScheduleProposal>> scheduleProposals() async => proposalList;

  @override
  Future<List<Relationship>> relationships() async => relationshipList;

  // -- mutation ------------------------------------------------------------
  @override
  Future<ConsentSnapshot> updateConsents({
    required int baseVersion,
    required List<ConsentChange> changes,
  }) async {
    final items = <ConsentItem>[...consentSnapshot.items];
    for (final change in changes) {
      items.removeWhere(
        (item) =>
            item.capability == change.capability && item.topic == change.topic,
      );
      items.add(
        ConsentItem(
          capability: change.capability,
          topic: change.topic,
          allowed: change.allowed,
          version: baseVersion + 1,
        ),
      );
    }
    consentSnapshot = ConsentSnapshot(version: baseVersion + 1, items: items);
    return consentSnapshot;
  }

  @override
  Future<Preferences> patchPreferences(Map<String, Object?> changes) async {
    if (offline) throw offlineError;
    prefs = prefs.copyWith(
      greetingStart: changes['greeting_start'] as String?,
      greetingEnd: changes['greeting_end'] as String?,
      quietStart: changes['quiet_start'] as String?,
      quietEnd: changes['quiet_end'] as String?,
      paused: changes['paused'] as bool?,
      voicePace: changes['voice_pace'] as String?,
      shortReplies: changes['short_replies'] as bool?,
      language: changes['language'] as String?,
      dailyCap: changes['daily_cap'] as int?,
      snoozedUntil: changes['snoozed_until'] as String?,
      designatedDeviceId: changes['designated_device_id'] as String?,
      clearDesignatedDevice:
          changes.containsKey('designated_device_id') &&
          changes['designated_device_id'] == null,
    );
    return prefs;
  }

  @override
  Future<MemoryItem> approveMemory(int id) async {
    final updated = MemoryItem(
      id: id,
      fact: memoryList.firstWhere((item) => item.id == id).fact,
      approvalState: 'approved',
      approvedAt: DateTime.utc(2026, 3, 10),
    );
    memoryList = memoryList
        .map((item) => item.id == id ? updated : item)
        .toList(growable: false);
    return updated;
  }

  @override
  Future<void> deleteMemory(int id) async {
    memoryList = memoryList
        .where((item) => item.id != id)
        .toList(growable: false);
  }

  @override
  Future<InvitationToken> createInvitation({int expiresInHours = 24}) async =>
      InvitationToken(
        id: 1,
        token: 'demo-invite-token',
        expiresAt: '2026-03-11T00:00:00Z',
      );

  @override
  Future<InvitationAcceptance> acceptInvitation(String token) async {
    if (token != 'good-token') {
      throw const ApiException(
        code: 'invitation_invalid',
        message: 'invalid',
        statusCode: 410,
      );
    }
    return const InvitationAcceptance(relationshipId: 7, status: 'pending');
  }

  @override
  Future<ScheduleProposal> createScheduleProposal(
    Map<String, Object?> changes,
  ) async {
    if (offline) throw offlineError;
    final proposal = ScheduleProposal(
      id: 99,
      status: 'pending',
      payload: changes,
    );
    proposalList = <ScheduleProposal>[...proposalList, proposal];
    return proposal;
  }

  @override
  Future<ScheduleProposal> approveScheduleProposal(int id) async {
    final approved = ScheduleProposal(
      id: id,
      status: 'approved',
      payload: const <String, Object?>{},
    );
    proposalList = proposalList
        .map((item) => item.id == id ? approved : item)
        .toList(growable: false);
    return approved;
  }

  // -- conversation --------------------------------------------------------
  @override
  Future<ConversationSession> openSession({
    String origin = 'voluntary',
    String? deviceId,
  }) async {
    openSessionCalls++;
    if (offline) throw offlineError;
    if (conflictOnOpen) {
      throw const ApiException(
        code: 'conflict',
        message: 'A conversation is already open.',
        statusCode: 409,
        extra: <String, Object?>{'session_id': 'existing-1'},
      );
    }
    sessionOrigins.add(origin);
    return ConversationSession(
      sessionId: 'session-${sessionOrigins.length}',
      state: 'active',
      micOn: true,
      greetingText: origin == 'proactive' ? '早上好。今天想聊点什么？' : null,
    );
  }

  @override
  Future<ConversationSession> session(String sessionId) async =>
      ConversationSession(
        sessionId: sessionId,
        state: 'active',
        micOn: true,
        greetingText: '早上好。今天想聊点什么？',
      );

  @override
  Future<TurnResult> turn(
    String sessionId, {
    String? text,
    String? audioB64,
    String? audioMime,
  }) async {
    final ticket = nonce.value;
    if (offline) throw offlineError;
    final result = pendingTurn == null
        ? TurnResult(
            transcript: text ?? '',
            replyText: '好的，我在听。',
            intent: 'chat',
            stopped: false,
          )
        : await pendingTurn!.future;
    // Mirror the real client: a reply that arrives after Stop is discarded.
    if (!nonce.isCurrent(ticket)) throw const ApiCancelled();
    return result;
  }

  @override
  Future<void> stopSession(String sessionId) async {
    stoppedSessions.add(sessionId);
  }

  // -- activities ----------------------------------------------------------
  @override
  Future<ActivitySessionResult> recordActivitySession({
    required String activityId,
    required bool completed,
    required int durationSeconds,
  }) async => ActivitySessionResult(
    recorded: true,
    activityId: activityId,
    observationRecorded: false,
  );

  // -- digest and contacts -------------------------------------------------
  @override
  Future<Digest> approveDigest(int id) async {
    final current = digestList.digests.firstWhere((item) => item.id == id);
    final approved = Digest(
      id: current.id,
      status: 'approved',
      periodStart: current.periodStart,
      periodEnd: current.periodEnd,
      items: current.items,
    );
    digestList = DigestList(<Digest>[approved]);
    return approved;
  }

  @override
  Future<Digest> patchDigest(int id, List<DigestItem> items) async {
    final current = digestList.digests.firstWhere((item) => item.id == id);
    final updated = Digest(
      id: current.id,
      status: 'awaiting_senior_approval',
      periodStart: current.periodStart,
      periodEnd: current.periodEnd,
      items: items,
    );
    digestList = DigestList(<Digest>[updated]);
    return updated;
  }

  @override
  Future<ContactAction> contactAction({
    required int contactId,
    bool? confirmed,
  }) async => ContactAction(
    id: 5,
    label: 'Mei',
    phone: '13800000000',
    dialUri: 'tel:13800000000',
  );

  @override
  Future<Map<String, int>> deleteData() async => <String, int>{'memories': 1};
}

/// A state wired to doubles: no plugins, no network, a frozen clock, a manual
/// invitation ticker (so no real timer leaks into a test).
AppState buildTestState(
  FakeApi api, {
  FakeDialer? dialer,
  ManualTicker? ticker,
  InvitationController? invitationController,
  DateTime Function()? now,
}) {
  final clock = now ?? (() => DateTime.utc(2026, 3, 10, 1, 30));
  return AppState(
    api: api,
    speaker: SilentSpeaker(),
    microphone: UnavailableMicrophoneInput(),
    dialer: dialer ?? FakeDialer(),
    now: clock,
    invitationController:
        invitationController ??
        InvitationController(
          api: api,
          now: clock,
          ticker: ticker ?? ManualTicker(),
        ),
  );
}

/// An eligible invitation answer, as the server would return it at 09:30 local.
CheckinEligibility eligibleNow({
  String localDate = '2026-03-10',
  int capRemaining = 1,
}) => CheckinEligibility(
  eligible: true,
  reasons: const <String>[],
  capRemaining: capRemaining,
  localTime: '09:30',
  localDate: localDate,
  designatedDeviceOk: true,
  windowStart: '09:00',
  windowEnd: '11:00',
  quietStart: '21:00',
  quietEnd: '08:00',
);

/// An ineligible answer with explicit server reasons.
CheckinEligibility blockedNow(
  List<String> reasons, {
  String localDate = '2026-03-10',
  int capRemaining = 1,
}) => CheckinEligibility(
  eligible: false,
  reasons: reasons,
  capRemaining: capRemaining,
  localTime: '12:00',
  localDate: localDate,
  designatedDeviceOk: !reasons.contains('designated_device_mismatch'),
);

/// One activity of each type, in a fixed rotation.
ActivityFeed threeActivityFeed() => const ActivityFeed(
  items: <ActivityItem>[
    ActivityItem(
      id: 'trivia-1',
      type: 'trivia',
      title: '一道小题',
      prompt: '哪一样是早餐？',
      minutes: 3,
      options: <String>['粥', '筷子', '雨伞'],
      answer: '粥',
    ),
    ActivityItem(
      id: 'story-1',
      type: 'story',
      title: '一个小故事',
      prompt: '讲讲你小时候的院子。',
      minutes: 3,
    ),
    ActivityItem(
      id: 'memory-1',
      type: 'memory',
      title: '记一记',
      prompt: '记住这三样：茶杯、钥匙、毛巾。',
      minutes: 3,
    ),
  ],
  rotation: <String>['trivia-1', 'story-1', 'memory-1'],
);

/// Pumps the whole app and signs in with the demo role buttons.
Future<void> pumpSignedIn(
  WidgetTester tester,
  AppState state, {
  bool caregiver = false,
  Size? size,
  double textScale = 1.0,
}) async {
  if (size != null) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    addTearDown(tester.view.reset);
  }
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(AnchorApp(state: state));
  await tester.pump();
  await tester.tap(
    find.byKey(
      caregiver ? const Key('login-caregiver') : const Key('login-senior'),
    ),
  );
  await settle(tester);
}

/// Pumps enough frames for async work *and* a full 300 ms route transition
/// without `pumpAndSettle` (some screens animate forever: progress bars, timers).
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Disposes the tree so timers and in-flight futures are cleaned up.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
