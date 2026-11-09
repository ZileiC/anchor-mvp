import 'dart:io';

import 'api_client.dart';
import 'backend_tts_speaker.dart';
import 'tts_service.dart';

/// Native build: read the real platform name and pick an implementation.
SpeakerTarget currentSpeakerTarget() =>
    speakerTargetFor(Platform.operatingSystem);

Speaker createPlatformSpeaker({ApiClient? api}) =>
    createSpeakerForTarget(currentSpeakerTarget(), api: api);

/// Windows must never reach `flutter_tts` (it crashes the process natively), so
/// it speaks with the backend's neural voice and keeps SAPI as the audible
/// fallback. Mobile keeps device TTS; web and anything exotic stay silent.
Speaker createSpeakerForTarget(SpeakerTarget target, {ApiClient? api}) =>
    switch (target) {
      // The real app always passes its own client (main.dart), so the token set
      // at login is reused; the default keeps this callable from a test.
      SpeakerTarget.windows => BackendTtsSpeaker(api: api ?? ApiClient()),
      SpeakerTarget.web => SilentSpeaker(),
      SpeakerTarget.android ||
      SpeakerTarget.ios ||
      SpeakerTarget.other => TtsService(),
    };
