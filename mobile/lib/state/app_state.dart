import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../platform_policy.dart';
import '../services/api_client.dart';
import '../services/backend_address_store.dart';
import '../services/backend_discovery.dart';
import '../services/credential_store.dart';
import '../services/dialer.dart';
import '../services/invitation_scheduler.dart';
import '../services/reminders.dart';
import '../services/speech_input.dart';
import '../services/tts_service.dart';
import 'activity_grading.dart';
import 'activity_rotation.dart';
import 'inline_activity.dart';
import 'invitation_controller.dart';

/// Where the phone's automatic binding stands (2026-11-14).
enum PairingState {
  /// Nothing tried yet (the appliance never leaves this).
  idle,

  /// Broadcasting / sweeping the local network for the computer.
  searching,

  /// Connected: the address answers /api/v1/health.
  bound,

  /// Nothing answered. The family can still type an address by hand.
  notFound,
}

/// One place for every piece of app state: identity, consent snapshot,
/// preferences, the active conversation and the cancellation state (SPEC §9).
///
/// Screens never call [ApiClient] directly. Every network failure is turned into
/// a friendly [lastError] plus an [offline] flag, so a dead backend degrades
/// instead of crashing.
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.speaker,
    required this.microphone,
    required this.dialer,
    this.addressStore = const BackendAddressStore(),
    PlatformPolicy? policy,
    CredentialStore? credentials,
    BackendDiscovery? discovery,
    DateTime Function()? now,
    InvitationController? invitationController,
    Duration invitationInterval = const Duration(seconds: 60),
    this.probeDuration = const Duration(seconds: 3),
    this.answerDuration = const Duration(seconds: 4),
  }) : policy = policy ?? PlatformPolicy.instance,
       discovery = discovery ?? const BackendDiscovery(),
       credentials = credentials ?? CredentialStore(),
       _now = now ?? DateTime.now {
    invitations =
        invitationController ??
        InvitationController(
          api: api,
          now: () => _now(),
          zone: () => zone,
          interval: invitationInterval,
          onGreeting: _speak,
        );
    invitations.setGreetingPlayer(_speak);
    // Repaint when the voice pipeline moves, so the dock can say what is really
    // happening instead of guessing.
    final Speaker playbackSource = speaker;
    if (playbackSource is SpeechStatusSource) {
      (playbackSource as SpeechStatusSource).playback.addListener(
        notifyListeners,
      );
    }
  }

  final ApiClient api;
  final Speaker speaker;

  /// Finds the computer on the local network (phone only). Injectable so tests
  /// never touch a socket.
  final BackendDiscovery discovery;

  /// What the phone's auto-binding is doing right now, shown on the login screen.
  PairingState pairing = PairingState.idle;

  /// The computer found by auto-binding, for the status line.
  DiscoveredBackend? pairedBackend;
  final MicrophoneInput microphone;
  final Dialer dialer;
  final CredentialStore credentials;

  /// Which product this build is (Windows appliance vs family/setup phone).
  ///
  /// Screens read it through [policy]; on the setup phone every voice entry
  /// point below is a no-op, so an accidental caller can never open the mic.
  final PlatformPolicy policy;

  final DateTime Function() _now;

  /// How long the Settings screen records when the user tests the microphone.
  final Duration probeDuration;

  /// How long one Play voice answer listens before it stops by itself.
  ///
  /// The card asks for one short answer, so the tap needs no second "done"
  /// gesture: four seconds is enough to react and say a few syllables, and short
  /// enough that a silent room does not feel stuck. The senior can always tap the
  /// voice button again (or tap an option) when it was too short.
  final Duration answerDuration;

  /// Foreground proactive invitations (SPEC §6.2). Owned here so the loop lives
  /// with the app, not with a screen; Home only reports whether it is visible.
  late final InvitationController invitations;

  // -- identity ------------------------------------------------------------
  Profile? profile;

  // -- senior data ---------------------------------------------------------
  ConsentSnapshot consent = ConsentSnapshot.privateDefault;
  Preferences? preferences;
  List<MemoryItem> memories = <MemoryItem>[];
  ActivityFeed activityFeed = ActivityFeed.empty;
  List<Digest> digests = <Digest>[];
  List<AppNotification> notifications = <AppNotification>[];

  /// Unread 'your family update is ready' reminders (family side only).
  int get unreadDigestCount =>
      notifications.where((n) => n.kind == 'digest_ready' && n.isUnread).length;
  String digestNote = '';
  List<ScheduleProposal> proposals = <ScheduleProposal>[];
  CheckinSchedule schedule = CheckinSchedule.empty;
  CheckinEligibility eligibility = CheckinEligibility.unknown;
  ReminderState reminderState = ReminderState.empty;

  // -- caregiver data ------------------------------------------------------
  List<Relationship> relationships = <Relationship>[];

  // -- contacts (server list when available, otherwise local numbers) ------
  List<Contact> serverContacts = <Contact>[];
  final List<Contact> localContacts = <Contact>[];

  // -- conversation --------------------------------------------------------
  ConversationSession? session;
  List<Caption> captions = <Caption>[];
  TurnResult? lastTurn;

  /// The activity the latest chat turn offered, if any (product decision
  /// 2026-11-10: activities appear inside the conversation). It belongs to that
  /// turn: a later turn without an offer ends it, so the card can never drift
  /// away from the sentence it followed.
  InlineActivity? inlineActivity;

  /// Encouragement counter: one flower per correct activity answer.
  ///
  /// Deliberately *not* a score: a wrong answer never subtracts, nothing is
  /// compared between users, and the UI never calls this a level or a cognitive
  /// result. It exists so answering feels worth doing.
  int flowers = 0;

  /// True when the answer just given earned a flower (drives the "+1" line).
  bool lastAnswerAwarded = false;

  /// The last anchor sentence that was played/displayed — the proactive greeting
  /// or the latest reply. Repeat falls back to this, because a proactive
  /// greeting is not a stored turn.
  String _lastAnchorText = '';

  String get lastAnchorText => _lastAnchorText;

  bool recording = false;
  bool micUnavailable = false;
  bool micFailed = false;
  bool sendingTurn = false;

  /// True while [listenForAnswer] is capturing, so a double tap on Play's voice
  /// button can never start a second recording on top of the first.
  bool _answerListening = false;

  /// Invalidates an in-flight Play voice answer: Stop, a tap on an option, a new
  /// card and leaving the screen all bump this, so a clip that finishes late is
  /// thrown away instead of grading the wrong card.
  int _answerTicket = 0;

  /// The request that failed and can be retried without retyping (503 recovery).
  _PendingTurn? _pendingTurn;

  // -- model and speech providers -----------------------------------------
  /// What the backend will really use; null until it has been read once.
  ProviderStatus? providers;
  bool providersLoading = false;
  bool providerFeatureMissing = false;

  /// True only when the backend says a real recogniser is available. An unknown
  /// status is treated as "not available" so the mic can never fake a transcript.
  bool get asrConfigured => providers?.asr.configured ?? false;

  bool get llmConfigured => providers?.llm.configured ?? false;

  /// The honest "offline template reply" badge: shown as soon as the status is
  /// known and the LLM is not configured, hidden once a real model is set up.
  bool get showOfflineLlmBadge =>
      providers != null && !providers!.llm.configured;

  // -- ui status -----------------------------------------------------------
  bool busy = false;
  bool offline = false;
  ApiException? lastError;
  String? invitationToken;
  bool digestFeatureMissing = false;
  bool contactsFeatureMissing = false;
  bool speechActive = false;

  /// What the voice pipeline is doing right now, when the speaker can tell us.
  ///
  /// A bare speechActive boolean made the Talk screen say '麦克风已开' while
  /// the machine was still waiting on synthesis. Speakers that implement
  /// [SpeechStatusSource] report preparing / playing / fallback honestly; the
  /// others fall back to the boolean.
  ValueListenable<SpeechPhase> get speechPlayback => _speechPlayback;
  final ValueNotifier<SpeechPhase> _speechPlayback = ValueNotifier(
    SpeechPhase.idle,
  );

  SpeechPhase get speechPhase {
    final Speaker source = speaker;
    if (source is SpeechStatusSource) {
      return (source as SpeechStatusSource).playback.value;
    }
    return speechActive ? SpeechPhase.preparing : SpeechPhase.idle;
  }

  bool get signedIn => profile != null;

  bool get isSenior => profile?.isSenior ?? false;

  bool get isCaregiver => profile != null && !profile!.isSenior;

  String get language {
    final current = profile;
    if (current == null) return 'zh-CN';
    if (current.isSenior) return preferences?.language ?? current.locale;
    return current.locale;
  }

  L get l => L.of(language);

  String get displayName => profile?.displayName ?? '';

  ZoneSpec get zone => ZoneSpec.byId(profile?.timezone);

  List<Contact> get contacts =>
      serverContacts.isNotEmpty ? serverContacts : localContacts;

  bool get hasContacts => contacts.isNotEmpty;

  ActivityRotationController get rotation =>
      ActivityRotationController(feed: activityFeed);

  bool get hasActiveSession => session != null && session!.isActive;

  String get greetingKey {
    final hour = zone.wallTime(_now().toUtc()).hour;
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }

  /// Local invitation plan built from the current preferences and consent, so
  /// the UI can show "next check-in" without a round trip (pure Dart, SPEC §9).
  InvitationScheduler get invitationScheduler => InvitationScheduler(
    zone: zone,
    settings: ReminderSettings.fromPreferences(
      preferences ?? Preferences.defaults,
      consentActive: consent.proactiveInvitations,
      hasActiveSession: hasActiveSession,
      designatedDeviceOk:
          (preferences?.designatedDeviceId ?? AnchorConfig.deviceId) ==
          AnchorConfig.deviceId,
      snoozedUntilUtc: reminderState.snoozedUntilUtc,
    ),
    state: reminderState,
    title: l.appName,
    body: l.homePrompt,
  );

  ReminderPlan? get nextReminder =>
      invitationScheduler.nextPlan(_now().toUtc());

  // -- error handling ------------------------------------------------------
  void _fail(Object error) {
    if (error is ApiCancelled) return;
    if (error is ApiException) {
      lastError = error;
      if (error.isOffline) offline = true;
    } else {
      lastError = ApiException(code: 'unknown', message: '$error');
    }
    debugPrint('AppState error: $error');
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void clearOffline() {
    offline = false;
    notifyListeners();
  }

  /// Marks a feature endpoint as absent so the UI shows a friendly note instead
  /// of repeating a failing request (SPEC: degrade when an endpoint 404s).
  void _noteFeature(String path, ApiException error) {
    if (!error.isFeatureUnavailable) return;
    if (path == 'digests') {
      digestFeatureMissing = true;
    } else if (path == 'contacts') {
      contactsFeatureMissing = true;
    }
  }

  // -- voice gate (architecture change 2026-11-10) -------------------------
  /// True when this build may use the microphone or the speaker.
  ///
  /// Windows is the older adult's appliance and keeps the whole voice path;
  /// the family/setup phone has none of it.
  bool get voiceAllowed => !policy.setupApp;

  /// Returns true — and logs one line — when this platform may not use voice.
  ///
  /// Every voice entry point starts with this, so even a caller the UI would
  /// never reach (a restored route, a forgotten button, a proactive invitation)
  /// returns instead of opening the microphone or the speaker.
  bool _voiceBlocked(String what) {
    if (voiceAllowed) return false;
    debugPrint('Voice disabled on the setup phone: $what ignored.');
    return true;
  }

  // -- authentication ------------------------------------------------------
  Future<bool> signInDemo(int userId) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final authToken = await api.devLogin(userId);
      api.token = authToken.accessToken;
      credentials.save(
        token: authToken.accessToken,
        userId: userId,
        role: userId == AnchorConfig.seniorDemo.userId ? 'senior' : 'caregiver',
      );
      busy = false;
      final loaded = await refresh();
      return loaded;
    } on ApiException catch (error) {
      _fail(error);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> refresh() async {
    try {
      final me = await api.me();
      profile = me;
      offline = false;
      if (me.isSenior) {
        await _loadSenior();
        // A proactive check-in belongs to the appliance that can speak it; the
        // phone must not race the PC for today's one invitation (or start a
        // greeting it is not allowed to play).
        if (voiceAllowed) invitations.start();
      } else {
        // Caregivers never see or trigger an invitation.
        invitations.stop(reset: true);
        await _loadCaregiver();
      }
      lastError = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> _loadSenior() async {
    await loadPreferences();
    await loadConsents();
    await loadMemories();
    await loadActivities();
    await loadDigests();
    await loadContacts();
    await loadSchedule();
    await loadProposals();
    await loadProviders();
    await loadRewards();
  }

  Future<void> _loadCaregiver() async {
    await loadRelationships();
    await loadDigests();
    await loadContacts();
    await loadProposals();
    // The family sets the AI up with the older adult on the phone (2026-11-11),
    // so a caregiver reads the provider status too — the hub's read-out and the
    // AI screen would otherwise claim "not loaded" forever.
    await loadProviders();
  }

  // -- individual loaders --------------------------------------------------
  Future<void> loadPreferences() async {
    if (!isSenior) return;
    try {
      preferences = await api.preferences();
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadConsents() async {
    if (!isSenior) return;
    try {
      consent = await api.consents();
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadMemories() async {
    if (!isSenior) return;
    try {
      memories = await api.memories();
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadActivities() async {
    if (!isSenior) return;
    try {
      activityFeed = await api.activities();
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadDigests() async {
    try {
      final list = await api.digests();
      digests = list.digests;
      digestNote = list.note;
      digestFeatureMissing = false;
      notifyListeners();
    } on ApiException catch (error) {
      _noteFeature('digests', error);
      // Never keep an old family copy visible after a failed permission
      // refresh: consent may have changed since this copy was fetched.
      if (isCaregiver) digests = <Digest>[];
      if (!error.isFeatureUnavailable) _fail(error);
    }
  }

  Future<void> loadContacts() async {
    final seniorId = profile?.seniorId;
    if (seniorId == null) return;
    try {
      serverContacts = await api.contacts();
      contactsFeatureMissing = false;
      notifyListeners();
    } on ApiException catch (error) {
      _noteFeature('contacts', error);
      if (!error.isFeatureUnavailable) _fail(error);
    }
  }

  Future<void> loadSchedule() async {
    if (!isSenior) return;
    try {
      schedule = await api.checkinSchedule();
      eligibility = await api.checkinEligibility(
        deviceId: AnchorConfig.deviceId,
      );
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadRelationships() async {
    try {
      relationships = await api.relationships();
      notifyListeners();
    } on ApiException catch (error) {
      _fail(error);
    }
  }

  Future<void> loadProposals() async {
    try {
      proposals = await api.scheduleProposals();
      notifyListeners();
    } on ApiException catch (error) {
      if (!error.isFeatureUnavailable) _fail(error);
    }
  }

  // -- notifications (family) ---------------------------------------------
  /// In-app reminders the phone can read while it is open. No push: this
  /// version has no background channel (documented in HANDOFF/limitations).
  Future<void> loadNotifications() async {
    if (!isCaregiver) return;
    try {
      notifications = await api.notifications();
      notifyListeners();
    } on ApiException catch (error) {
      if (!error.isFeatureUnavailable) _fail(error);
    }
  }

  Future<bool> markNotificationRead(int id) async {
    try {
      await api.markNotificationRead(id);
      await loadNotifications();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  /// Turn every sharing topic off in one versioned consent request.
  ///
  /// 我的选择 needs this: revoking five topics one by one is five chances to give
  /// up half way, and the one thing a worried person wants is one switch
  /// (borrowed from the TA5 fork, 2026-11-12).
  Future<bool> stopAllSharing() async {
    if (!isSenior) return false;
    try {
      consent = await api.updateConsents(
        baseVersion: consent.version,
        changes: <ConsentChange>[
          for (final topic in ShareTopics.all)
            ConsentChange(
              capability: Capabilities.shareTopic,
              topic: topic,
              allowed: false,
            ),
        ],
      );
      lastError = null;
      await loadDigests();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (error.code == 'consent_version_conflict') await loadConsents();
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  // -- digests on demand (2026-11-12, borrowed from the fork) --------------
  /// Prepares last week's update without a worker.
  Future<bool> generateDigest() async {
    if (!isSenior) return false;
    try {
      final generated = await api.generateDigest();
      digests = <Digest>[
        generated,
        ...digests.where((d) => d.id != generated.id),
      ];
      lastError = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  /// The senior's explicit approval, then immediate delivery to the family.
  Future<bool> publishDigest(int id) async {
    if (!isSenior) return false;
    try {
      final published = await api.publishDigest(id);
      digests = <Digest>[
        published,
        ...digests.where((d) => d.id != published.id),
      ];
      lastError = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  // -- model and speech providers -----------------------------------------
  /// Reads the effective provider configuration. A missing endpoint (older
  /// backend) is not an error: the mic simply stays off, honestly.
  Future<bool> loadProviders() async {
    providersLoading = true;
    notifyListeners();
    try {
      providers = await api.providers();
      providerFeatureMissing = false;
      return true;
    } on ApiException catch (error) {
      if (error.isFeatureUnavailable) providerFeatureMissing = true;
      debugPrint('Provider status unavailable: $error');
      return false;
    } finally {
      providersLoading = false;
      notifyListeners();
    }
  }

  /// Saves a partial edit and adopts the server's answer (so the UI shows the
  /// new status without a second round trip).
  Future<ProviderStatus?> saveProviders(ProviderUpdate update) async {
    try {
      final status = await api.updateProviders(update);
      providers = status;
      providerFeatureMissing = false;
      lastError = null;
      notifyListeners();
      return status;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return null;
    }
  }

  /// Runs the real one-shot probe. Without [audio] the server answers ASR with
  /// `reason: "no_sample"` rather than claiming success.
  Future<ProviderTestResult?> testProviders({RecordedAudio? audio}) async {
    try {
      return await api.testProviders(
        audioB64: audio?.base64,
        audioMime: audio?.mimeType,
      );
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return null;
    }
  }

  /// Records a short clip for the Settings → microphone test.
  ///
  /// Returns null when the microphone is missing or nothing usable was captured;
  /// the caller must show that honestly and never substitute a transcript.
  Future<RecordedAudio?> captureProbeClip() async {
    // The phone has no microphone path at all: the ASR test button is phone-only
    // UI, but a stale caller must not be able to open the device either.
    if (_voiceBlocked('captureProbeClip')) return null;
    try {
      if (!await microphone.isAvailable()) {
        micUnavailable = true;
        notifyListeners();
        return null;
      }
      await microphone.startRecording();
      if (probeDuration > Duration.zero) {
        await Future<void>.delayed(probeDuration);
      }
      return await microphone.stopRecording();
    } on MicrophoneUnavailable catch (error) {
      micFailed = true;
      micUnavailable = true;
      debugPrint('Probe microphone unavailable: ${error.reason}');
      notifyListeners();
      return null;
    } catch (error) {
      micFailed = true;
      debugPrint('Probe microphone failed: $error');
      notifyListeners();
      return null;
    }
  }

  // -- preferences and consent ---------------------------------------------
  Future<bool> updatePreferences(Map<String, Object?> changes) async {
    try {
      preferences = await api.patchPreferences(changes);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> setConsent({
    required String capability,
    String topic = '',
    required bool allowed,
  }) async {
    try {
      consent = await api.updateConsents(
        baseVersion: consent.version,
        changes: <ConsentChange>[
          ConsentChange(capability: capability, topic: topic, allowed: allowed),
        ],
      );
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (error.code == 'consent_version_conflict') {
        await loadConsents();
      }
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> snoozeToday() async {
    final wall = zone.wallTime(_now().toUtc());
    final untilWall = DateTime(wall.year, wall.month, wall.day + 1);
    final untilUtc = zone.toUtc(untilWall);
    reminderState = reminderState.withSnooze(untilUtc);
    final ok = await updatePreferences(<String, Object?>{
      'snoozed_until': untilUtc.toIso8601String(),
    });
    if (!ok) {
      reminderState = reminderState.withSnooze(null);
    }
    notifyListeners();
  }

  // -- memories ------------------------------------------------------------
  Future<bool> approveMemory(int id) async {
    try {
      final updated = await api.approveMemory(id);
      memories = memories
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMemory(int id) async {
    try {
      await api.deleteMemory(id);
      memories = memories
          .where((item) => item.id != id)
          .toList(growable: false);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  // -- family links --------------------------------------------------------
  Future<String?> createInvitation() async {
    try {
      final invitation = await api.createInvitation();
      invitationToken = invitation.token;
      notifyListeners();
      return invitation.token;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> acceptInvitation(String token) async {
    try {
      await api.acceptInvitation(token.trim());
      await loadRelationships();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> approveRelationship(int id) async {
    try {
      await api.approveRelationship(id);
      await loadRelationships();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> revokeRelationship(int id) async {
    try {
      await api.revokeRelationship(id);
      await loadRelationships();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> proposeSchedule(Map<String, Object?> changes) async {
    try {
      final proposal = await api.createScheduleProposal(changes);
      proposals = <ScheduleProposal>[...proposals, proposal];
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> approveProposal(int id) async {
    try {
      await api.approveScheduleProposal(id);
      await loadProposals();
      await loadPreferences();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  // -- conversation --------------------------------------------------------
  Future<bool> startConversation({String origin = 'voluntary'}) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final opened = await api.openSession(
        origin: origin,
        deviceId: AnchorConfig.deviceId,
      );
      _adoptSession(opened);
      if (opened.greetingText != null && opened.greetingText!.isNotEmpty) {
        await _speak(opened.greetingText!);
      }
      lastError = null;
      return true;
    } on ApiException catch (error) {
      if (error.code == 'conflict' && error.conflictSessionId != null) {
        try {
          final existing = await api.session('${error.conflictSessionId}');
          _adoptSession(existing);
          return true;
        } on ApiException catch (retryError) {
          _fail(retryError);
        }
      } else {
        _fail(error);
      }
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _adoptSession(ConversationSession opened) {
    session = opened;
    captions = <Caption>[...opened.captions];
    lastTurn = null;
    recording = false;
    notifyListeners();
  }

  /// Adopts the session opened by [InvitationController.accept] so the Talk
  /// screen continues the proactive conversation instead of opening another one.
  void adoptProactiveSession(ConversationSession opened) {
    offline = false;
    _adoptSession(opened);
    final greeting = opened.greetingText;
    if (captions.isEmpty && greeting != null && greeting.isNotEmpty) {
      captions = <Caption>[
        Caption(role: 'anchor', text: greeting, at: _now().toUtc()),
      ];
      notifyListeners();
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    // The setup phone never plays speech — not a reply, not a greeting, not the
    // Play feedback. Returning before [speechActive] is touched keeps the UI
    // from ever showing a speaking state on the phone.
    if (_voiceBlocked('speak')) return;
    // Remember it even if the device voice is unavailable: Repeat must be able to
    // replay what the senior saw, not only what the speaker managed to say.
    _lastAnchorText = text;
    speechActive = true;
    notifyListeners();
    try {
      await speaker.speak(
        text,
        language: language == 'en' ? 'en-US' : 'zh-CN',
        slow: preferences?.isSlowPace ?? true,
      );
    } finally {
      // A throwing speaker must not leave the dock saying '正在朗读' forever.
      speechActive = false;
      notifyListeners();
    }
  }

  /// Speaks one short sentence for the Play screen: the story of a card, the
  /// teaching sentence after a tap, or a memory reply.
  ///
  /// Why this exists: Play already shows the exact same sentence on screen, so
  /// the voice is decoration and must never become a failure the senior has to
  /// deal with. [_speak] is the one path that knows the locale, the slow-pace
  /// preference and the remembered text, so this is a thin wrapper around it —
  /// never a second TTS route. Any speaker failure is swallowed here (and
  /// [speechActive] is put back, so the UI can never be stuck "speaking").
  Future<void> speakFeedback(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _speak(text);
    } catch (error) {
      speechActive = false;
      notifyListeners();
      debugPrint('Activity feedback speech failed: $error');
    }
  }

  Future<TurnResult?> sendText(
    String text, {
    bool keepInlineCard = false,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return null;
    if (session == null) {
      final opened = await startConversation();
      if (!opened || session == null) return null;
    }
    return _sendTurn(text: value, keepInlineCard: keepInlineCard);
  }

  Future<TurnResult?> _sendTurn({
    String? text,
    RecordedAudio? audio,
    bool addLocalCaption = true,
    bool keepInlineCard = false,
  }) async {
    final current = session;
    if (current == null) return null;
    sendingTurn = true;
    if (text != null && addLocalCaption) {
      captions = <Caption>[
        ...captions,
        Caption(role: 'senior', text: text, at: _now().toUtc()),
      ];
    }
    notifyListeners();
    try {
      final result = await api.turn(
        current.sessionId,
        text: text,
        audioB64: audio?.base64,
        audioMime: audio?.mimeType,
      );
      lastTurn = result;
      _pendingTurn = null;
      if (result.stopped) {
        await stopAll();
        return result;
      }
      if (result.activity != null) {
        inlineActivity = InlineActivity(
          offer: result.activity!,
          offeredAt: _now().toUtc(),
        );
      } else if (!keepInlineCard) {
        // A card belongs to the turn that offered it: a newer, card-less turn
        // ends it. The answered card of the current turn is the exception
        // ([keepInlineCard]), because collapsing it is what records the answer.
        inlineActivity = null;
      }
      if (result.captions.isNotEmpty) {
        captions = <Caption>[...result.captions];
      } else {
        final next = <Caption>[...captions];
        // Audio turns have no optimistic caption: show the transcript the server
        // actually recognised, or nothing at all — never a canned sentence.
        if (audio != null && result.transcript.isNotEmpty) {
          next.add(
            Caption(
              role: 'senior',
              text: result.transcript,
              at: _now().toUtc(),
            ),
          );
        }
        next.add(
          Caption(role: 'anchor', text: result.replyText, at: _now().toUtc()),
        );
        captions = next;
      }
      offline = false;
      lastError = null;
      notifyListeners();
      await _speak(result.replyText);
      return result;
    } on ApiCancelled {
      // The user pressed Stop: the late reply is discarded, nothing is shown.
      return null;
    } on ApiException catch (error) {
      // Keep the failed request so Retry can resend it verbatim.
      if (text != null || audio != null) {
        _pendingTurn = _PendingTurn(
          text: text,
          audio: audio,
          keepInlineCard: keepInlineCard,
        );
      }
      _fail(error);
      if (error.code == 'session_stopped') {
        session = null;
      }
      return null;
    } finally {
      sendingTurn = false;
      notifyListeners();
    }
  }

  /// Resends the last failed turn (the Talk screen offers this for a 503).
  ///
  /// The local caption from the first attempt is kept, so a text retry does not
  /// duplicate the senior's sentence. Returns null when nothing is pending.
  Future<TurnResult?> retryLastTurn() async {
    final pending = _pendingTurn;
    if (pending == null) return null;
    if (session == null) {
      final opened = await startConversation();
      if (!opened || session == null) return null;
    }
    return _sendTurn(
      text: pending.text,
      audio: pending.audio,
      addLocalCaption: false,
      keepInlineCard: pending.keepInlineCard,
    );
  }

  /// What Repeat would say right now, or null when nothing has been said yet.
  ///
  /// The server reply of the current turn wins (so a shortened/re-generated reply
  /// is what is repeated); otherwise the remembered greeting/reply is used.
  String? get repeatableText {
    final fromTurn = lastTurn?.replyText ?? '';
    if (fromTurn.isNotEmpty) return fromTurn;
    return _lastAnchorText.isEmpty ? null : _lastAnchorText;
  }

  /// Replays the last anchor sentence. See [repeatableText] for the precedence.
  Future<TurnResult?> repeatLastReply() async {
    final text = repeatableText;
    if (text == null) return null;
    await _speak(text);
    return lastTurn;
  }

  Future<bool> startRecording() async {
    // The family/setup phone has no microphone path: never open the device.
    if (_voiceBlocked('startRecording')) return false;
    // Without a real recogniser the backend would refuse the turn anyway, so
    // never record something that cannot be transcribed (the UI shows why).
    if (!asrConfigured) return false;
    // An earlier failure is not permanent: the headset may have disconnected, or
    // the app that was holding the microphone may have let go. Always retry, and
    // only keep [micUnavailable] as "the last attempt failed".
    try {
      // Silence our own voice first: the app speaks the greeting/reply and then
      // opens the microphone, so without this the mic records the speaker and
      // the recogniser transcribes Anchor talking to itself (measured: peak
      // 32000 = clipped, transcript garbage). No echo cancellation is assumed.
      await speaker.stop();
      await microphone.startRecording();
      recording = true;
      micFailed = false;
      micUnavailable = false;
      notifyListeners();
      return true;
    } on MicrophoneUnavailable catch (error) {
      recording = false;
      micFailed = true;
      micUnavailable = true;
      debugPrint('Microphone unavailable: ${error.reason}');
      notifyListeners();
      return false;
    }
  }

  Future<TurnResult?> stopRecordingAndSend() async {
    if (_voiceBlocked('stopRecordingAndSend')) return null;
    if (!recording) return null;
    recording = false;
    notifyListeners();
    final audio = await microphone.stopRecording();
    if (audio == null) {
      micFailed = true;
      notifyListeners();
      return null;
    }
    return _sendTurn(audio: audio);
  }

  Future<void> cancelRecording() async {
    _answerTicket++; // drops a Play voice answer that is still in flight
    recording = false;
    if (!_voiceBlocked('cancelRecording')) await microphone.cancel();
    notifyListeners();
  }

  /// Stop / Not now: instantaneous locally, then told to the server.
  ///
  /// The nonce is bumped *first*, so any response already on its way is dropped
  /// and can never re-open the conversation (SPEC §9, failure_stop_late_output).
  Future<void> stopAll() async {
    api.nonce.bump();
    // Any Play voice answer still being recorded or transcribed is now stale.
    _answerTicket++;
    recording = false;
    sendingTurn = false;
    captions = <Caption>[];
    lastTurn = null;
    inlineActivity = null;
    _pendingTurn = null;
    final current = session;
    session = null;
    speechActive = false;
    notifyListeners();

    if (voiceAllowed) {
      await microphone.cancel();
      await speaker.stop();
    }

    if (current != null) {
      // Fire and forget: the senior pressed Stop, so the screen must go quiet
      // immediately. Awaiting the server used to leave Stop looking dead for as
      // long as the request ran (up to the full HTTP timeout) and a second tap
      // stacked another stop on top of it.
      unawaited(_stopSessionOnServer(current));
    }
    notifyListeners();
  }

  Future<void> _stopSessionOnServer(ConversationSession stopped) async {
    try {
      await api.stopSession(stopped.sessionId);
    } on ApiException catch (error) {
      // Stopping locally already succeeded; a dead server changes nothing.
      debugPrint('Server stop failed: $error');
    } catch (error) {
      debugPrint('Server stop failed: $error');
    }
  }

  // -- activities ----------------------------------------------------------
  /// Records ONE short answer for Play and returns what was said.
  ///
  /// This is deliberately not a conversation: it never opens a session, never
  /// speaks, and never touches captions — the card is already open on screen.
  /// It uses the *same* microphone gate and the *same* error state as Talk
  /// ([micUnavailable], [micFailed], [lastError]), so a broken headset degrades
  /// in one place instead of two.
  ///
  /// Returns the recogniser's own words, or null when there is no usable device,
  /// nothing usable was captured, no recogniser is configured, the request failed
  /// (503 / 422, reported through [lastError]) or the answer was cancelled. The
  /// screen decides what a transcript means; nothing is invented here.
  ///
  /// [onRecordingComplete] fires after the microphone is closed and before the
  /// server is asked, which is what lets the screen show its "working" state.
  Future<String?> listenForAnswer({
    void Function()? onRecordingComplete,
  }) async {
    // Play's voice answer is appliance-only: on the phone it returns nothing and
    // the card stays a tap-only card.
    if (_voiceBlocked('listenForAnswer')) return null;
    // One recording at a time: a second tap must not stack two capture streams.
    if (_answerListening) return null;
    // Without a real recogniser the server would refuse the clip anyway, so the
    // microphone is never opened just to fail. The screen explains this instead.
    if (!asrConfigured) {
      debugPrint('Voice answer skipped: no speech recogniser configured.');
      return null;
    }
    _answerListening = true;
    final ticket = ++_answerTicket;
    var capturedAudio = false;
    try {
      // An earlier failure is not permanent (the headset may have reconnected),
      // so every attempt really tries again — exactly like Talk's mic button.
      micFailed = false;
      // Never listen while Anchor is still speaking: the mic would capture the
      // speaker (clipped) and the recogniser would transcribe our own words.
      await speaker.stop();
      await microphone.startRecording();
      recording = true;
      micUnavailable = false;
      notifyListeners();
      if (answerDuration > Duration.zero) {
        await Future<void>.delayed(answerDuration);
      }
      final audio = await microphone.stopRecording();
      recording = false;
      if (ticket != _answerTicket) return null; // cancelled while recording
      notifyListeners();
      if (audio == null || audio.base64.trim().isEmpty) {
        // The device opened but nothing usable came back: report "nothing heard",
        // never a made-up transcript and never "the microphone is unavailable".
        micFailed = true;
        debugPrint('Voice answer captured no audio.');
        notifyListeners();
        return null;
      }
      capturedAudio = true;
      onRecordingComplete?.call();
      final text = await api.transcribe(
        audioB64: audio.base64,
        audioMime: audio.mimeType,
      );
      if (ticket != _answerTicket) return null; // cancelled while transcribing
      final words = text.trim();
      // Length only: the words themselves are the senior's speech and are not
      // written to a log file.
      debugPrint('Voice answer transcribed: ${words.length} chars');
      if (words.isEmpty) return null;
      lastError = null;
      notifyListeners();
      return words;
    } on MicrophoneUnavailable catch (error) {
      recording = false;
      micFailed = true;
      micUnavailable = true;
      debugPrint('Voice answer microphone unavailable: ${error.reason}');
      notifyListeners();
      return null;
    } on ApiCancelled {
      // Stop won the race: the transcript is dropped, nothing is graded.
      return null;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return null;
    } catch (error) {
      recording = false;
      if (!capturedAudio) micFailed = true;
      debugPrint('Voice answer failed: $error');
      notifyListeners();
      return null;
    } finally {
      _answerListening = false;
      recording = false;
      notifyListeners();
    }
  }

  Future<bool> finishActivity({
    required String activityId,
    required bool completed,
    required int durationSeconds,
    bool? correct,
  }) async {
    try {
      final result = await api.recordActivitySession(
        activityId: activityId,
        completed: completed,
        durationSeconds: durationSeconds,
        correct: correct,
      );
      flowers = result.flowers;
      lastAnswerAwarded = result.awarded;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  /// Reads the encouragement counter (flowers). Never a score or a level.
  Future<void> loadRewards() async {
    try {
      flowers = await api.rewards();
      notifyListeners();
    } on ApiException catch (error) {
      debugPrint('Could not read rewards: $error');
    }
  }

  /// Answers the activity that is open **inside the conversation**.
  ///
  /// One tap, then the chat continues: the card locks immediately (a second tap
  /// can never grade it twice or post two turns), the result goes through the
  /// *existing* activity-session endpoint so rotation and observations stay
  /// correct, and the choice is posted as an ordinary chat turn so the model
  /// answers conversationally.
  ///
  /// The graded sentence is spoken after the model's reply, one after the other:
  /// the Windows voice stops whatever it is saying when the next sentence
  /// starts, so overlapping utterances would cut each other off.
  Future<void> answerInlineActivity(int index) async {
    final current = inlineActivity;
    if (current == null || current.answered || sendingTurn) return;
    final item = current.item;
    if (index < 0 || index >= item.options.length) return;
    final l = this.l;
    inlineActivity = current.withAnswer(index);
    notifyListeners();

    // Recorded first: the activity really was answered even if the reply fails.
    final recorded = await finishActivity(
      activityId: item.id,
      completed: true,
      durationSeconds: current.durationSeconds(_now()),
      // Only a graded card can earn a flower; a memory card passes null.
      correct: item.hasAnswer ? item.isCorrect(index) : null,
    );
    // Play's own rotation advanced on the server; refresh it so the Play screen
    // does not hand out the card the senior just answered.
    if (recorded) await loadActivities();

    final result = await sendText(
      l.inlineAnswer(item.options[index]),
      keepInlineCard: true,
    );
    if (result == null || result.stopped) return;
    await speakFeedback(gradeActivity(l, item, index).spoken);
  }

  // -- digest --------------------------------------------------------------
  Future<Digest?> digestForSeniorPreview() async =>
      digests.isEmpty ? null : digests.first;

  Future<bool> editDigest(Digest digest, List<DigestItem> items) async {
    try {
      final updated = await api.patchDigest(digest.id, items);
      digests = digests
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> approveDigest(Digest digest) async {
    try {
      var target = digest;
      if (target.isDraft) {
        target = await api.patchDigest(target.id, target.highlights);
      }
      final approved = await api.approveDigest(target.id);
      digests = digests
          .map((item) => item.id == approved.id ? approved : item)
          .toList(growable: false);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  // -- contacts and calling ------------------------------------------------
  void addLocalContact({required String label, required String phone}) {
    localContacts.add(
      Contact(id: -(localContacts.length + 1), label: label, phone: phone),
    );
    notifyListeners();
  }

  /// Resolves and records the call (best effort), then hands the number to the
  /// system dialer. Calling works with no network at all.
  Future<DialResult> callContact(Contact contact) async {
    try {
      await api.contactAction(contactId: contact.id);
    } on ApiException catch (error) {
      _noteFeature('contacts', error);
      debugPrint('contact-actions unavailable: $error');
    }
    final result = await dialer.dial(contact.phone);
    notifyListeners();
    return result;
  }

  // -- data rights ---------------------------------------------------------
  Future<bool> deleteMyData() async {
    try {
      await api.deleteData();
      memories = <MemoryItem>[];
      digests = <Digest>[];
      relationships = <Relationship>[];
      serverContacts = <Contact>[];
      activityFeed = ActivityFeed.empty;
      consent = ConsentSnapshot.privateDefault;
      inlineActivity = null;
      _lastAnchorText = '';
      notifyListeners();
      await refresh();
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
  }

  void signOut() {
    invitations.stop(reset: true);
    api.token = null;
    credentials.clear();
    profile = null;
    consent = ConsentSnapshot.privateDefault;
    preferences = null;
    memories = <MemoryItem>[];
    activityFeed = ActivityFeed.empty;
    digests = <Digest>[];
    proposals = <ScheduleProposal>[];
    schedule = CheckinSchedule.empty;
    eligibility = CheckinEligibility.unknown;
    relationships = <Relationship>[];
    serverContacts = <Contact>[];
    session = null;
    captions = <Caption>[];
    lastTurn = null;
    inlineActivity = null;
    _pendingTurn = null;
    providers = null;
    _lastAnchorText = '';
    lastError = null;
    invitationToken = null;
    reminderState = ReminderState.empty;
    busy = false;
    offline = false;
    notifyListeners();
  }

  /// Maps backend eligibility reasons onto the pure-Dart scheduler vocabulary.
  Set<InvitationBlocker> get serverBlockers =>
      eligibility.reasons.map((reason) {
        return switch (reason) {
          'consent_off' => InvitationBlocker.consentOff,
          'no_designated_device' => InvitationBlocker.notDesignatedDevice,
          'designated_device_mismatch' => InvitationBlocker.notDesignatedDevice,
          'paused' => InvitationBlocker.paused,
          'snoozed' => InvitationBlocker.snoozed,
          'daily_cap_reached' => InvitationBlocker.dailyCapReached,
          'quiet_hours' => InvitationBlocker.quietHours,
          'outside_greeting_window' => InvitationBlocker.outsideGreetingWindow,
          'active_session' => InvitationBlocker.activeSession,
          _ => InvitationBlocker.outsideGreetingWindow,
        };
      }).toSet();

  String get checkinTimeLabel {
    final first = schedule.entries.isEmpty ? null : schedule.entries.first;
    if (first == null) return '';
    return '${first.date} ${first.localTime}';
  }

  /// Local contact id used by the caregiver digest call action. The senior's
  /// saved number is the only thing a caregiver may dial (SPEC §9).
  Contact? get digestContact => contacts.isEmpty ? null : contacts.first;

  @override
  void dispose() {
    invitations.dispose();
    speaker.dispose();
    microphone.dispose();
    super.dispose();
  }

  /// Test/debug helper: human readable error for the last failure.
  String? get lastErrorText =>
      lastError == null ? null : l.errorText(lastError!);

  /// Exposed for the caregiver invitation screen copy.
  String get apiBaseLabel => api.baseUrl;

  /// True when the address in use was typed in on this device (and survives a
  /// restart). False on a fresh phone install: the compiled-in default is only a
  /// guess there, and the login screen says so.
  /// Where the phone remembers its address. Injectable so a test can never
  /// rewrite the machine's real file (that is exactly how the desktop app once
  /// ended up pointing at a test's fake address, 2026-11-14).
  final BackendAddressStore addressStore;

  /// True when the address in use was chosen on this device.
  bool addressChosenHere = false;

  /// Finds the computer and binds to it, with nobody typing an address.
  ///
  /// 2026-11-14. The order matters: an address that already works is never
  /// replaced (a demo on a fixed network must not start hunting), and anything
  /// discovery returns is verified over HTTP before it is adopted.
  ///
  /// On the **appliance** there is nothing to find: the backend is the process the
  /// app starts itself, so its address is the compiled-in loopback and never a LAN
  /// address. This branch also heals a machine that was left pointing somewhere
  /// else — which happened: the desktop app once loaded a stored 192.168.43.57 and
  /// could not reach its own backend, i.e. exactly the failure this app must never
  /// show ("the computer itself must always connect").
  Future<bool> autoBind() async {
    if (!policy.setupApp) {
      final loopback = AnchorConfig.apiBase;
      if (api.baseUrl != loopback) {
        debugPrint(
          'Appliance address ${api.baseUrl} is not the bundled backend; '
          'using $loopback.',
        );
        api.retarget(loopback);
        pairing = PairingState.idle;
      }
      final healthy = await _healthOf(loopback);
      if (healthy) addressChosenHere = true;
      notifyListeners();
      return healthy;
    }
    if (pairing == PairingState.searching) return false;
    pairing = PairingState.searching;
    notifyListeners();
    try {
      // 1. An address that already answers wins: no need to search, and it keeps
      //    a manually typed address working on a network with no broadcast.
      if (await _healthOf(api.baseUrl)) {
        pairing = PairingState.bound;
        notifyListeners();
        return true;
      }
      // 2. Search.
      final found = await discovery.discover();
      if (found == null) {
        pairing = PairingState.notFound;
        notifyListeners();
        return false;
      }
      pairedBackend = found;
      api.retarget(found.baseUrl);
      credentials.clear();
      api.token = null;
      profile = null;
      providers = null;
      offline = false;
      lastError = null;
      addressChosenHere = true;
      await addressStore.save(found.baseUrl);
      pairing = PairingState.bound;
      notifyListeners();
      return true;
    } on Object {
      pairing = PairingState.notFound;
      notifyListeners();
      return false;
    }
  }

  /// One quick health question, with its own short timeout (a search must not
  /// inherit the 90 s budget a spoken turn needs).
  Future<bool> _healthOf(String baseUrl) => discovery.healthOf(baseUrl);

  /// Repoints the whole client (and the screens that read the address) at
  /// another backend, then signs out.
  ///
  /// Why sign out: a token was issued by the old backend, so keeping it against
  /// a different server would produce 401s that look like a broken app. The
  /// caller persists the address; this only changes the live state.
  void retargetBackend(String baseUrl) {
    if (!api.retarget(baseUrl)) return;
    credentials.clear();
    api.token = null;
    profile = null;
    providers = null;
    offline = false;
    lastError = null;
    addressChosenHere = true;
    notifyListeners();
  }

  /// Parses a duration into whole seconds for `POST /activity-sessions`.
  static int secondsBetween(DateTime from, DateTime to) {
    final value = to.difference(from).inSeconds;
    return value < 0 ? 0 : value;
  }

  /// Convenience for tests and diagnostics.
  Map<String, Object?> get debugSnapshot => <String, Object?>{
    'signed_in': signedIn,
    'role': profile?.role,
    'language': language,
    'offline': offline,
    'session': session?.sessionId,
    'captions': captions.length,
    'digests': digests.length,
    'contacts': contacts.length,
    'consent_version': consent.version,
  };

  /// Kept for symmetry with the caregiver screen: whether the senior's digest can
  /// be dialled at all.
  bool get canCallFromDigest => digestContact != null;

  /// Used by the caregiver screen when a senior id arrives from `/me`.
  int? get linkedSeniorId => profile?.seniorId;

  /// Local evaluation of the proactive-invitation rules for the settings preview.
  InvitationDecision get invitationDecision =>
      invitationScheduler.evaluate(_now().toUtc());
}

/// A turn that failed for a recoverable reason and can be resent as-is.
class _PendingTurn {
  const _PendingTurn({this.text, this.audio, this.keepInlineCard = false});

  final String? text;
  final RecordedAudio? audio;

  /// The retry must keep the collapsed activity card (this turn answers it).
  final bool keepInlineCard;
}
