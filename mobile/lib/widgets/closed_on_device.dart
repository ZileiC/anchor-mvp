import 'package:flutter/material.dart';

import '../theme.dart';

/// What a screen shows when the running platform does not have it at all.
///
/// Architecture change 2026-11-10: the Windows appliance has no settings UI, so
/// `SettingsScreen` and `AiProvidersScreen` must not be reachable there. Hiding
/// the entry point is not enough — a restored route, a deep link or a hand-built
/// `MaterialPageRoute` could still push one — so those two screens return this
/// instead, which explains itself and then bounces straight back to Home.
class ClosedOnDevice extends StatefulWidget {
  const ClosedOnDevice({super.key, required this.message});

  final String message;

  @override
  State<ClosedOnDevice> createState() => _ClosedOnDeviceState();
}

class _ClosedOnDeviceState extends State<ClosedOnDevice> {
  @override
  void initState() {
    super.initState();
    // Back to the first route (Home) on the next frame, so a pushed route never
    // leaves the senior stranded on a screen this build does not have.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.message,
              key: const Key('closed-on-device'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                color: AnchorTheme.ink,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
