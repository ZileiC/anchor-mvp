import 'package:flutter/material.dart';

import 'app.dart';
import 'services/api_client.dart';
import 'services/backend_bootstrapper.dart';
import 'services/dialer.dart';
import 'services/speaker_factory.dart';
import 'services/speech_input.dart';
import 'state/app_state.dart';
import 'state/backend_startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
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
