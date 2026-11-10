import 'dart:io' show Platform;

/// Which of the two products this build is running as.
///
/// Architecture decision 2026-11-10: *one codebase, two shapes*.
///
/// * **Windows = the older adult's appliance.** Voice chat, Play, the family
///   call and Stop. No settings UI at all: no Settings entry, no AI provider
///   screen, no provider key fields.
/// * **Android = the family/setup phone.** Configure AI providers (LLM + ASR),
///   family contacts, invitations, digests and device preferences. No voice
///   interaction at all: no microphone button, no spoken replies, no voice
///   answer button; nothing on the phone may open the mic or play speech.
///
/// The policy is a plain const object so a screen can be exercised as either
/// shape: [PlatformPolicy.fromPlatform] is what the app really runs, and widget
/// tests pass an explicit instance down through `AppState` instead of depending
/// on the host's `Platform.isWindows`. No screen and no state may branch on
/// `Platform` directly — that keeps the two shapes in one auditable place. (The
/// voice/bootstrapper services keep their own platform switch, because they are
/// about which implementation exists on a host, not about which product this is.)
class PlatformPolicy {
  const PlatformPolicy({required this.seniorAppliance});

  /// The older adult's Windows appliance: voice UI and no settings.
  const PlatformPolicy.seniorAppliance() : seniorAppliance = true;

  /// The family/setup phone: settings UI and no voice.
  const PlatformPolicy.setupApp() : seniorAppliance = false;

  /// What this build really is: Windows is the appliance, everything else the
  /// family/setup phone (Android is the only other shipped target).
  factory PlatformPolicy.fromPlatform() =>
      PlatformPolicy(seniorAppliance: Platform.isWindows);

  /// True on the older adult's appliance (Windows).
  final bool seniorAppliance;

  /// True on the family/setup phone (Android). The exact inverse of
  /// [seniorAppliance]: a build is always exactly one of the two shapes.
  bool get setupApp => !seniorAppliance;

  /// The policy the app uses unless a caller injects its own.
  ///
  /// Mutable only so tests can state a platform explicitly; production code
  /// never assigns it and always sees [fromPlatform].
  static PlatformPolicy instance = PlatformPolicy.fromPlatform();

  /// Restores [instance] to the real platform (test tear-down).
  static void resetInstance() {
    instance = PlatformPolicy.fromPlatform();
  }
}
