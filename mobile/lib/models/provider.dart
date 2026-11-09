import 'parse.dart';

/// One provider section (`llm` or `asr`) as `GET/PUT /providers` describes it.
///
/// The server never returns the API key itself, only a short [keyHint] such as
/// `sk-…abcd`, which is what the UI is allowed to display.
class ProviderSectionStatus {
  const ProviderSectionStatus({
    required this.configured,
    required this.mode,
    required this.engine,
    this.baseUrl,
    this.model = '',
    this.keyHint,
  });

  /// True only for a real provider (an HTTP endpoint or the local recogniser);
  /// the offline rule model and the test fake are *not* configured.
  final bool configured;

  /// `"http"` when the section uses a network endpoint, otherwise `"offline"`.
  final String mode;

  /// `http`, `windows-sapi`, `offline-rule`, `fake` or `none`.
  final String engine;

  final String? baseUrl;
  final String model;
  final String? keyHint;

  bool get usesHttp => mode == 'http' || engine == 'http';

  bool get isWindowsSapi => engine == 'windows-sapi';

  bool get hasKey => (keyHint ?? '').isNotEmpty;

  factory ProviderSectionStatus.fromJson(Map<String, Object?> json) =>
      ProviderSectionStatus(
        configured: asBool(json['configured']),
        mode: asString(json['mode'], 'offline'),
        engine: asString(json['engine'], 'none'),
        baseUrl: asStringOrNull(json['base_url']),
        model: asString(json['model']),
        keyHint: asStringOrNull(json['key_hint']),
      );

  /// What a section looks like when the server did not answer at all.
  static const ProviderSectionStatus unknown = ProviderSectionStatus(
    configured: false,
    mode: 'offline',
    engine: 'none',
  );
}

/// `GET /providers` and the body returned by `PUT /providers`.
class ProviderStatus {
  const ProviderStatus({required this.llm, required this.asr, this.updatedAt});

  final ProviderSectionStatus llm;
  final ProviderSectionStatus asr;
  final String? updatedAt;

  factory ProviderStatus.fromJson(Map<String, Object?> json) => ProviderStatus(
    llm: json['llm'] == null
        ? ProviderSectionStatus.unknown
        : ProviderSectionStatus.fromJson(asMap(json['llm'])),
    asr: json['asr'] == null
        ? ProviderSectionStatus.unknown
        : ProviderSectionStatus.fromJson(asMap(json['asr'])),
    updatedAt: asStringOrNull(json['updated_at']),
  );

  /// The state before anything was loaded, or after a reset.
  static const ProviderStatus unknown = ProviderStatus(
    llm: ProviderSectionStatus.unknown,
    asr: ProviderSectionStatus.unknown,
  );
}

/// One section of the answer from `POST /providers/test`.
///
/// The ASR half uses [reason] instead of [error] for the honest "no sample was
/// supplied" case (`no_sample`), which is not a provider failure.
class ProviderProbeResult {
  const ProviderProbeResult({
    required this.ok,
    this.latencyMs,
    this.replySample,
    this.textSample,
    this.error,
    this.reason,
  });

  final bool ok;
  final int? latencyMs;
  final String? replySample;
  final String? textSample;
  final String? error;
  final String? reason;

  factory ProviderProbeResult.fromJson(Map<String, Object?> json) =>
      ProviderProbeResult(
        ok: asBool(json['ok']),
        latencyMs: json['latency_ms'] == null
            ? null
            : asInt(json['latency_ms']),
        replySample: asStringOrNull(json['reply_sample']),
        textSample: asStringOrNull(json['text_sample']),
        error: asStringOrNull(json['error']),
        reason: asStringOrNull(json['reason']),
      );

  static const ProviderProbeResult unavailable = ProviderProbeResult(
    ok: false,
    error: 'provider_unavailable',
  );
}

/// The whole answer from `POST /providers/test`.
class ProviderTestResult {
  const ProviderTestResult({required this.llm, required this.asr});

  final ProviderProbeResult llm;
  final ProviderProbeResult asr;

  factory ProviderTestResult.fromJson(Map<String, Object?> json) =>
      ProviderTestResult(
        llm: json['llm'] == null
            ? ProviderProbeResult.unavailable
            : ProviderProbeResult.fromJson(asMap(json['llm'])),
        asr: json['asr'] == null
            ? ProviderProbeResult.unavailable
            : ProviderProbeResult.fromJson(asMap(json['asr'])),
      );
}

/// A partial edit for one section of `PUT /providers`.
///
/// Blank values are omitted: the server keeps what it already stored, and an
/// empty API key specifically means "keep the saved key". [clear] resets both
/// the URL and the key of that section and is sent on its own.
class ProviderSectionUpdate {
  const ProviderSectionUpdate({
    this.baseUrl,
    this.apiKey,
    this.model,
    this.clear = false,
  });

  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final bool clear;

  Map<String, Object?> toJson() {
    if (clear) return <String, Object?>{'clear': true};
    return <String, Object?>{
      if ((baseUrl ?? '').isNotEmpty) 'base_url': baseUrl,
      if ((apiKey ?? '').isNotEmpty) 'api_key': apiKey,
      if ((model ?? '').isNotEmpty) 'model': model,
    };
  }
}

/// Body of `PUT /providers`: one or both sections, nothing else.
class ProviderUpdate {
  const ProviderUpdate({this.llm, this.asr});

  final ProviderSectionUpdate? llm;
  final ProviderSectionUpdate? asr;

  Map<String, Object?> toJson() => <String, Object?>{
    if (llm != null) 'llm': llm!.toJson(),
    if (asr != null) 'asr': asr!.toJson(),
  };
}
