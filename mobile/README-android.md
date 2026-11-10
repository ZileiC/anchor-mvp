# Anchor on Android — build and the voice path

The Android app speaks with the **backend's neural voice**, the same voice the
Windows build uses. It is not the robotic device voice: `flutter_tts` is only a
fallback for when the backend or the player cannot deliver audio.

## What happens when a sentence is spoken

`AndroidTtsSpeaker` (`lib/services/android_tts_speaker.dart`) does, per
utterance, exactly what the Windows speaker does:

1. `POST /api/v1/tts` on the `ApiClient` the app already uses, so the bearer
   token from sign-in authorises it and the base URL is the one from
   `--dart-define=ANCHOR_API_BASE`;
2. the returned `audio/mpeg` bytes are written to one uniquely named
   `.mp3` in the app's temp directory;
3. `just_audio` (ExoPlayer/media3) plays that file to its end;
4. the file is deleted right after playback — nothing spoken is ever kept;
5. `stop()` silences the player immediately and still deletes the file;
6. if the backend answers an error/empty body, or the platform refuses to play
   the file, the sentence is spoken by `flutter_tts` instead **and**
   `lastAttemptFailed` reports `true`, so nothing pretends the neural voice
   worked when it did not.

`speaker_factory_io.dart` picks the implementation: Windows → the PowerShell
`MediaPlayer` speaker, Android/iOS → this one, web → silent.

## Permissions

`android/app/src/main/AndroidManifest.xml` declares `INTERNET` and
`android:usesCleartextTraffic="true"` (the demo backend is a laptop on the same
Wi-Fi speaking plain HTTP; Android 9+ blocks cleartext by default).

The microphone permission `android.permission.RECORD_AUDIO` is contributed by
the `record` plugin's own manifest and therefore **is** in the APK — the app's
manifest deliberately does not repeat it, because an S9 "no surveillance" test
(`test/no_camera_test.dart`) requires the app itself to request no capture
permission. Check the built APK with:

```powershell
& "$env:ANDROID_HOME\build-tools\<version>\aapt2.exe" dump permissions app-debug.apk
```

## Build a debug APK for a given LAN address

The backend address is baked in at build time; **no laptop IP is hardcoded in
the source**. Replace `192.168.1.100` with the IP of the machine running the
backend (`ipconfig` → the Wi-Fi adapter's IPv4 address), and make sure that
machine's firewall lets TCP 8077 in:

```powershell
cd mobile
flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://192.168.1.100:8077
```

The artifact lands in `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
With a connected device (USB debugging on):

```powershell
flutter install --debug --dart-define=ANCHOR_API_BASE=http://192.168.1.100:8077
```

The phone and the laptop must be on the same network, and the backend must
listen on `0.0.0.0` (not `127.0.0.1`) for the phone to reach it.

## The built artifact

`mobile/dist/android/anchor-app-debug.apk` (150.6 MiB — a debug APK carries the
debug engine for every ABI, so it is large on purpose; `--split-per-abi` or a
release build is far smaller) was built with the **demonstration** address
`http://192.168.1.100:8077`, sha256
`C3EC658EDF333139F08B183AB2EA02AE8FE1977E9693F166EF185F97A3969481`.

It was built from the committed baseline (`HEAD`) plus only the voice changes in
this branch, because at build time the working tree contained other teammates'
in-progress edits whose tests did not pass. Rebuild from the working tree with
the real LAN address before demoing:

```powershell
. .\scripts\_common.ps1 ; Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://<lan-ip>:8077
```

Checks run against the APK:

```powershell
$apk = 'mobile\dist\android\anchor-app-debug.apk'
& "$env:ANDROID_HOME\build-tools\36.0.0\aapt2.exe" dump permissions $apk   # INTERNET + RECORD_AUDIO
& "$env:ANDROID_HOME\build-tools\36.0.0\aapt2.exe" dump badging $apk       # minSdk 24, targetSdk 36
& "$env:ANDROID_HOME\build-tools\36.0.0\apksigner.bat" verify --print-certs $apk
```

The demo address is really baked in: `assets/flutter_assets/kernel_blob.bin`
inside the APK contains `192.168.1.100:8077`, and the dex contains
`com/ryanheise/just_audio` and `androidx/media3/exoplayer`.

## Environment notes for this machine

* Flutter 3.47.2, Android SDK 36, JDK 21. `flutter doctor` reports the Android
  toolchain as OK.
* `PUB_HOSTED_URL=https://pub.flutter-io.cn` and
  `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` are required; the
  default hosts are not reachable from here.
* The repository path contains non-ASCII characters, which crashes Dart's
  analysis server. Build and test through the ASCII mirror used by the repo
  scripts:

  ```powershell
  . .\scripts\_common.ps1
  Sync-MobileToAscii
  cd "$env:LOCALAPPDATA\anchor-build\mobile"
  flutter test ; flutter analyze ; flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://<lan-ip>:8077
  ```

* `dl.google.com` is unreliable from this network, so the machine carries
  `%USERPROFILE%\.gradle\init.gradle` pointing at Aliyun's Maven mirrors and a
  `%USERPROFILE%\.gradle\gradle.properties` with longer HTTP timeouts. Without
  them Gradle intermittently dies with
  `Could not resolve com.android.tools.build:gradle` /
  `Connection timed out` while configuring `:flutter_tts`. Those two files are
  machine setup, not part of this repository.

## Verified

Run on the committed baseline (`HEAD`) plus only the voice changes of this
branch, through the ASCII mirror:

* `flutter analyze` — **No issues found.**
* `flutter test` — **252 tests, all passed** (the 236 that existed before plus the
  16 that cover the Android speaker and the factory switch: `test/
  android_tts_speaker_test.dart` and `test/speaker_test.dart`).
* `flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://192.168.1.100:8077`
  — `√ Built build\app\outputs\flutter-apk\app-debug.apk` in 226.8 s.

Checked on the artifact itself (not on a device): `aapt2 dump permissions` lists
`android.permission.INTERNET` and `android.permission.RECORD_AUDIO`; the merged
manifest has `android:usesCleartextTraffic=true`; `apksigner verify` shows the
Android debug certificate; `minSdkVersion 24`, `targetSdkVersion 36`; the dex
contains `just_audio` and `androidx/media3/exoplayer`.

Other teammates were editing the same working tree while this was built, so the
counts above are for the baseline + voice changes only. At the time of writing,
the live working tree ran 263 tests with all passing, while `flutter analyze`
reported two issues in their in-progress files (`lib/services/api_client.dart`,
`test/support/fakes.dart`) — neither is touched by this work.

## Not verified

There is no Android device or emulator on this machine, so the APK has **not**
been installed, no sentence has been heard, and the microphone has not been
exercised on Android. In particular these remain unproven on hardware: that
ExoPlayer accepts the backend's mp3, that `stop()` really cuts the audio, that
the device voice activates as the fallback, and that the phone can reach the
LAN backend through its firewall.
