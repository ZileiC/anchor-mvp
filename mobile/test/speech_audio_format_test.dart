import 'dart:io';
import 'dart:typed_data';

import 'package:anchor_app/services/speech_audio_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// The voice changed providers on 2026-11-14 (Microsoft edge-tts → DeepSeek),
/// and the container changed with it: mp3 became WAV. Both platform players open
/// the audio as a *file*, so a wrong extension means silence — the worst possible
/// failure for the person using this app.
void main() {
  Uint8List ascii(String text) => Uint8List.fromList(text.codeUnits);

  group('container sniffing', () {
    test('a RIFF/WAVE body is named .wav', () {
      final wav = Uint8List.fromList(<int>[
        ...ascii('RIFF'),
        0x24,
        0x08,
        0x00,
        0x00,
        ...ascii('WAVE'),
        ...ascii('fmt '),
      ]);
      expect(speechFileExtension(wav), 'wav');
    });

    test(
      'anything else stays .mp3, which is what every earlier build produced',
      () {
        final mp3 = Uint8List.fromList(<int>[
          0x49,
          0x44,
          0x33, // "ID3" tag: the usual start of an mp3
          0x04,
          0x00,
          ...List<int>.filled(20, 0),
        ]);
        expect(speechFileExtension(mp3), 'mp3');
      },
    );

    test('a body too short to identify is not guessed as wav', () {
      expect(speechFileExtension(Uint8List.fromList(<int>[0x52, 0x49])), 'mp3');
      expect(speechFileExtension(Uint8List(0)), 'mp3');
    });

    test('RIFF with a different form type is not a wav', () {
      final riff = Uint8List.fromList(<int>[
        ...ascii('RIFF'),
        0,
        0,
        0,
        0,
        ...ascii('AVI '),
      ]);
      expect(speechFileExtension(riff), 'mp3');
    });
  });

  group('temp-file sweep', () {
    test('both containers left by a crash are recognised', () {
      const prefix = 'anchor-tts';
      expect(isSpeechTempName('$prefix-1-0.mp3', prefix), isTrue);
      expect(isSpeechTempName('$prefix-1-0.wav', prefix), isTrue);
    });

    test('unrelated files are left alone', () {
      const prefix = 'anchor-tts';
      expect(isSpeechTempName('holiday.wav', prefix), isFalse);
      expect(isSpeechTempName('$prefix-1-0.txt', prefix), isFalse);
      expect(isSpeechTempName('$prefix-1-0.mp3.part', prefix), isFalse);
    });
  });

  test('the sweep runs over real files without touching foreign ones', () async {
    final directory = await Directory.systemTemp.createTemp(
      'anchor-wav-sweep-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stale = File(
      '${directory.path}${Platform.pathSeparator}anchor-tts-9-0.wav',
    );
    await stale.writeAsBytes(<int>[0, 1, 2, 3]);
    final foreign = File(
      '${directory.path}${Platform.pathSeparator}keep-me.wav',
    );
    await foreign.writeAsBytes(<int>[0, 1, 2, 3]);
    // A timestamp far in the past so the age filter always applies.
    final old = DateTime.now().subtract(const Duration(days: 1));
    await stale.setLastModified(old);
    await foreign.setLastModified(old);

    // The speaker's own sweep is exercised indirectly by its test file; here the
    // rule itself is what matters: recognised names go, everything else stays.
    for (final entity in directory.listSync().whereType<File>()) {
      final name = entity.uri.pathSegments.last;
      if (isSpeechTempName(name, 'anchor-tts')) await entity.delete();
    }
    expect(stale.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
  });
}
