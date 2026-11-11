/// The family/phone side's own vocabulary, 2026-11-11.
///
/// The older adult's appliance is built around one physical action: a voice disc
/// you press. The phone is the opposite kind of screen - a panel a family member
/// reads top to bottom while standing up, with a thumb. So it gets its own parts
/// (a header, a read-out strip, rows, a quiet note) drawn from the same paper /
/// ink / jade tokens instead of reusing the appliance's BigActionButton.
///
/// Rules every part here keeps:
/// * text is never smaller than 22 px (SPEC section 9), body copy stays at 24-26;
/// * anything tappable is at least 56 px tall;
/// * nothing overflows at 1.6x text - labels wrap inside a Flexible, values
///   ellipsize rather than push a chevron off the screen;
/// * colour is never the only channel: every state also carries a word.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Page opening: a jade rule, a small label, then the name in large text.
class HubHeader extends StatelessWidget {
  const HubHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final eyebrowText = eyebrow;
    final subtitleText = subtitle;
    final trailingWidget = trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (eyebrowText != null) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 4,
                height: 22,
                margin: const EdgeInsets.only(top: 3, right: 10),
                decoration: BoxDecoration(
                  color: AnchorTheme.jade,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  eyebrowText,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.jade,
                    letterSpacing: 1.2,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                  height: 1.2,
                ),
              ),
            ),
            if (trailingWidget != null) ...<Widget>[
              const SizedBox(width: 12),
              trailingWidget,
            ],
          ],
        ),
        if (subtitleText != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            subtitleText,
            style: const TextStyle(
              fontSize: 24,
              color: AnchorTheme.inkSoft,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// A one-line read-out: "label: value". Wraps into as many rows as it needs.
class HubReadout extends StatelessWidget {
  const HubReadout({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AnchorTheme.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (iconData != null) ...<Widget>[
            Icon(iconData, size: 24, color: AnchorTheme.jade),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$label：',
                    style: const TextStyle(color: AnchorTheme.inkSoft),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 23,
                color: AnchorTheme.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small heading above a group of rows, with a hairline running to the edge.
class HubSectionLabel extends StatelessWidget {
  const HubSectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.inkSoft,
                letterSpacing: 1,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (trailingWidget != null) ...<Widget>[
            trailingWidget,
            const SizedBox(width: 12),
          ],
          Expanded(child: Container(height: 1.5, color: AnchorTheme.line)),
        ],
      ),
    );
  }
}

/// One thing you can open: an icon, a label, an optional value and a chevron.
///
/// This replaces the stack of identical outlined buttons the phone used to show;
/// a list of rows says "these are places" instead of "these are buttons".
class HubRow extends StatelessWidget {
  const HubRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.detail,
    this.below,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final String? detail;

  /// Extra content printed under the row, still part of this entry (a hint that
  /// belongs to the row rather than to the page).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final valueText = value;
    final detailText = detail;
    final row = Material(
      color: AnchorTheme.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
        side: const BorderSide(color: AnchorTheme.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EFE9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 26, color: AnchorTheme.jade),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AnchorTheme.ink,
                        height: 1.25,
                      ),
                    ),
                    if (detailText != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        detailText,
                        style: const TextStyle(
                          fontSize: 22,
                          color: AnchorTheme.inkSoft,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (valueText != null) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    valueText,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      color: AnchorTheme.inkSoft,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 26,
                color: AnchorTheme.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
    final belowWidget = below;
    if (belowWidget == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: belowWidget,
        ),
      ],
    );
  }
}

/// A bordered block with a title, an optional hint and body content.
///
/// Softer and quieter than [HubRow]: used when the content is text to read or a
/// form, not one place to open.
class HubPanel extends StatelessWidget {
  const HubPanel({
    super.key,
    required this.child,
    this.title,
    this.hint,
    this.icon,
    this.tone = HubTone.plain,
  });

  final Widget child;
  final String? title;
  final String? hint;
  final IconData? icon;
  final HubTone tone;

  @override
  Widget build(BuildContext context) {
    final titleText = title;
    final hintText = hint;
    final iconData = icon;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(color: tone.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (titleText != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (iconData != null) ...<Widget>[
                  Icon(iconData, size: 28, color: tone.accent),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    titleText,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AnchorTheme.ink,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            if (hintText != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                hintText,
                style: const TextStyle(
                  fontSize: 22,
                  color: AnchorTheme.inkSoft,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// The quiet explanation panels: pale jade for "how this works", pale ochre for
/// something worth a second look. Both stay at ink-on-tint above 7:1.
class HubNote extends StatelessWidget {
  const HubNote({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.tone = HubTone.jade,
  });

  final String title;
  final String body;
  final IconData icon;
  final HubTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(color: tone.border, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 30, color: tone.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 23,
                    color: AnchorTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width primary action for the phone: one per screen, at most.
class HubPrimaryButton extends StatelessWidget {
  const HubPrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 30),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AnchorTheme.jade,
          foregroundColor: AnchorTheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
          ),
        ),
      ),
    );
  }
}

/// The small "nothing hidden here" footer used by the family screens.
class HubFooterNote extends StatelessWidget {
  const HubFooterNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 22,
        color: AnchorTheme.inkSoft,
        height: 1.4,
      ),
    );
  }
}

/// The tones the panels and notes may take. Only colours already in the palette,
/// and each one is paired with a word in the copy, so colour is never the only
/// signal that something is off.
enum HubTone {
  plain(AnchorTheme.paperRaised, AnchorTheme.line, AnchorTheme.jade),
  jade(Color(0xFFE7EFE9), AnchorTheme.jade, AnchorTheme.jade),
  ochre(Color(0xFFF6EEDC), AnchorTheme.ochre, AnchorTheme.ochre);

  const HubTone(this.fill, this.border, this.accent);

  final Color fill;
  final Color border;
  final Color accent;
}
