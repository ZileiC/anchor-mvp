import 'package:anchor_app/services/answer_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// The matcher is the only thing that turns words into a grade, so these tests
/// pin the exact rules: containment first, then a fragment, then a character
/// overlap with one clear winner — and nothing at all whenever it would be a
/// guess. A wrong grade is far worse than an honest "没听清".
void main() {
  group('exact and contained answers', () {
    test('an exact option is found', () {
      expect(matchOption('把锅盖盖上', <String>['先泼一盆水', '把锅盖盖上', '端起来往水池挪']), 1);
    });

    test('punctuation and spaces around the words are ignored', () {
      expect(matchOption(' 把锅盖盖上。 ', <String>['先泼一盆水', '把锅盖盖上']), 1);
      expect(matchOption('把锅盖 盖上', <String>['先泼一盆水', '把锅盖盖上']), 1);
    });

    test('an option said inside a longer sentence wins', () {
      expect(matchOption('我最喜欢在树下乘凉', <String>['在门口等信', '在树下乘凉']), 1);
      expect(matchOption('应该是冬至吧', <String>['夏至', '冬至', '立秋']), 1);
    });

    test('the longest contained option wins', () {
      expect(matchOption('锅盖盖上', <String>['锅盖', '锅盖盖上']), 1);
      expect(matchOption('就选冬至', <String>['冬', '冬至']), 1);
    });

    test('full-width digits are read as normal digits', () {
      expect(matchOption('我选１２', <String>['10', '11', '12']), 2);
    });

    test('Latin case does not matter', () {
      expect(
        matchOption('put the lid on the pan', <String>[
          'Put the lid on the pan',
        ]),
        0,
      );
    });
  });

  group('spoken paraphrase', () {
    test('"盖上锅盖" selects "把锅盖盖上" by character overlap', () {
      expect(matchOption('盖上锅盖', <String>['先泼一盆水', '把锅盖盖上', '端起来往水池挪']), 1);
    });

    test('a partial phrase selects the option that contains it', () {
      expect(matchOption('锅盖', <String>['先泼一盆水', '把锅盖盖上']), 1);
    });
  });

  group('numbers', () {
    test('a Chinese numeral matches the digit option', () {
      expect(matchOption('十二', <String>['10', '11', '12']), 2);
      expect(matchOption('是十二个月', <String>['10', '11', '12']), 2);
      expect(matchOption('十', <String>['10', '11']), 0);
      expect(matchOption('二十三', <String>['20', '23']), 1);
    });

    test('a digit said as a digit matches too', () {
      expect(matchOption('12', <String>['10', '11', '12']), 2);
    });

    test('a shorter number is never found inside a longer one', () {
      expect(matchOption('12', <String>['1', '12']), 1);
      expect(matchOption('是十二', <String>['1', '2']), isNull);
    });

    test('a number that is not an option does not match', () {
      expect(matchOption('十三', <String>['10', '11', '12']), isNull);
    });

    test('a number beyond 99 leaves no stray digit behind', () {
      // 一百 / 两百 are read as numbers this matcher does not claim; dropping the
      // whole run is what keeps "一" from matching option "1".
      expect(matchOption('一百', <String>['1', '2']), isNull);
      expect(matchOption('两百', <String>['2', '3']), isNull);
    });

    test('两 is read as 二, because people say 两个', () {
      expect(matchOption('两个', <String>['2', '3']), 0);
    });
  });

  group('refusals', () {
    test('gibberish matches nothing', () {
      expect(
        matchOption('今天天气不错', <String>['先泼一盆水', '把锅盖盖上', '端起来往水池挪']),
        isNull,
      );
    });

    test('a half-heard option is below the threshold', () {
      // 夏至 shares only 夏 with 夏天: 1 of 2 characters = 0.5 < 0.6.
      expect(matchOption('夏天', <String>['夏至', '冬至']), isNull);
    });

    test('two equally good options are ambiguous', () {
      expect(matchOption('甲丙乙', <String>['甲乙丙丁', '甲丁丙乙']), isNull);
    });

    test('a fragment fitting two options is ambiguous', () {
      expect(matchOption('在树下', <String>['在树下乘凉', '在树下等信']), isNull);
    });

    test('one character is never enough', () {
      expect(matchOption('把', <String>['把锅盖盖上']), isNull);
    });

    test('empty and punctuation-only transcripts match nothing', () {
      expect(matchOption('', <String>['10', '11', '12']), isNull);
      expect(matchOption('   ', <String>['10', '11', '12']), isNull);
      expect(matchOption('，。？', <String>['10', '11', '12']), isNull);
    });

    test('an empty option list matches nothing', () {
      expect(matchOption('十二', const <String>[]), isNull);
    });
  });
}
