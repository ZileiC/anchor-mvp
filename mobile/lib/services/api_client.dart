import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import '../models/parse.dart';

/// Structured API failure. `code` mirrors the backend error envelope (SPEC §6)
/// plus client-side `offline` / `cancelled` codes.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode = 0,
    this.recovery = const <String>[],
    this.extra = const <String, Object?>{},
  });

  final String code;
  final String message;
  final int statusCode;

  /// Recovery hints from the server (`retry`, `type_instead`, ...).
  final List<String> recovery;
  final Map<String, Object?> extra;

  bool get isOffline => code == 'offline';
  bool get isNotFound => statusCode == 404 || code == 'not_found';

  /// True when the endpoint itself is missing (feature not deployed yet), which
  /// the UI must degrade from with a friendly message rather than an error.
  bool get isFeatureUnavailable => statusCode == 404 || statusCode == 405;

  String? get conflictSessionId => asStringOrNull(extra['session_id']);

  int? get currentConsentVersion =>
      extra['current_version'] == null ? null : asInt(extra['current_version']);

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Thrown when a response arrives after the user pressed Stop (SPEC §9).
class ApiCancelled implements Exception {
  const ApiCancelled();

  @override
  String toString() => 'ApiCancelled: response discarded after Stop';
}

/// Monotonic request ticket. Bumping it invalidates every in-flight response.
class RequestNonce {
  int _value = 0;

  int get value => _value;

  int bump() => ++_value;

  bool isCurrent(int ticket) => ticket == _value;
}

/// A raw HTTP response, already read **as bytes** so UTF-8 is decoded explicitly
/// (a missing `charset` in `application/json` must not produce mojibake).
class TransportResponse {
  const TransportResponse(this.statusCode, this.bodyBytes);

  final int statusCode;
  final Uint8List bodyBytes;

  String get body => utf8.decode(bodyBytes, allowMalformed: true);
}

/// Seam for tests: a fake transport can answer with canned JSON or a delay.
abstract class HttpTransport {
  Future<TransportResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

/// Real transport over `package:http`.
class IoHttpTransport implements HttpTransport {
  IoHttpTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<TransportResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, url)..headers.addAll(headers);
    if (body != null) request.body = body;
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    return TransportResponse(response.statusCode, response.bodyBytes);
  }
}

/// Transport that fails every call — used by tests that only override methods.
class UnavailableTransport implements HttpTransport {
  const UnavailableTransport();

  @override
  Future<TransportResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    required Duration timeout,
  }) async {
    throw const ApiException(code: 'offline', message: 'No test transport');
  }
}

/// Typed client for every Anchor endpoint the UI needs (SPEC §6).
class ApiClient {
  ApiClient({String? baseUrl, HttpTransport? transport, Duration? timeout})
    : _baseUrl = _trimSlash(baseUrl ?? AnchorConfig.apiBase),
      _transport = transport ?? IoHttpTransport(),
      _timeout = timeout ?? AnchorConfig.requestTimeout;

  /// Where the backend lives. Read-only so that a screen can decide to change
  /// it (on the phone it is chosen at first run, not compiled in); the transport
  /// reads [baseUrl] on every request, so changing it takes effect immediately.
  String get baseUrl => _baseUrl;
  String _baseUrl;

  /// Points the whole client at another backend, e.g. the computer's LAN address
  /// typed in on the phone. Returns false for anything that is not http(s).
  bool retarget(String baseUrl) {
    final parsed = Uri.tryParse(baseUrl.trim());
    final usable =
        parsed != null &&
        parsed.hasAuthority &&
        (parsed.scheme == 'http' || parsed.scheme == 'https');
    if (!usable) return false;
    _baseUrl = _trimSlash(baseUrl);
    return true;
  }

  final HttpTransport _transport;
  final Duration _timeout;

  /// Bearer token from `POST /dev/login`; held in memory only.
  String? token;

  /// Invalidate every in-flight request by bumping this on Stop.
  final RequestNonce nonce = RequestNonce();

