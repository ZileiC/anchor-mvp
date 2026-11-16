import 'dart:async';

import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/senior/choices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The older adult picks between the two voices, 2026-11-16.
///
/// The provider exposes one female voice and one male voice. The stored value is
/// the gender, not the provider id, so a provider or fallback change keeps the
/// choice meaningful; these tests pin the model and the two buttons.
void main() {
  test('the model reads the stored gender', () {
    expect(
      Preferences.fromJson(<String, Object?>{'voice_gender': 'male'})
          .isMaleVoice,
      isTrue,
    );
    expect(
      Preferences.fromJson(<String, Object?>{'voice_gender': 'female'})
          .isMaleVoice,
      isFalse,
    );
  });

  test('a missing gender means the default (female) voice', () {
    expect(Preferences.defaults.voiceGender, isNull);
    expect(Preferences.defaults.isMaleVoice, isFalse);
    expect(
      Preferences.fromJson(<String, Object?>{'voice_gender': null}).isMaleVoice,
      isFalse,
    );
  });

  test('copyWith can set it and clear it', () {
    final male = Preferences.defaults.copyWith(voiceGender: 'male');
    expect(male.isMaleVoice, isTrue);
    expect(male.copyWith(clearVoiceGender: true).voiceGender, isNull);
  });

  testWidgets('the two buttons write the choice and show which is active', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);

    final navigator = Navigator.of(tester.element(find.byType(Scaffold).first));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => ChoicesScreen(state: state)),
    );
    await settle(tester);

    // Female is the default, so it starts filled and male starts outlined.
    expect(find.byKey(const Key('voice-female')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('voice-female'))),
      isA<FilledButton>(),
    );
    expect(
      tester.widget(find.byKey(const Key('voice-male'))),
      isA<OutlinedButton>(),
    );

    final male = find.byKey(const Key('voice-male'));
    await tester.ensureVisible(male);
    await tester.tap(male);
    await settle(tester);

    expect(api.prefs.voiceGender, 'male');
    expect(state.prefersMaleVoice, isTrue);
    expect(
      tester.widget(find.byKey(const Key('voice-male'))),
      isA<FilledButton>(),
    );
    expect(
      tester.widget(find.byKey(const Key('voice-female'))),
      isA<OutlinedButton>(),
    );

    // And back to the female voice.
    final female = find.byKey(const Key('voice-female'));
    await tester.ensureVisible(female);
    await tester.tap(female);
    await settle(tester);
    expect(api.prefs.voiceGender, 'female');
    expect(state.prefersMaleVoice, isFalse);

    await disposeApp(tester);
  });

  testWidgets('the buttons are labelled for a person, not a device', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);

    // Not awaited: a pushed route stays mounted, so its future never completes
    // and awaiting it hangs the test until the 10-minute guard fires.
    unawaited(
      Navigator.of(tester.element(find.byType(Scaffold).first)).push(
        MaterialPageRoute<void>(builder: (_) => ChoicesScreen(state: state)),
      ),
    );
    await settle(tester);

    expect(find.text(L.zh.t('女声', 'Female voice')), findsOneWidget);
    expect(find.text(L.zh.t('男声', 'Male voice')), findsOneWidget);
    expect(find.text(L.zh.t('用哪个声音说话', 'Which voice speaks')), findsOneWidget);

    await disposeApp(tester);
  });
}
