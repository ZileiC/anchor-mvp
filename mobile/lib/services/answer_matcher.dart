/// Decides which of a card's options a recognised sentence means.
///
/// The Play screen treats a spoken answer exactly like a tap, so the hard part is
/// not recognising speech (the backend does that) but choosing between three
/// short options when the senior says a whole sentence, reorders the words, or
/// uses a numeral word. This library is pure Dart — no Flutter, no clock, no
/// randomness — so every rule below is testable on its own.
///
/// The matcher is deliberately allowed to answer **nothing**. A wrong grade is
/// worse than an honest "没听清": the senior can retry the voice, or simply tap.
library;

/// The smallest character-overlap score that may be accepted.
///
/// A paraphrased answer such as "盖上锅盖" against the option "把锅盖盖上" scores
/// three shared characters out of four (0.75), so 0.6 accepts that while still
/// rejecting a half-understood phrase.
const double _overlapThreshold = 0.6;

/// A fragment of an option must be at least this long before it is trusted.
///
/// One shared character is too easy to say by accident ("冬" is in both 冬至 and
/// 冬天), so a one-character sentence never wins by containment.
const int _minimumFragmentLength = 2;

/// Returns the index in [options] that [transcript] means, or `null`.
///
/// The rules are applied in this order, and the first one that decides wins:
///
/// 1. **Containment.** If a normalised option occurs inside the normalised
///    transcript, that option is the answer; when several occur, the longest one
///    wins. A tie between two equally long options is ambiguous and returns null.
/// 2. **Fragment.** If the whole normalised transcript (at least two characters)
///    occurs inside exactly one option, that option is the answer. Several
///    options containing it is ambiguous and returns null.
/// 3. **Character overlap.** For every remaining option, the score is the number
///    of *distinct* characters the option shares with the transcript, divided by
///    the number of distinct characters in the option. The single best option is
///    accepted only when its score is at least 0.6 **and** strictly higher than
///    the runner-up; a tie returns null.
///
/// A **numeric** option (digits only, e.g. `"12"`) takes part through its number
/// instead: the transcript is scanned for number tokens (ASCII digit runs and the
/// Chinese numerals 一…九十九, with 两 read as 二), and the option matches only
/// when one whole token equals it. Numeric options never take part in steps 2 and
/// 3, so `"1"` can never be matched from inside `"12"`.
///
/// Normalisation (used everywhere above): trim, convert full-width digits to
/// half-width, drop whitespace and punctuation, and fold Latin case.
int? matchOption(String transcript, List<String> options) {
  if (options.isEmpty) return null;
  final spoken = _normalise(transcript);
  if (spoken.isEmpty) return null;

  final normalised = <String>[for (final option in options) _normalise(option)];
  final numbers = _numberTokens(spoken);
  final spokenCharacters = spoken.runes.toSet();

  // 1) an option that was said inside the sentence.
  var contained = -1;
  var containedLength = 0;
  var containedTie = false;
  for (var index = 0; index < normalised.length; index++) {
    final option = normalised[index];
    if (option.isEmpty) continue;
    final matched = _isNumeric(option)
        ? numbers.contains(option)
        : spoken.contains(option);
    if (!matched) continue;
    final length = option.runes.length;
    if (length > containedLength) {
      contained = index;
      containedLength = length;
      containedTie = false;
    } else if (length == containedLength) {
      containedTie = true;
    }
  }
  if (contained >= 0) return containedTie ? null : contained;

  // 2) the sentence was only part of an option ("锅盖" for "把锅盖盖上").
  if (spoken.runes.length >= _minimumFragmentLength) {
    var fragment = -1;
    var fragmentCount = 0;
    for (var index = 0; index < normalised.length; index++) {
      final option = normalised[index];
      if (option.isEmpty || _isNumeric(option)) continue;
      if (option.contains(spoken)) {
        fragment = index;
        fragmentCount++;
      }
    }
    if (fragmentCount == 1) return fragment;
    if (fragmentCount > 1) return null;
  }

  // 3) character overlap, one clear winner only.
  final scores = List<double>.filled(normalised.length, 0);
  for (var index = 0; index < normalised.length; index++) {
    final option = normalised[index];
    if (option.isEmpty || _isNumeric(option)) continue;
    final optionCharacters = option.runes.toSet();
    if (optionCharacters.isEmpty) continue;
    final shared = optionCharacters.where(spokenCharacters.contains).length;
    scores[index] = shared / optionCharacters.length;
  }
  var best = -1;
  var bestScore = 0.0;
  for (var index = 0; index < scores.length; index++) {
    if (scores[index] > bestScore) {
      best = index;
      bestScore = scores[index];
    }
  }
  if (best < 0 || bestScore < _overlapThreshold) return null;
  var bestCount = 0;
  var runnerUp = 0.0;
  for (var index = 0; index < scores.length; index++) {
    if (scores[index] == bestScore) {
      bestCount++;
    } else if (scores[index] > runnerUp) {
      runnerUp = scores[index];
    }
  }
  if (bestCount != 1 || bestScore <= runnerUp) return null;
  return best;
}

