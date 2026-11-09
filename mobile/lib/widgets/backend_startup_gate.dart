import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../services/backend_bootstrapper.dart';
import '../state/backend_startup.dart';
import '../theme.dart';
import 'status_banner.dart';

/// Shows the "preparing the local service" splash, then either the app or a
/// retry card.
///
/// It wraps [RootScreen] instead of replacing it, so a dead backend degrades:
/// the login picker, Stop and Settings stay usable and only a banner is added
/// (SPEC §9 "degrade, never crash").
class BackendStartupGate extends StatefulWidget {
  const BackendStartupGate({
    super.key,
    required this.startup,
    required this.child,
  });

  final BackendStartup startup;
  final Widget child;

  @override
  State<BackendStartupGate> createState() => _BackendStartupGateState();
}

class _BackendStartupGateState extends State<BackendStartupGate> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the splash paints before the probe can block on
    // a socket: the UI thread is never held up by ensureReady().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.startup.start());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.startup,
      builder: (context, child) {
        final startup = widget.startup;
        if (!startup.applies) return child!;
        if (startup.waiting) return const BackendSplash();
        if (!startup.failed) return child!;
        final l = AnchorScope.of(context).l;
        return Column(
          children: <Widget>[
            _BannerSlot(
              child: BackendProblemCard(
                l: l,
                result: startup.result!,
                fallbackPath: startup.expectedExecutablePath,
                busy: startup.busy,
                onRetry: () => unawaited(startup.retry()),
              ),
            ),
            Expanded(child: child!),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Keeps the card from ever squeezing the screen below the fold: if the copy
/// gets tall at large text scales, only the card scrolls.
class _BannerSlot extends StatelessWidget {
  const _BannerSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: SingleChildScrollView(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The full-screen "正在准备本地服务…" state shown while the backend starts.
class BackendSplash extends StatelessWidget {
  const BackendSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AnchorScope.of(context).l;
    return Scaffold(
      key: const Key('backend-splash'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(strokeWidth: 8),
                ),
                const SizedBox(height: 28),
                Text(
                  l.backendPreparing,
                  key: const Key('backend-splash-text'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: AnchorTheme.baseTextSize,
                    color: AnchorTheme.ink,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "本地服务未启动" + 重试 + the path we looked for. Never a raw stack trace.
class BackendProblemCard extends StatelessWidget {
  const BackendProblemCard({
    super.key,
    required this.l,
    required this.result,
    required this.fallbackPath,
    required this.busy,
    required this.onRetry,
  });

  final L l;
  final BackendBootResult result;

  /// Used when the result carries no path (a platform callback failed).
  final String fallbackPath;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final path = result.executablePath.isEmpty
        ? fallbackPath
        : result.executablePath;
    final missing = result.status == BackendBootStatus.missing;
    final lines = <String>[
      missing ? l.backendMissingBody : l.backendTimeoutBody,
      if (path.isNotEmpty) l.backendExpectedPath(path),
      if (busy) l.backendStarting,
    ];
    return StatusBanner(
      key: const Key('backend-problem'),
      l: l,
      tone: BannerTone.problem,
      title: l.backendUnavailableTitle,
      body: lines.join('\n'),
      onRetry: busy ? null : onRetry,
      retryLabel: l.backendRetry,
    );
  }
}
