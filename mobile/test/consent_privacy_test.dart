import 'package:anchor_app/models/consent.dart';
import 'package:flutter_test/flutter_test.dart';

/// Private by default (SPEC §5 rule 1, S8): a missing row is "not allowed".
void main() {
  test('the default snapshot shares nothing', () {
    const snapshot = ConsentSnapshot.privateDefault;
    expect(snapshot.cloudProcessing, isFalse);
    expect(snapshot.proactiveInvitations, isFalse);
    expect(snapshot.saveMemory, isFalse);
    expect(snapshot.recordObservations, isFalse);
    expect(snapshot.anySharing, isFalse);
    for (final topic in ShareTopics.all) {
      expect(snapshot.shareTopicAllowed(topic), isFalse, reason: topic);
    }
  });

  test('an empty server snapshot is still private', () {
    final snapshot = ConsentSnapshot.fromJson(<String, Object?>{
      'version': 3,
      'items': <Object?>[],
    });
    expect(snapshot.version, 3);
    expect(snapshot.anySharing, isFalse);
    expect(snapshot.cloudProcessing, isFalse);
  });

  test('only explicitly allowed rows are allowed', () {
    final snapshot = ConsentSnapshot.fromJson(<String, Object?>{
      'version': 2,
      'items': <Object?>[
        <String, Object?>{
          'capability': 'share_topic',
          'topic': 'meals',
          'allowed': true,
          'version': 2,
        },
        <String, Object?>{
          'capability': 'share_topic',
          'topic': 'mood',
          'allowed': false,
          'version': 2,
        },
        <String, Object?>{
          'capability': 'cloud_processing',
          'topic': '',
          'allowed': true,
          'version': 2,
        },
      ],
    });
    expect(snapshot.shareTopicAllowed('meals'), isTrue);
    expect(snapshot.shareTopicAllowed('mood'), isFalse);
    expect(snapshot.shareTopicAllowed('wellbeing'), isFalse);
    expect(snapshot.allowedShareTopics, <String>['meals']);
    expect(snapshot.cloudProcessing, isTrue);
    expect(snapshot.saveMemory, isFalse);
  });

  test(
    'a topic row without its capability row does not imply the capability',
    () {
      final snapshot = ConsentSnapshot.fromJson(<String, Object?>{
        'version': 1,
        'items': <Object?>[
          <String, Object?>{
            'capability': 'share_topic',
            'topic': 'mood',
            'allowed': true,
          },
        ],
      });
      expect(snapshot.shareTopicAllowed('mood'), isTrue);
      expect(snapshot.recordObservations, isFalse);
    },
  );

  test('copyWith keeps unspecified fields', () {
    const snapshot = ConsentSnapshot.privateDefault;
    final updated = snapshot.copyWith(version: 9);
    expect(updated.version, 9);
    expect(updated.items, isEmpty);
  });
}
