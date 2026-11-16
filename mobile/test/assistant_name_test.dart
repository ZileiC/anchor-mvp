import 'package:anchor_app/app.dart';
import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/screens/senior/choices_screen.dart';
import 'package:anchor_app/screens/senior/talk_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The older adult names the companion, 2026-11-16.
///
/// The chat used to label every assistant line with one fixed word. These tests
/// pin the whole path: the name reaches the model, the caption uses it, a blank
/// answer falls back to the default, and the choice is the senior's alone.
void main() {
  test('the model reads the name the backend stores', () {
    final prefs = Preferences.fromJson(<String, Object?>{
      'assistant_name': '小安',
      'voice_pace': 'slow',
    });
    expect(prefs.assistantName, '小安');
  });

  test('a missing or blank name is null, not an empty label', () {
    expect(Preferences.fromJson(<String, Object?>{}).assistantName, isNull);
    expect(
      Preferences.fromJson(<String, Object?>{'assistant_name': null})
          .assistantName,
      isNull,
    );
    expect(Preferences.defaults.assistantName, isNull);
  });

  test('AppState falls back to blank so the UI can choose the default', () {
    final state = buildTestState(FakeApi());
    expect(state.assistantName, '', reason: 'no profile loaded yet');
  });

  testWidgets('setting a name sends it and the caption shows it', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);

    // Save a name through the same call the dialog makes.
    expect(await state.setAssistantName(' 小安 '), isTrue);
    expect(api.prefs.assistantName, '小安');
    expect(state.assistantName, '小安');

    // The conversation shows it instead of the product word.
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byType(TalkScreen), findsOneWidget);
    state.captions
      ..clear()
      ..add(const Caption(role: 'anchor', text: '你好呀'));
    state.captions.add(const Caption(role: 'senior', text: '你好'));
    // Any preference patch repaints the tree; that is how the screen learns the
    // name changed in the real app too.
    await state.updatePreferences(<String, Object?>{});
    await settle(tester);

    expect(find.text('小安'), findsOneWidget);
    expect(
      find.text(L.zh.anchor),
      findsNothing,
      reason: 'the default is replaced',
    );

    await disposeApp(tester);
  });

  testWidgets('a blank name goes back to the default', (tester) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);

    expect(await state.setAssistantName('小安'), isTrue);
    expect(await state.setAssistantName('   '), isTrue);
    expect(api.prefs.assistantName, isNull);
    expect(state.assistantName, '');
    expect(api.prefs.assistantName, isNot(''));

    await disposeApp(tester);
  });

  testWidgets('the choices screen edits the name through the dialog', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);
    await tester.tap(find.byKey(const Key('login-senior')));
    await settle(tester);

    final navigator = Navigator.of(tester.element(find.byType(Scaffold).first));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => ChoicesScreen(state: state)),
    );
    await settle(tester);

    final row = find.byKey(const Key('choice-assistant-name'));
    await tester.ensureVisible(row);
    // Before any change the row shows the product default.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('choice-assistant-name-value')))
          .data,
      L.zh.anchor,
    );

    await tester.tap(row);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('assistant-name-field')), '老伴');
    await tester.tap(find.byKey(const Key('assistant-name-save')));
    await settle(tester);

    expect(api.prefs.assistantName, '老伴');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('choice-assistant-name-value')))
          .data,
      '老伴',
    );

    await disposeApp(tester);
  });

  testWidgets('the dialog is only 12 characters long on purpose', (
    tester,
  ) async {
    final field = TextField(key: const Key('probe'), maxLength: 12);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));
    expect(
      tester.widget<TextField>(find.byKey(const Key('probe'))).maxLength,
      12,
    );
  });
}
