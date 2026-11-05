import 'dart:io';

import 'tts_service.dart';
import 'windows_sapi_speaker.dart';

/// Native build: read the real platform name and pick an implementation.
SpeakerTarget currentSpeakerTarget() =>
    speakerTargetFor(Platform.operatingSystem);

Speaker createPlatformSpeaker() =>
    createSpeakerForTarget(currentSpeakerTarget());

/// Windows must never reach `flutter_tts` (it crashes natively), so it gets the
/// SAPI speaker; mobile keeps device TTS; web and anything exotic stay silent.
Speaker createSpeakerForTarget(SpeakerTarget target) => switch (target) {
  SpeakerTarget.windows => WindowsSapiSpeaker(),
  SpeakerTarget.web => SilentSpeaker(),
  SpeakerTarget.android ||
  SpeakerTarget.ios ||
  SpeakerTarget.other => TtsService(),
};
