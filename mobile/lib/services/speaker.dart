/// Text-to-speech seam. The app must stay usable when the device voice is
/// missing, so every implementation degrades silently instead of throwing.
abstract class Speaker {
  Future<void> speak(String text, {String language, bool slow});

  Future<void> stop();

  Future<void> dispose();

  bool get lastAttemptFailed;
}

/// Which playback implementation a platform should use.
///
/// Windows is deliberately **not** handled by `flutter_tts`: its Windows plugin
/// crashes the process with an access violation (0xc0000005 in
/// `flutter_tts_plugin.dll`), so Windows uses SAPI through PowerShell instead.
enum SpeakerTarget { windows, android, ios, web, other }

/// Pure mapping from a platform name to the implementation choice.
///
/// `Platform.operatingSystem` values are used in production; tests (and the web
/// build) pass the name explicitly so this stays free of `dart:io`.
SpeakerTarget speakerTargetFor(String? platformName) {
  switch (platformName?.trim().toLowerCase()) {
    case 'windows':
      return SpeakerTarget.windows;
    case 'android':
      return SpeakerTarget.android;
    case 'ios':
      return SpeakerTarget.ios;
    case 'web':
      return SpeakerTarget.web;
    default:
      return SpeakerTarget.other;
  }
}

/// No-op speaker used by tests, on the web and where voice output is unwanted.
class SilentSpeaker implements Speaker {
  final List<String> spoken = <String>[];

  int get spokenCount => spoken.length;

  @override
  bool get lastAttemptFailed => false;

  @override
  Future<void> speak(
    String text, {
    String language = 'zh-CN',
    bool slow = true,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
