import 'api_client.dart';
import 'speaker.dart';

/// Web/unsupported build: there is no `dart:io`, so speech is a no-op.
///
/// The [ApiClient] parameter exists only so both branches of the conditional
/// import in `speaker_factory.dart` expose the same API; the web speaker never
/// uses it.
SpeakerTarget currentSpeakerTarget() => SpeakerTarget.web;

Speaker createPlatformSpeaker({ApiClient? api}) =>
    createSpeakerForTarget(currentSpeakerTarget(), api: api);

Speaker createSpeakerForTarget(SpeakerTarget target, {ApiClient? api}) =>
    SilentSpeaker();