  static String _trimSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl${AnchorConfig.apiPrefix}$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  /// One request with the shared headers, timeout mapping and late-response
  /// guard, returned **as bytes**.
  ///
  /// JSON callers go through [_send], which decodes the body; the TTS mp3 uses
  /// this directly so its audio is never run through `utf8.decode`.
  Future<TransportResponse> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool guardNonce = true,
    String accept = 'application/json',
  }) async {
    final ticket = guardNonce ? nonce.value : -1;
    final headers = <String, String>{
      'Accept': accept,
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    TransportResponse response;
    try {
      response = await _transport.send(
        method,
        _uri(path, query),
        headers: headers,
        body: body == null ? null : jsonEncode(body),
        timeout: _timeout,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: 'offline',
        message: 'The server took too long to answer.',
        recovery: <String>['retry', 'type_instead'],
      );
    } on SocketException catch (error) {
      throw ApiException(
        code: 'offline',
        message: 'No connection to the server ($error).',
        recovery: const <String>['retry', 'type_instead'],
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        code: 'offline',
        message: 'Connection failed (${error.message}).',
        recovery: const <String>['retry', 'type_instead'],
      );
    } on HandshakeException {
      throw const ApiException(
        code: 'offline',
        message: 'Secure connection failed.',
        recovery: <String>['retry'],
      );
    }

    if (guardNonce && !nonce.isCurrent(ticket)) {
      throw const ApiCancelled();
    }
    return response;
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool guardNonce = true,
  }) async {
    final response = await _request(
      method,
      path,
      body: body,
      query: query,
      guardNonce: guardNonce,
    );

    final status = response.statusCode;
    final text = response.body;
    if (status >= 200 && status < 300) {
      if (text.trim().isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        return null;
      }
    }
    throw _errorFrom(status, text);
  }

  ApiException _errorFrom(int status, String text) {
    Object? decoded;
    try {
      decoded = text.trim().isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final map = asMap(decoded);
    final envelope = asMap(map['error']);
    final code = envelope.isNotEmpty
        ? asString(envelope['code'], _fallbackCode(status))
        : _fallbackCode(status);
    final message = envelope.isNotEmpty
        ? asString(envelope['message'], 'Request failed')
        : asString(map['detail'], 'Request failed');
    final extra = <String, Object?>{...envelope}
      ..remove('code')
      ..remove('message');
    return ApiException(
      code: code,
      message: message,
      statusCode: status,
      recovery: asStringList(extra['recovery']),
      extra: extra,
    );
  }

  static String _fallbackCode(int status) => switch (status) {
    400 => 'validation_error',
    401 => 'unauthorized',
    403 => 'forbidden',
    404 => 'not_found',
    405 => 'not_found',
    409 => 'conflict',
    422 => 'validation_error',
    500 => 'server_error',
    503 => 'provider_unavailable',
    _ => 'http_error',
  };

  // -- identity ------------------------------------------------------------
  Future<AuthToken> devLogin(int userId) async {
    final payload = await _send(
      'POST',
      '/dev/login',
      body: <String, Object?>{'user_id': userId},
    );
    return AuthToken.fromJson(asMap(payload));
  }

  Future<Profile> me() async =>
      Profile.fromJson(asMap(await _send('GET', '/me')));

  Future<HealthInfo> health() async =>
      HealthInfo.fromJson(asMap(await _send('GET', '/health')));

  // -- model and speech providers -----------------------------------------
  /// What the backend will really use right now, with the key masked.
  Future<ProviderStatus> providers() async =>
      ProviderStatus.fromJson(asMap(await _send('GET', '/providers')));

  /// Partial update: omitted fields keep their stored value, [clear] resets a
  /// section. Takes effect without restarting the backend.
  Future<ProviderStatus> updateProviders(ProviderUpdate update) async {
    final payload = await _send('PUT', '/providers', body: update.toJson());
    return ProviderStatus.fromJson(asMap(payload));
  }

  /// Real one-shot probe of the current configuration. With [audioB64] the ASR
  /// half transcribes that clip; without it the server honestly answers
  /// `reason: "no_sample"` instead of pretending speech works.
  Future<ProviderTestResult> testProviders({
    String? audioB64,
    String? audioMime,
  }) async {
    final payload = await _send(
      'POST',
      '/providers/test',
      body: audioB64 == null
          ? null
          : <String, Object?>{'audio_b64': audioB64, 'audio_mime': ?audioMime},
    );
    return ProviderTestResult.fromJson(asMap(payload));
  }

  /// `POST /tts`: the backend's neural voice, as raw `audio/mpeg` bytes.
  ///
  /// The bytes are returned untouched — an mp3 must never be decoded as UTF-8
  /// (unlike every JSON method here). [voice] null lets the server pick its
  /// default voice; [rate] uses the edge-tts format that the server forwards
  /// (`'-12%'`, `'+0%'`), and null keeps the server's own default pace.
  ///
  /// A 200 with an empty body is reported as an error rather than "no audio",
  /// so the caller falls back to the device voice instead of going silent.
  Future<Uint8List> ttsSpeech({
    required String text,
    String? voice,
    String? rate,
  }) async {
    final response = await _request(
      'POST',
      '/tts',
      body: <String, Object?>{'text': text, 'voice': voice, 'rate': rate},
      accept: 'audio/mpeg',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) {
        throw const ApiException(
          code: 'empty_audio',
          message: 'The voice service returned no audio.',
          recovery: <String>['retry', 'type_instead'],
        );
      }
      return response.bodyBytes;
    }
    throw _errorFrom(response.statusCode, response.body);
  }

  /// `POST /transcribe`: one recorded clip → the words that were said.
  ///
  /// Same JSON plumbing, bearer token and error mapping as every other method:
  /// a 503 (`provider_unavailable`) means no working recogniser right now and a
  /// 422 (`validation_error`) that the clip was unusable. [audioMime] defaults to
  /// `audio/wav` because that is the one format the microphone seam records, so
  /// the request always matches the fixed contract.
  ///
  /// The transcript is returned exactly as recognised (trimmed). Nothing is
  /// invented when the server sends no text: the caller gets an empty string and
  /// must treat that as "not heard".
  Future<String> transcribe({
    required String audioB64,
    String? audioMime,
  }) async {
    final mime = (audioMime ?? '').trim();
    final payload = await _send(
      'POST',
      '/transcribe',
      body: <String, Object?>{
        'audio_b64': audioB64,
        'audio_mime': mime.isEmpty ? 'audio/wav' : mime,
      },
    );
    return asString(asMap(payload)['text']).trim();
  }

  // -- invitations and family links ---------------------------------------
  Future<InvitationToken> createInvitation({int expiresInHours = 24}) async {
    final payload = await _send(
      'POST',
      '/invitations',
      body: <String, Object?>{'expires_in_hours': expiresInHours},
    );
    return InvitationToken.fromJson(asMap(payload));
  }

  Future<InvitationAcceptance> acceptInvitation(String token) async {
    final payload = await _send(
      'POST',
      '/invitations/accept',
      body: <String, Object?>{'token': token},
    );
    return InvitationAcceptance.fromJson(asMap(payload));
  }

  Future<List<Relationship>> relationships() async {
    final payload = asMap(await _send('GET', '/relationships'));
    return asList(payload['items'])
        .map((item) => Relationship.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<Relationship> approveRelationship(int id) async {
    final payload = await _send('POST', '/relationships/$id/approve');
    return Relationship.fromJson(asMap(payload));
  }

  Future<void> revokeRelationship(int id) async {
    await _send('DELETE', '/relationships/$id');
  }

  // -- consent -------------------------------------------------------------
  Future<ConsentSnapshot> consents() async =>
      ConsentSnapshot.fromJson(asMap(await _send('GET', '/consents')));

  Future<ConsentSnapshot> updateConsents({
    required int baseVersion,
    required List<ConsentChange> changes,
  }) async {
    final payload = await _send(
      'PUT',
      '/consents',
      body: <String, Object?>{
        'base_version': baseVersion,
        'changes': changes
            .map((change) => change.toJson())
            .toList(growable: false),
      },
    );
    return ConsentSnapshot.fromJson(asMap(payload));
  }

  // -- preferences and proposals ------------------------------------------
  Future<Preferences> preferences() async =>
      Preferences.fromJson(asMap(await _send('GET', '/preferences')));

  Future<Preferences> patchPreferences(Map<String, Object?> changes) async {
    final payload = await _send('PATCH', '/preferences', body: changes);
    return Preferences.fromJson(asMap(payload));
  }

  Future<List<ScheduleProposal>> scheduleProposals() async {
    final payload = asMap(await _send('GET', '/schedule-proposals'));
    return asList(payload['items'])
        .map((item) => ScheduleProposal.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<ScheduleProposal> createScheduleProposal(
    Map<String, Object?> changes,
  ) async {
    final payload = await _send(
      'POST',
      '/schedule-proposals',
      body: <String, Object?>{'payload': changes},
    );
    return ScheduleProposal.fromJson(asMap(payload));
  }

  Future<ScheduleProposal> approveScheduleProposal(int id) async {
    final payload = await _send('POST', '/schedule-proposals/$id/approve');
    return ScheduleProposal.fromJson(asMap(payload));
  }

  // -- proactive check-ins -------------------------------------------------
  Future<CheckinEligibility> checkinEligibility({String? deviceId}) async {
    final payload = await _send(
      'GET',
      '/checkins/eligibility',
      query: <String, String>{'device_id': ?deviceId},
    );
    return CheckinEligibility.fromJson(asMap(payload));
  }

  Future<CheckinAttempt> recordCheckinAttempt({
    required String outcome,
    String? deviceId,
  }) async {
    final payload = await _send(
      'POST',
      '/checkins/attempts',
      body: <String, Object?>{'outcome': outcome, 'device_id': deviceId},
    );
    return CheckinAttempt.fromJson(asMap(payload));
  }

  Future<CheckinSchedule> checkinSchedule() async =>
      CheckinSchedule.fromJson(asMap(await _send('GET', '/checkins/schedule')));

  // -- conversation --------------------------------------------------------
  Future<ConversationSession> openSession({
    String origin = 'voluntary',
    String? deviceId,
  }) async {
    final payload = await _send(
      'POST',
      '/sessions',
      body: <String, Object?>{'origin': origin, 'device_id': deviceId},
    );
    return ConversationSession.fromJson(asMap(payload));
  }

  Future<ConversationSession> session(String sessionId) async =>
      ConversationSession.fromJson(
        asMap(await _send('GET', '/sessions/$sessionId')),
      );

  /// One turn, either text or recorded audio (`audio_b64`). Audio is never stored.
  Future<TurnResult> turn(
    String sessionId, {
    String? text,
    String? audioB64,
    String? audioMime,
  }) async {
    final payload = await _send(
      'POST',
      '/sessions/$sessionId/turns',
      body: <String, Object?>{
        'text': ?text,
        'audio_b64': ?audioB64,
        'audio_mime': ?audioMime,
      },
    );
    return TurnResult.fromJson(asMap(payload));
  }

  /// Stop must still reach the server after the nonce was bumped, so it is
  /// exempt from the late-response guard (it is the cancellation itself).
  Future<void> stopSession(String sessionId) async {
    await _send('POST', '/sessions/$sessionId/stop', guardNonce: false);
  }

  // -- memories ------------------------------------------------------------
  Future<List<MemoryItem>> memories() async {
    final payload = asMap(await _send('GET', '/memories'));
    return asList(payload['items'])
        .map((item) => MemoryItem.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<MemoryItem> proposeMemory(String fact, {String? sourceRef}) async {
    final payload = await _send(
      'POST',
      '/memories',
      body: <String, Object?>{'fact': fact, 'source_ref': sourceRef},
    );
    return MemoryItem.fromJson(asMap(payload));
  }

  Future<MemoryItem> approveMemory(int id) async =>
      MemoryItem.fromJson(asMap(await _send('POST', '/memories/$id/approve')));

  Future<void> deleteMemory(int id) async {
    await _send('DELETE', '/memories/$id');
  }

  // -- activities ----------------------------------------------------------
  Future<ActivityFeed> activities() async =>
      ActivityFeed.fromJson(asMap(await _send('GET', '/activities')));

  Future<ActivitySessionResult> recordActivitySession({
    required String activityId,
    required bool completed,
    required int durationSeconds,
    bool? correct,
  }) async {
    final payload = await _send(
      'POST',
      '/activity-sessions',
      body: <String, Object?>{
        'activity_id': activityId,
        'completed': completed,
        'duration_seconds': durationSeconds,
        'correct': ?correct,
      },
    );
    return ActivitySessionResult.fromJson(asMap(payload));
  }

  /// The senior's encouragement counter (flowers). Never a score or a level.
  Future<int> rewards() async {
    final payload = await _send('GET', '/rewards');
    return asInt(asMap(payload)['flowers'], 0);
  }

  // -- digest + family bridge ---------------------------------------------
  Future<DigestList> digests() async =>
      DigestList.fromResponse(await _send('GET', '/digests'));

  Future<Digest> digest(int id) async =>
      Digest.fromJson(asMap(await _send('GET', '/digests/$id')));

  Future<Digest> patchDigest(int id, List<DigestItem> items) async {
    final payload = await _send(
      'PATCH',
      '/digests/$id',
      body: <String, Object?>{
        'items': items.map((item) => item.toJson()).toList(growable: false),
      },
    );
    return Digest.fromJson(asMap(payload));
  }

  Future<Digest> approveDigest(int id) async =>
      Digest.fromJson(asMap(await _send('POST', '/digests/$id/approve')));

  /// The saved contacts endpoint is not part of the frozen SPEC §6 surface, so
  /// callers must treat a 404 here as "unavailable" and use local numbers.
  Future<List<Contact>> contacts() async {
    final payload = asMap(await _send('GET', '/contacts'));
    return asList(payload['items'])
        .map((item) => Contact.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<ContactAction> contactAction({
    required int contactId,
    bool? confirmed,
  }) async {
    final payload = await _send(
      'POST',
      '/contact-actions',
      body: <String, Object?>{'contact_id': contactId, 'confirmed': ?confirmed},
    );
    return ContactAction.fromJson(asMap(payload));
  }

  // -- notifications and data rights --------------------------------------
  Future<List<AppNotification>> notifications() async {
    final payload = asMap(await _send('GET', '/notifications'));
    return asList(payload['items'])
        .map((item) => AppNotification.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<void> markNotificationRead(int id) async {
    await _send(
      'PATCH',
      '/notifications/$id',
      body: <String, Object?>{'read': true},
    );
  }

  Future<Map<String, int>> deleteData() async {
    final payload = asMap(
      await _send('DELETE', '/data', body: <String, Object?>{'confirm': true}),
    );
    final deleted = asMap(payload['deleted']);
    return deleted.map((key, value) => MapEntry(key, asInt(value)));
  }
}
