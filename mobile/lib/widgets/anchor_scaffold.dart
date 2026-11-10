import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'stop_bar.dart';

/// Shared screen frame for the senior side: a large title, a scrolling body and
/// the persistent Stop control. Using one frame is what guarantees that Stop is
/// on *every* screen rather than on the screens someone remembered to touch.
class AnchorScaffold extends StatelessWidget {
  const AnchorScaffold({
    super.key,
    required this.state,
    required this.title,
    required this.body,
    this.subtitle,
    this.showBack = true,
    this.leading,
    this.footer,
    this.onStop,
    this.stopLabel,
    this.scrollable = true,
  });

  final AppState state;
  final String title;
  final String? subtitle;
  final Widget body;
  final bool showBack;
  final Widget? leading;
  final Widget? footer;
  final VoidCallback? onStop;
  final String? stopLabel;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final l = state.l;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 24,
              color: AnchorTheme.inkSoft,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
        ],
        body,
        if (footer != null) ...<Widget>[const SizedBox(height: 24), footer!],
        const SizedBox(height: 24),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        leading: leading ?? (showBack ? const BackButton() : null),
        automaticallyImplyLeading: showBack,
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        bottom: false,
        child: scrollable
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: content,
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: content,
              ),
      ),
      // Stop means "stop talking / stop listening". The family/setup phone has
      // no voice at all (architecture change 2026-11-10), so it gets no Stop
      // control either — there is nothing on this device for it to stop.
      bottomNavigationBar: state.policy.setupApp
          ? null
          : StopBar(
              l: l,
              label: stopLabel,
              onStop: onStop ?? () => _defaultStop(context),
            ),
    );
  }

  Future<void> _defaultStop(BuildContext context) async {
    await state.stopAll();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(state.l.stoppedTitle)));
  }
}

/// A titled block used across Settings and the caregiver screens.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? hint;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: AnchorTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AnchorTheme.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 30, color: AnchorTheme.primary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AnchorTheme.ink,
                        height: 1.25,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              if (hint != null && hint!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  hint!,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AnchorTheme.inkSoft,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A large, high-contrast primary action with an icon *and* a text label.
class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPressed,
    this.background = AnchorTheme.primary,
    this.foreground = AnchorTheme.onPrimary,
    this.minHeight = AnchorTheme.primaryActionHeight,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: '$label. $subtitle',
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AnchorTheme.border, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 46, color: foreground),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 22,
                            color: foreground,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
