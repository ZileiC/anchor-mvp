import 'dart:io';

import 'api_client.dart';
import 'android_tts_speaker.dart';
import 'backend_tts_speaker.dart';
import 'tts_service.dart';

/// Native build: read the real platform name and pick an implementation.
SpeakerTarget currentSpeakerTarget() =>
    speakerTargetFor(Platform.operatingSystem);

Speaker createPlatformSpeaker({ApiClient? api}) =>
    createSpeakerForTarget(currentSpeakerTarget(), api: api);

/// Windows must never reach `flutter_tts` (it crashes the process natively), so
/// it speaks with the backend's neural voice and keeps SAPI as the audible
/// fallback. Android and iOS get the backend's neural voice too, played by
/// `just_audio` with the device voice as fallback — the same audio, the same
/// Stop semantics. Anything exotic keeps the device voice alone; web is silent.
Speaker createSpeakerForTarget(SpeakerTarget target, {ApiClient? api}) =>
    switch (target) {
      // The real app always passes its own client (main.dart), so the token set
      // at login is reused; the default keeps this callable from a test.
      SpeakerTarget.windows => BackendTtsSpeaker(api: api ?? ApiClient()),
      SpeakerTarget.android ||
      SpeakerTarget.ios => AndroidTtsSpeaker(api: api ?? ApiClient()),
      SpeakerTarget.web => SilentSpeaker(),
      SpeakerTarget.other => TtsService(),
    };
