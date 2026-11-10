import 'api_client.dart';
import 'speaker.dart';
// `dart:io` only exists on native platforms: the stub keeps the web build
// compiling and makes speech a no-op there.
import 'speaker_factory_stub.dart'
    if (dart.library.io) 'speaker_factory_io.dart'
    as impl;

export 'speaker.dart';

/// The speaker this platform should use.
///
/// Windows → `BackendTtsSpeaker` (the backend's neural voice via
/// `MediaPlayer`, with the SAPI device voice as fallback), Android/iOS →
/// `AndroidTtsSpeaker` (the same neural voice, played by `just_audio`, with the
/// device voice as fallback), web → silent.
///
/// Pass the app's [api]: that same client carries the base URL and the bearer
/// token set at login, and the speaker re-reads `api.token` on every request.
/// Without it the factory still builds a working speaker around a default
/// client (tests and callers that have none).
Speaker createSpeaker({ApiClient? api}) => impl.createPlatformSpeaker(api: api);

/// Same choice, made explicitly (used by tests and by callers that already know
/// the platform).
Speaker createSpeakerForTarget(SpeakerTarget target, {ApiClient? api}) =>
    impl.createSpeakerForTarget(target, api: api);
