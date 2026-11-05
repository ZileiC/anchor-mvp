import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Outcome of handing a number to the system dialer.
class DialResult {
  const DialResult({required this.launched, required this.phone, this.error});

  final bool launched;
  final String phone;
  final String? error;
}

/// Calling seam. Dialing must work with no network at all (SPEC §9 offline
/// rule), so this never talks to the API.
abstract class Dialer {
  Future<DialResult> dial(String phone);
}

/// Opens `tel:` through the platform launcher.
class SystemDialer implements Dialer {
  const SystemDialer();

  static String normalise(String phone) {
    final kept = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return kept.isEmpty ? phone.trim() : kept;
  }

  @override
  Future<DialResult> dial(String phone) async {
    final cleaned = normalise(phone);
    if (cleaned.isEmpty) {
      return const DialResult(
        launched: false,
        phone: '',
        error: 'empty_number',
      );
    }
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return DialResult(
        launched: opened,
        phone: cleaned,
        error: opened ? null : 'launch_refused',
      );
    } catch (error) {
      debugPrint('Dialer failed: $error');
      return DialResult(launched: false, phone: cleaned, error: '$error');
    }
  }
}
