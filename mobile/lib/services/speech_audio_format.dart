/// Which container the backend just sent us, 2026-11-14.
///
/// The voice used to be Microsoft edge-tts, which always answered `audio/mpeg`.
/// Since 2026-11-14 the backend may answer with DeepSeek's voice instead, which
/// is WAV (or raw PCM) — and both platform players here open the bytes as a
/// **file**, so the extension has to match the container or the player refuses
/// the file and the senior hears nothing.
///
/// Sniffing the first bytes is used rather than the response `Content-Type`:
/// it costs 12 bytes of comparison, it cannot be wrong about the bytes we
/// actually hold, and it keeps this decision out of the HTTP client (which
/// currently hands callers raw bytes only).
library;

import 'dart:typed_data';

/// `'wav'` for a RIFF/WAVE body, `'mp3'` for everything else.
///
/// Defaulting to mp3 is deliberate: that is what every previous build produced,
/// and a wrong-but-plausible extension is better than a player that cannot open
/// the file at all... except for the one case handled here, which is the whole
/// point of this file.
String speechFileExtension(Uint8List audio) {
  if (audio.length >= 12 &&
      audio[0] == 0x52 && // R
      audio[1] == 0x49 && // I
      audio[2] == 0x46 && // F
      audio[3] == 0x46 && // F
      audio[8] == 0x57 && // W
      audio[9] == 0x41 && // A
      audio[10] == 0x56 && // V
      audio[11] == 0x45) {
    // E
    return 'wav';
  }
  return 'mp3';
}

/// True when a temp file name looks like one of ours (any container).
///
/// Used by the startup sweep, which has to clean up after a crash: it used to
/// look for `.mp3` only, which would have left WAV files behind forever.
bool isSpeechTempName(String name, String prefix) {
  if (!name.startsWith(prefix)) return false;
  return name.endsWith('.mp3') || name.endsWith('.wav');
}
