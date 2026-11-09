import 'package:flutter/foundation.dart';

import '../config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/credential_store.dart';
import '../services/dialer.dart';
import '../services/invitation_scheduler.dart';
import '../services/reminders.dart';
import '../services/speech_input.dart';
import '../services/tts_service.dart';
import 'activity_rotation.dart';
import 'invitation_controller.dart';

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
    CredentialStore? credentials,
    DateTime Function()? now,
    InvitationController? invitationController,
    Duration invitationInterval = const Duration(seconds: 60),
    this.probeDuration = const Duration(seconds: 3),
  }) : credentials = credentials ?? CredentialStore(),
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
  }

  final ApiClient api;
  final Speaker speaker;
  final MicrophoneInput microphone;
  final Dialer dialer;
  final CredentialStore credentials;
  final DateTime Function() _now;

  /// How long the Settings screen records when the user tests the microphone.
  final Duration probeDuration;

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

  /// The last anchor sentence that was played/displayed — the proactive greeting
  /// or the latest reply. Repeat falls back to this, because a proactive
  /// greeting is not a stored turn.
  String _lastAnchorText = '';

  String get lastAnchorText => _lastAnchorText;

  bool recording = false;
  bool micUnavailable = false;
  bool micFailed = false;
  bool sendingTurn = false;

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
        invitations.start();
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
  }

  Future<void> _loadCaregiver() async {
    await loadRelationships();
    await loadDigests();
    await loadContacts();
    await loadProposals();
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
    // Remember it even if the device voice is unavailable: Repeat must be able to
    // replay what the senior saw, not only what the speaker managed to say.
    _lastAnchorText = text;
    speechActive = true;
    notifyListeners();
    await speaker.speak(
      text,
      language: language == 'en' ? 'en-US' : 'zh-CN',
      slow: preferences?.isSlowPace ?? true,
    );
    speechActive = false;
    notifyListeners();
  }

  Future<TurnResult?> sendText(String text) async {
    final value = text.trim();
    if (value.isEmpty) return null;
    if (session == null) {
      final opened = await startConversation();
      if (!opened || session == null) return null;
    }
    return _sendTurn(text: value);
  }

  Future<TurnResult?> _sendTurn({
    String? text,
    RecordedAudio? audio,
    bool addLocalCaption = true,
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
        _pendingTurn = _PendingTurn(text: text, audio: audio);
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
    // Without a real recogniser the backend would refuse the turn anyway, so
    // never record something that cannot be transcribed (the UI shows why).
    if (!asrConfigured) return false;
    if (micUnavailable) return false;
    try {
      await microphone.startRecording();
      recording = true;
      micFailed = false;
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
    recording = false;
    await microphone.cancel();
    notifyListeners();
  }

  /// Stop / Not now: instantaneous locally, then told to the server.
  ///
  /// The nonce is bumped *first*, so any response already on its way is dropped
  /// and can never re-open the conversation (SPEC §9, failure_stop_late_output).
  Future<void> stopAll() async {
    api.nonce.bump();
    recording = false;
    sendingTurn = false;
    captions = <Caption>[];
    lastTurn = null;
    _pendingTurn = null;
    final current = session;
    session = null;
    speechActive = false;
    notifyListeners();

    await microphone.cancel();
    await speaker.stop();

    if (current != null) {
      try {
        await api.stopSession(current.sessionId);
      } on ApiException catch (error) {
        // Stopping locally already succeeded; a dead server changes nothing.
        debugPrint('Server stop failed: $error');
      }
    }
    notifyListeners();
  }

  // -- activities ----------------------------------------------------------
  Future<bool> finishActivity({
    required String activityId,
    required bool completed,
    required int durationSeconds,
  }) async {
    try {
      await api.recordActivitySession(
        activityId: activityId,
        completed: completed,
        durationSeconds: durationSeconds,
      );
      return true;
    } on ApiException catch (error) {
      _fail(error);
      notifyListeners();
      return false;
    }
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
  const _PendingTurn({this.text, this.audio});

  final String? text;
  final RecordedAudio? audio;
}
