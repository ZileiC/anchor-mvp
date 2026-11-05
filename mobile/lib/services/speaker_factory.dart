import 'speaker.dart';
// `dart:io` only exists on native platforms: the stub keeps the web build
// compiling and makes speech a no-op there.
import 'speaker_factory_stub.dart'
    if (dart.library.io) 'speaker_factory_io.dart'
    as impl;

export 'speaker.dart';

/// The speaker this platform should use.
///
/// Windows → `WindowsSapiSpeaker` (System.Speech via PowerShell), Android/iOS →
/// `TtsService` (flutter_tts), web → silent.
Speaker createSpeaker() => impl.createPlatformSpeaker();

/// Same choice, made explicitly (used by tests and by callers that already know
/// the platform).
Speaker createSpeakerForTarget(SpeakerTarget target) =>
    impl.createSpeakerForTarget(target);
