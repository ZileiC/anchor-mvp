import 'dart:async';

import 'package:anchor_app/services/api_client.dart';
import 'package:anchor_app/services/dialer.dart';
import 'package:anchor_app/services/speech_input.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/state/invitation_controller.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/services/backend_discovery.dart';
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

  /// Provider configuration the fake backend reports (default: nothing set up).
  ProviderStatus providerStatusValue = const ProviderStatus(
    llm: ProviderSectionStatus(
      configured: false,
      mode: 'offline',
      engine: 'offline-rule',
      model: 'deepseek-chat',
    ),
    asr: ProviderSectionStatus(
      configured: false,
      mode: 'offline',
      engine: 'none',
    ),
  );
  bool providersMissing = false;
  int providersCalls = 0;
  final List<ProviderUpdate> providerUpdates = <ProviderUpdate>[];
  ProviderTestResult providerTestResult = const ProviderTestResult(
    llm: ProviderProbeResult(ok: true, latencyMs: 42, replySample: '你好，我在这里。'),
    asr: ProviderProbeResult(ok: false, reason: 'no_sample'),
  );
  ApiException? testError;
  String? lastTestAudioB64;
  String? lastTestAudioMime;

  /// Recorded so tests can prove what was actually posted to the turn endpoint.
  int turnCalls = 0;
  String? lastTurnText;
  String? lastTurnAudioB64;
  ApiException? turnError;

  /// The reply every successful turn answers with. A test that wants the
  /// assistant's activity bridge sentence puts it in here (the real backend
  /// appends it to `reply_text`).
  String replyText = '好的，我在听。';

  /// The activity the next turn offers, or null for a turn without a card
  /// (`activity` on the turn response).
  TurnActivity? nextTurnActivity;

  // -- Play voice answers --------------------------------------------------
  /// What the fake recogniser returns for the next clip.
  String transcript = '';

  /// When set, `transcribe` waits for it before answering — lets a test sit in
  /// the screen's "working" state.
  Completer<void>? transcribeGate;

  /// When set, `transcribe` fails the way a dead recogniser does.
  ApiException? transcribeError;
  int transcribeCalls = 0;
  String? lastTranscribeAudioB64;
  String? lastTranscribeAudioMime;

  @override
  Future<String> transcribe({
    required String audioB64,
    String? audioMime,
  }) async {
    transcribeCalls++;
    lastTranscribeAudioB64 = audioB64;
    lastTranscribeAudioMime = audioMime;
    final gate = transcribeGate;
    if (gate != null) await gate.future;
    if (offline) throw offlineError;
    if (transcribeError != null) throw transcribeError!;
    return transcript;
  }

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

  // -- providers -----------------------------------------------------------
  @override
  Future<ProviderStatus> providers() async {
    providersCalls++;
    if (offline) throw offlineError;
    if (providersMissing) {
      throw const ApiException(
        code: 'not_found',
        message: 'Not Found',
        statusCode: 404,
      );
    }
    return providerStatusValue;
  }

  @override
  Future<ProviderStatus> updateProviders(ProviderUpdate update) async {
    if (offline) throw offlineError;
    providerUpdates.add(update);
    providerStatusValue = ProviderStatus(
      llm: update.llm == null
          ? providerStatusValue.llm
          : _applySection(providerStatusValue.llm, update.llm!),
      asr: update.asr == null
          ? providerStatusValue.asr
          : _applySection(providerStatusValue.asr, update.asr!),
      updatedAt: '2026-03-10T01:30:00Z',
    );
    return providerStatusValue;
  }

  @override
  Future<ProviderTestResult> testProviders({
    String? audioB64,
    String? audioMime,
  }) async {
    if (offline) throw offlineError;
    if (testError != null) throw testError!;
    lastTestAudioB64 = audioB64;
    lastTestAudioMime = audioMime;
    return providerTestResult;
  }

  /// Mirrors the backend: blank values keep the stored value, an empty key keeps
  /// the saved key, and `clear` resets the section.
  ProviderSectionStatus _applySection(
    ProviderSectionStatus current,
    ProviderSectionUpdate edit,
  ) {
    if (edit.clear) return ProviderSectionStatus.unknown;
    final base = edit.baseUrl ?? current.baseUrl;
    final model = edit.model ?? current.model;
    final keyHint = (edit.apiKey ?? '').isNotEmpty
        ? 'sk-…test'
        : current.keyHint;
    final configured = (base ?? '').isNotEmpty && keyHint != null;
    return ProviderSectionStatus(
      configured: configured,
      mode: configured ? 'http' : 'offline',
      engine: configured ? 'http' : current.engine,
      baseUrl: base,
      model: model,
      keyHint: keyHint,
    );
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
    turnCalls++;
    lastTurnText = text;
    lastTurnAudioB64 = audioB64;
    if (offline) throw offlineError;
    if (turnError != null) throw turnError!;
    // Like the backend: one offer per turn, and an item is never offered twice
    // in one conversation — so the next turn starts without a card.
    final offer = nextTurnActivity;
    nextTurnActivity = null;
    final result = pendingTurn == null
        ? TurnResult(
            transcript: text ?? (audioB64 == null ? '' : '这是识别结果'),
            replyText: replyText,
            intent: 'chat',
            stopped: false,
            activity: offer,
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
  /// Every finished session, in order, so tests can prove the silent POST
  /// (id, completed, measured seconds) still happens.
  final List<({String id, bool completed, int seconds})> activitySessions =
      <({String id, bool completed, int seconds})>[];

  @override
  Future<ActivitySessionResult> recordActivitySession({
    required String activityId,
    required bool completed,
    required int durationSeconds,
    bool? correct,
  }) async {
    activitySessions.add((
      id: activityId,
      completed: completed,
      seconds: durationSeconds,
    ));
    final awarded = correct == true;
    if (awarded) flowersAwarded += 1;
    return ActivitySessionResult(
      recorded: true,
      activityId: activityId,
      observationRecorded: false,
      awarded: awarded,
      flowers: flowersAwarded,
    );
  }

  /// Running flower count the fake reports back (and through [rewards]).
  int flowersAwarded = 0;

  @override
  Future<int> rewards() async => flowersAwarded;

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

/// Microphone double: captures a fixed WAV clip without touching a device.
class FakeMicrophoneInput implements MicrophoneInput {
  FakeMicrophoneInput({this.available = true});

  bool available;

  /// Set to make [startRecording] fail the way a busy/absent device does.
  String? failStartWith;
  String? _lastError;

  @override
  String? get lastError => _lastError;
  RecordedAudio? captured = const RecordedAudio(
    base64: 'UklGRiQAAABXQVZFZm10IBAAAAABAAEA',
    mimeType: 'audio/wav',
  );
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> startRecording() async {
    startCalls++;
    final failure = failStartWith;
    if (failure != null) {
      _lastError = failure;
      throw MicrophoneUnavailable(failure);
    }
    _lastError = null;
  }

  @override
  Future<RecordedAudio?> stopRecording() async {
    stopCalls++;
    return captured;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {}
}

/// A state wired to doubles: no plugins, no network, a frozen clock, a manual
/// invitation ticker (so no real timer leaks into a test).
///
/// [policy] states which product the test exercises. It defaults to the Windows
/// appliance (voice UI, no settings) rather than reading the host platform, so a
/// CI machine on Linux runs exactly the same suite, and a test that needs the
/// phone passes `const PlatformPolicy.setupApp()`.
AppState buildTestState(
  FakeApi api, {
  FakeDialer? dialer,
  ManualTicker? ticker,
  InvitationController? invitationController,
  DateTime Function()? now,
  MicrophoneInput? microphone,
  PlatformPolicy policy = const PlatformPolicy.seniorAppliance(),
  BackendDiscovery? discovery,
  Duration probeDuration = Duration.zero,
  Duration answerDuration = Duration.zero,
}) {
  final clock = now ?? (() => DateTime.utc(2026, 3, 10, 1, 30));
  return AppState(
    api: api,
    speaker: SilentSpeaker(),
    microphone: microphone ?? UnavailableMicrophoneInput(),
    dialer: dialer ?? FakeDialer(),
    policy: policy,
    discovery: discovery ?? const NoNetworkDiscovery(),
    now: clock,
    probeDuration: probeDuration,
    answerDuration: answerDuration,
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
///
/// Covers the whole content contract: a graded quiz with an explanation and a
/// gentle hint, a story that is read before its question, and a memory card
/// with one warm reply per option and no right answer at all.
ActivityFeed threeActivityFeed() => const ActivityFeed(
  items: <ActivityItem>[
    ActivityItem(
      id: 'trivia-1',
      type: 'trivia',
      title: '一道小题',
      prompt: '哪一样是早餐？',
      minutes: 3,
      options: <String>['粥', '筷子', '雨伞'],
      answerIndex: 0,
      explanation: '粥是早餐。筷子用来吃饭，雨伞是下雨用的。',
      wrongHint: '再想想早上常吃的东西。',
    ),
    ActivityItem(
      id: 'story-1',
      type: 'story',
      title: '一个小故事',
      prompt: '小时候的院子里，你最喜欢做什么？',
      minutes: 3,
      options: <String>['在树下乘凉', '在门口等信'],
      answerIndex: 0,
      explanation: '在树下乘凉，是很安静的夏天。',
      story: '小时候的院子有一棵枣树。夏天你常在树下坐着。',
    ),
    ActivityItem(
      id: 'memory-1',
      type: 'memory',
      title: '记一记',
      prompt: '记住这三样：茶杯、钥匙、毛巾。',
      minutes: 3,
      options: <String>['茶杯', '钥匙', '毛巾'],
      replies: <String>['茶杯在桌上。', '钥匙在门口的小盘子里。', '毛巾在柜子里。'],
    ),
  ],
  rotation: <String>['trivia-1', 'story-1', 'memory-1'],
);

/// Test discovery: nothing to find, ever.
///
/// The app's real discovery opens UDP sockets and sweeps /24s. Every widget test
/// that renders the login screen would otherwise run a network search on its
/// first frame. Reporting "the current address already works" keeps the pairing
/// state at bound, which is exactly the state a demo phone is in.
class NoNetworkDiscovery extends BackendDiscovery {
  const NoNetworkDiscovery({this.healthy = true});

  /// False models the phone that has not found anything yet.
  final bool healthy;

  @override
  Future<bool> healthOf(String baseUrl) async => healthy;

  @override
  Future<DiscoveredBackend?> discover({
    Duration budget = const Duration(seconds: 6),
    Future<bool> Function(String baseUrl)? verify,
  }) async => null;
}

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
