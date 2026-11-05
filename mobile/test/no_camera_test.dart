import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S9 "no surveillance": Anchor must not request a camera, and the app manifest
/// must not request continuous recording of any kind.
void main() {
  File manifest() => File('android/app/src/main/AndroidManifest.xml');

  test('the app AndroidManifest exists in the package root', () {
    expect(
      manifest().existsSync(),
      isTrue,
      reason: 'flutter test must run from the mobile package root',
    );
  });

  test('no camera permission anywhere in the Android manifest', () {
    final text = manifest().readAsStringSync();
    expect(text.contains('android.permission.CAMERA'), isFalse);
    expect(text.toUpperCase().contains('CAMERA'), isFalse);
  });

  test('no recorder service or background capture declaration', () {
    final text = manifest().readAsStringSync();
    expect(text.contains('FOREGROUND_SERVICE_MICROPHONE'), isFalse);
    expect(text.contains('android.permission.RECORD_AUDIO'), isFalse);
    expect(text.contains('MediaRecorder'), isFalse);
  });

  test('the manifest does declare INTERNET for the Anchor API', () {
    expect(
      manifest().readAsStringSync().contains('android.permission.INTERNET'),
      isTrue,
    );
  });

  test('no camera plugin is a declared dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final banned in <String>['camera:', 'camera_', 'image_picker:']) {
      expect(pubspec.contains(banned), isFalse, reason: banned);
    }
  });
}