/// Space, punctuation and symbols carry no meaning for matching.
///
/// Unicode property escapes keep this honest for Chinese punctuation (`，。？`)
/// and the ideographic space, not only for ASCII.
final RegExp _ignorable = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

/// Trim, width-fold, drop noise, fold case. The one form every comparison uses.
String _normalise(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    // FULLWIDTH DIGIT ZERO … NINE → ASCII 0…9, so "１２" and "12" are the same.
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
      continue;
    }
    if (_ignorable.hasMatch(String.fromCharCode(rune))) continue;
    buffer.write(String.fromCharCode(rune).toLowerCase());
  }
  return buffer.toString();
}

bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

/// True when the normalised option is nothing but digits.
bool _isNumeric(String normalised) {
  if (normalised.isEmpty) return false;
  for (final rune in normalised.runes) {
    if (!_isAsciiDigit(rune)) return false;
  }
  return true;
}

// -- Chinese numerals ------------------------------------------------------
//
// The recogniser may return "十二" where the card shows "12". Only the numerals a
// senior would say for a small count are handled: 一…九, 十, and 两 for 二 (people
// say "两个"), up to 99. Anything else is left alone and simply will not match.

const int _ten = 0x5341; // 十

const Map<int, int> _chineseDigitValues = <int, int>{
  0x4E00: 1, // 一
  0x4E8C: 2, // 二
  0x4E09: 3, // 三
  0x56DB: 4, // 四
  0x4E94: 5, // 五
  0x516D: 6, // 六
  0x4E03: 7, // 七
  0x516B: 8, // 八
  0x4E5D: 9, // 九
  0x4E24: 2, // 两
};

int? _chineseDigitValue(int rune) => _chineseDigitValues[rune];

/// Hundreds and above (百/千/万/亿) are outside this matcher's range.
const Set<int> _numeralScale = <int>{0x767E, 0x5343, 0x4E07, 0x4EBF};

/// Every number the transcript says, in order, as ASCII digits.
///
/// A run of Chinese numeral characters is read as one number ("二十三" → "23");
/// an unreadable run contributes nothing rather than a guess. A run that turns
/// out to be the head of a bigger number ("一百", "两千") is dropped whole, so it
/// can never leave a stray "1" or "2" behind.
List<String> _numberTokens(String text) {
  final numbers = <String>[];
  final runes = text.runes.toList(growable: false);
  var index = 0;
  while (index < runes.length) {
    final rune = runes[index];
    if (_isAsciiDigit(rune)) {
      final start = index;
      while (index < runes.length && _isAsciiDigit(runes[index])) {
        index++;
      }
      numbers.add(String.fromCharCodes(runes.sublist(start, index)));
      continue;
    }
    if (_chineseDigitValue(rune) != null || rune == _ten) {
      final start = index;
      while (index < runes.length &&
          (_chineseDigitValue(runes[index]) != null || runes[index] == _ten)) {
        index++;
      }
      if (index < runes.length && _numeralScale.contains(runes[index])) {
        continue;
      }
      final value = _parseChineseNumeral(runes.sublist(start, index));
      if (value != null) numbers.add('$value');
      continue;
    }
    index++;
  }
  return numbers;
}

/// Reads one run of Chinese numeral characters as a number from 1 to 99.
int? _parseChineseNumeral(List<int> runes) {
  if (runes.isEmpty) return null;
  final tenIndex = runes.indexOf(_ten);
  if (tenIndex < 0) {
    if (runes.length != 1) return null;
    return _chineseDigitValue(runes.first);
  }
  // At most one digit on each side of 十 keeps this a simple tens+units reading.
  if (runes.length > 3) return null;
  final before = runes.sublist(0, tenIndex);
  final after = runes.sublist(tenIndex + 1);
  if (before.length > 1 || after.length > 1) return null;
  final tens = before.isEmpty ? 1 : _chineseDigitValue(before.first);
  final units = after.isEmpty ? 0 : _chineseDigitValue(after.first);
  if (tens == null || units == null) return null;
  return tens * 10 + units;
}
