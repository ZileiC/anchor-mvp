import 'speaker.dart';

/// Web/unsupported build: there is no `dart:io`, so speech is a no-op.
SpeakerTarget currentSpeakerTarget() => SpeakerTarget.web;

Speaker createPlatformSpeaker() =>
    createSpeakerForTarget(currentSpeakerTarget());

Speaker createSpeakerForTarget(SpeakerTarget target) => SilentSpeaker();
