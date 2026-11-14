import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/api_client.dart';
import 'services/backend_address_store.dart';
import 'services/app_log.dart';
import 'services/backend_bootstrapper.dart';
import 'services/backend_tts_speaker.dart';
import 'services/dialer.dart';
import 'services/lan_address.dart';
import 'services/speaker_factory.dart';
import 'services/speech_input.dart';
import 'state/app_state.dart';
import 'state/backend_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First thing: a windowed double-click launch has no console, so every
  // debugPrint (microphone failures included) also goes to
  // %LOCALAPPDATA%\Anchor\anchor_app.log.
  AppLog.install();
  // The phone's backend address is chosen on the phone, not compiled in: the
  // computer's LAN address changes with the Wi-Fi. Read it before the client is
  // built so the first probe already talks to the right machine.
  final savedAddress = await const BackendAddressStore().load();
  // The Windows Home screen prints 'address for the phone: http://<lan>:8077',
  // so look the LAN address up once here instead of on every rebuild.
  unawaited(probeLanAddress());
  // Drop speech mp3s a previous run never cleaned up (crash / killed child).
  unawaited(sweepStaleTtsFiles());
  // No saved address on a phone means "find the computer", not "127.0.0.1": the
  // login screen runs the search on its first frame (2026-11-14).
  final api = ApiClient(baseUrl: savedAddress);
  final state = AppState(
    api: api,
    // Windows speech asks this same client for the backend's neural mp3, so it
    // reuses the base URL and the bearer token that sign-in stores on it.
    speaker: createSpeaker(api: api),
    microphone: RecordMicrophoneInput(),
    dialer: const SystemDialer(),
  );
  // Windows demo package: start the bundled backend ourselves so the user only
  // has to double-click anchor_app.exe. On other platforms (and when the API is
  // remote) this resolves immediately and nothing is spawned. The gate shows the
  // splash while the probe/launch runs and a retry card if it fails.
  final startup = BackendStartup(bootstrapper: createBackendBootstrapper())
    ..attachLifecycle();
  runApp(AnchorApp(state: state, startup: startup));
}
