import 'package:flutter/material.dart';

import 'app.dart';
import 'services/api_client.dart';
import 'services/dialer.dart';
import 'services/speaker_factory.dart';
import 'services/speech_input.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(
    api: ApiClient(),
    speaker: createSpeaker(),
    microphone: RecordMicrophoneInput(),
    dialer: const SystemDialer(),
  );
  runApp(AnchorApp(state: state));
}
