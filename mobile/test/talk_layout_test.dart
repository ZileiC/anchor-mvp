import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/senior/talk_screen.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The redesigned Talk screen (docs/design/senior-ui.md, 2026-11-10).
///
/// The conversation is a quiet stream of turns — a small speaker label and one
/// sentence, no card per turn — while the microphone lives in a fixed dock with
/// Stop directly beneath it. The senior never scrolls to talk: only the
/// conversation and the typing fallback at its end scroll.
void main() {
  late FakeApi api;
  late AppState state;

  const configuredProviders = ProviderStatus(
    llm: ProviderSectionStatus(
      configured: true,
      mode: 'http',
      engine: 'http',
      model: 'deepseek-chat',
    ),
    asr: ProviderSectionStatus(
      configured: true,
      mode: 'offline',
      engine: 'windows-sapi',
      model: 'whisper-1',
    ),
  );

  setUp(() {
    api = FakeApi()..feed = threeActivityFeed();
    state = buildTestState(api);
  });

  Future<void> openTalk(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    await pumpSignedIn(tester, state, size: size, textScale: textScale);
    await tester.ensureVisible(find.byKey(const Key('primary-talk')));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byType(TalkScreen), findsOneWidget);
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('talk-text-field')), text);
    await tester.ensureVisible(find.byKey(const Key('talk-send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('talk-send')));
    await settle(tester);
  }

  Text statusText(WidgetTester tester) => tester.widget<Text>(
    find.descendant(
      of: find.byKey(const Key('mic-indicator')),
      matching: find.byType(Text),
    ),
  );

  testWidgets('a turn is a label line and a sentence, never a card', (
    tester,
  ) async {
    await openTalk(tester);
    await say(tester, '今天天气好');

    final first = find.byKey(const ValueKey<String>('caption-0'));
    final second = find.byKey(const ValueKey<String>('caption-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);

    final firstTexts = find.descendant(of: first, matching: find.byType(Text));
    final secondTexts = find.descendant(
      of: second,
      matching: find.byType(Text),
    );
    expect(firstTexts, findsNWidgets(2));
    expect(secondTexts, findsNWidgets(2));

    final you = tester.widget<Text>(firstTexts.at(0));
    final said = tester.widget<Text>(firstTexts.at(1));
    final anchor = tester.widget<Text>(secondTexts.at(0));
    final reply = tester.widget<Text>(secondTexts.at(1));

    // Label: 22 px, inkSoft. Sentence: 26 px, ink, line height 1.35.
    expect(you.data, L.zh.you);
    expect(you.style?.fontSize, 22);
    expect(you.style?.color, AnchorTheme.inkSoft);
    expect(said.data, '今天天气好');
    expect(said.style?.fontSize, 26);
    expect(said.style?.height, 1.35);
    expect(said.style?.color, AnchorTheme.ink);
    expect(anchor.data, L.zh.anchor);
    expect(anchor.style?.fontSize, 22);
    expect(reply.data, '好的，我在听。');
    expect(reply.style?.fontSize, 26);
    expect(reply.style?.height, 1.35);

    // No bubble, avatar, card or surface around a turn: plain text on paper.
    for (final turn in <Finder>[first, second]) {
      expect(
        find.descendant(of: turn, matching: find.byType(Container)),
        findsNothing,
      );
      expect(
        find.descendant(of: turn, matching: find.byType(Material)),
        findsNothing,
      );
      expect(
        find.descendant(of: turn, matching: find.byType(CircleAvatar)),
        findsNothing,
      );
    }

    // Exactly 16 px between one turn and the next.
    final gap =
        tester.getRect(secondTexts.at(0)).top -
        tester.getRect(firstTexts.at(1)).bottom;
    expect(gap, closeTo(16, 0.5));

    await disposeApp(tester);
  });

  testWidgets('the mic and Stop sit in a dock the stream cannot scroll away', (
    tester,
  ) async {
    await openTalk(tester);
    for (var index = 0; index < 5; index++) {
      await say(tester, '第 ${index + 1} 句');
    }
    expect(tester.takeException(), isNull);

    // The dock is outside the scrolling area; the typing fallback is inside it.
    expect(
      find.ancestor(
        of: find.byKey(const Key('talk-mic')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('stop-control')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('talk-text-field')),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );

    final mic = tester.getRect(find.byKey(const Key('talk-mic')));
    final stop = tester.getRect(find.byKey(const Key('stop-control')));

    // Scrolling the whole conversation to the top moves neither of them.
    await tester.drag(
      find.byKey(const Key('talk-stream')),
      const Offset(0, 600),
    );
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('talk-mic'))), mic);
    expect(tester.getRect(find.byKey(const Key('stop-control'))), stop);

    // Stop is the last thing on the screen, directly under the mic.
    expect(mic.bottom, lessThanOrEqualTo(stop.top));
    expect(stop.bottom, lessThanOrEqualTo(844));

    // Full width (16 px each side) and comfortably tall.
    expect(mic.height, greaterThanOrEqualTo(72));
    expect(mic.width, closeTo(390 - 32, 0.5));

    await disposeApp(tester);
  });

  testWidgets(
    'on a wide window the stream is a centred reading column, the dock spans '
    'the panel',
    (tester) async {
      await openTalk(tester, size: const Size(1280, 720));
      await say(tester, '今天天气好');

      final caption = tester.getRect(
        find.byKey(const ValueKey<String>('caption-0')),
      );
      expect(caption.width, lessThanOrEqualTo(860));
      // Centred: equal paper margins on both sides of the reading column.
      expect(caption.left, closeTo(1280 - caption.right, 1));

      final mic = tester.getRect(find.byKey(const Key('talk-mic')));
      expect(mic.width, greaterThan(caption.width));

      await disposeApp(tester);
    },
  );

  testWidgets('the stream and dock survive 1.3x text on a phone', (
    tester,
  ) async {
    await openTalk(tester, textScale: 1.3);
    await say(tester, '今天天气好');
    await say(tester, '再聊一句');
    expect(tester.takeException(), isNull);

    final mic = tester.getRect(find.byKey(const Key('talk-mic')));
    final stop = tester.getRect(find.byKey(const Key('stop-control')));
    expect(mic.top, greaterThanOrEqualTo(0));
    expect(mic.bottom, lessThanOrEqualTo(stop.top));
    expect(stop.bottom, lessThanOrEqualTo(844));
    expect(find.byKey(const Key('talk-text-field')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the offline banner does not overflow at 1.3x text', (
    tester,
  ) async {
    await pumpSignedIn(
      tester,
      state,
      size: const Size(390, 844),
      textScale: 1.3,
    );
    api.offline = true;
    await state.refresh();
    await tester.pump();
    expect(state.offline, isTrue);

    await tester.ensureVisible(find.byKey(const Key('primary-talk')));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('talk-type-instead')), findsOneWidget);
    expect(find.byKey(const Key('talk-mic')), findsOneWidget);
    expect(find.byKey(const Key('stop-control')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('without a recogniser the button and status say so', (
    tester,
  ) async {
    await openTalk(tester);

    final status = statusText(tester);
    expect(status.data, L.zh.micNotConnected);
    expect(status.style?.fontSize, 22);
    expect(
      find.descendant(
        of: find.byKey(const Key('talk-mic')),
        matching: find.text(L.zh.micNotConnected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('talk-mic')),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await disposeApp(tester);
  });

  testWidgets('the mic states are written out, and listening breathes a ring', (
    tester,
  ) async {
    api.providerStatusValue = configuredProviders;
    state = buildTestState(api, microphone: FakeMicrophoneInput());
    await openTalk(tester);

    final mic = find.byKey(const Key('talk-mic'));
    final button = tester.widget<FilledButton>(mic);
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AnchorTheme.jade,
    );
    expect(find.byKey(const Key('talk-mic-ring')), findsNothing);
    expect(statusText(tester).data, L.zh.micOn);
    expect(
      find.descendant(of: mic, matching: find.text(L.zh.startTalking)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mic, matching: find.byIcon(Icons.mic)),
      findsOneWidget,
    );

    // Listening: the button offers to finish, the status line says 我在听, and a
    // breathing ring appears (motion is on, so a ticker is running).
    await tester.tap(mic);
    await settle(tester);
    expect(state.recording, isTrue);
    expect(find.byKey(const Key('talk-mic-ring')), findsOneWidget);
    expect(
      find.descendant(of: mic, matching: find.text(L.zh.doneSpeaking)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mic, matching: find.byIcon(Icons.stop)),
      findsOneWidget,
    );
    expect(statusText(tester).data, L.zh.listening);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    // The ring is painted *around* the button, so the button does not resize.
    final buttonRect = tester.getRect(mic);
    final ringRect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('talk-mic-ring')),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(ringRect.left, closeTo(buttonRect.left - 7, 0.5));
    expect(ringRect.right, closeTo(buttonRect.right + 7, 0.5));
    expect(ringRect.top, closeTo(buttonRect.top - 7, 0.5));
    expect(ringRect.bottom, closeTo(buttonRect.bottom + 7, 0.5));

    // Done: back to a still, plain button.
    await tester.tap(mic);
    await settle(tester);
    expect(state.recording, isFalse);
    expect(find.byKey(const Key('talk-mic-ring')), findsNothing);
    expect(
      find.descendant(of: mic, matching: find.text(L.zh.startTalking)),
      findsOneWidget,
    );

    await disposeApp(tester);
  });

  testWidgets('with motion off the listening ring is static', (tester) async {
    api.providerStatusValue = configuredProviders;
    state = buildTestState(api, microphone: FakeMicrophoneInput());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await openTalk(tester);
    await tester.tap(find.byKey(const Key('talk-mic')));
    await settle(tester);

    expect(state.recording, isTrue);
    expect(find.byKey(const Key('talk-mic-ring')), findsOneWidget);
    // Nothing is ticking: the ring is drawn, but it does not breathe.
    expect(tester.binding.transientCallbackCount, 0);

    await disposeApp(tester);
  });

  testWidgets('listening at 1.3x keeps the mic and Stop on screen', (
    tester,
  ) async {
    api.providerStatusValue = configuredProviders;
    state = buildTestState(api, microphone: FakeMicrophoneInput());
    await openTalk(tester, textScale: 1.3);

    await tester.tap(find.byKey(const Key('talk-mic')));
    await settle(tester);
    expect(state.recording, isTrue);
    expect(tester.takeException(), isNull);

    final mic = tester.getRect(find.byKey(const Key('talk-mic')));
    final stop = tester.getRect(find.byKey(const Key('stop-control')));
    expect(mic.top, greaterThanOrEqualTo(0));
    expect(mic.bottom, lessThanOrEqualTo(stop.top));
    expect(stop.bottom, lessThanOrEqualTo(844));

    await disposeApp(tester);
  });

  testWidgets('a caption fades in once, and stays still when motion is off', (
    tester,
  ) async {
    await openTalk(tester);
    await say(tester, '你好');

    final reply = find.byKey(const ValueKey<String>('caption-1'));
    final fade = find.descendant(of: reply, matching: find.byType(Opacity));
    expect(fade, findsOneWidget);
    expect(tester.widget<Opacity>(fade).opacity, 1);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await settle(tester);
    await say(tester, '再说一句');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('caption-3')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    await disposeApp(tester);
  });
}
