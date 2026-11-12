import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../services/lan_address.dart';
import '../../state/invitation_controller.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/invitation_card.dart';
import '../../widgets/status_banner.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'talk_screen.dart';

/// Senior home, redesigned 2026-11-10 (docs/design/senior-ui.md).
///
/// One primary action — talking — rendered as a single large disc, plus two
/// quiet secondary bars (play, call). Activities now happen inside the
/// conversation, so they no longer deserve an equal third tile; the space the
/// old settings tile left behind is used by the greeting and the flower count
/// instead of another card.
///
/// While this screen is visible it also lets [InvitationController] poll and
/// render the foreground invitation; leaving the screen stops that.
class SeniorHomeScreen extends StatefulWidget {
  const SeniorHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends State<SeniorHomeScreen> with RouteAware {
  /// The address the phone should be pointed at, read once at start.
  String? _addressLine;
  ModalRoute<void>? _route;
  bool _pressed = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // Read once: the LAN address does not change while the app runs, and a
    // network lookup on every rebuild would be waste.
    _addressLine = backendAddressForDisplay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) state.invitations.setHomeVisible(true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      if (!identical(route, _route)) {
        if (_route != null) anchorRouteObserver.unsubscribe(this);
        _route = route;
        anchorRouteObserver.subscribe(this, route);
      }
      state.invitations.setHomeVisible(route.isCurrent);
    }
  }

  @override
  void didPush() => state.invitations.setHomeVisible(true);

  @override
  void didPopNext() => state.invitations.setHomeVisible(true);

  @override
  void didPushNext() => state.invitations.setHomeVisible(false);

  @override
  void didPop() => state.invitations.setHomeVisible(false);

  @override
  void dispose() {
    anchorRouteObserver.unsubscribe(this);
    state.invitations.setHomeVisible(false);
    super.dispose();
  }

  String _greeting(L l) => switch (state.greetingKey) {
    'morning' => l.greetingMorning,
    'afternoon' => l.greetingAfternoon,
    _ => l.greetingEvening,
  };

  Future<void> _acceptInvitation() async {
    final session = await state.invitations.accept();
    if (!mounted) return;
    if (session == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(state.l.invitationFailed)));
      return;
    }
    state.adoptProactiveSession(session);
    await _openTalk();
  }

  Future<void> _dismissInvitation() async {
    await state.invitations.dismiss();
  }

  Future<void> _openTalk() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TalkScreen(state: state)));
  }

  @override
  Widget build(BuildContext context) {
    final l = state.l;
    return AnchorScaffold(
      state: state,
      title: l.appName,
      showBack: false,
      // Nothing on this screen is running, so there is nothing to stop: the
      // stop pill only appears inside the conversation. (The senior pressed it
      // here once and asked why it stayed — it must not live on the home page.)
      showStop: false,
      body: ListenableBuilder(
        listenable: state.invitations,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            // The disc takes the room that is left after the two bars; it never
            // shrinks below a comfortable thumb target.
            final disc = math.min(
              AnchorTheme.voiceDiscSize,
              math.max(170.0, constraints.maxWidth * 0.5),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _greetingRow(l),
                const SizedBox(height: 6),
                Text(
                  l.homePrompt,
                  key: const Key('main-text'),
                  style: const TextStyle(
                    fontSize: 26,
                    color: AnchorTheme.inkSoft,
                    height: 1.35,
                  ),
                ),
                // The one thing the phone needs from this computer: the address
                // to type. Small, grey and passive — a fact, not a control
                // (2026-11-12).
                if (_addressLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${l.backendAddressOnComputer}${_addressLine!}',
                      key: const Key('home-lan-address'),
                      style: const TextStyle(
                        fontSize: 22,
                        color: AnchorTheme.inkSoft,
                        height: 1.3,
                      ),
                    ),
                  ),
                if (state.offline) ...<Widget>[
                  const SizedBox(height: 12),
                  StatusBanner(
                    l: l,
                    title: l.offlineTitle,
                    body: l.offlineBody,
                    onRetry: state.refresh,
                  ),
                ],
                if (state.lastError != null && !state.offline) ...<Widget>[
                  const SizedBox(height: 12),
                  StatusBanner(
                    l: l,
                    tone: BannerTone.problem,
                    title: state.lastErrorText ?? l.unknownError,
                    onRetry: state.refresh,
                  ),
                ],
                if (state.invitations.offerVisible) ...<Widget>[
                  const SizedBox(height: 12),
                  InvitationCard(
                    l: l,
                    busy: state.invitations.busy,
                    onAccept: _acceptInvitation,
                    onDismiss: _dismissInvitation,
                  ),
                ],
                if (state.invitations.hint == InvitationHint.designatedDevice)
                  _deviceHint(l),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: _VoiceDisc(
                      size: disc,
                      label: l.actionTalk,
                      hint: l.actionTalkSub,
                      pressed: _pressed,
                      onTap: _openTalk,
                      onPressChange: (pressed) =>
                          setState(() => _pressed = pressed),
                    ),
                  ),
                ),
                _secondaryActions(context, l, wide),
                if (state.policy.setupApp) ...<Widget>[
                  const SizedBox(height: 12),
                  _settingsButton(context, l),
                ],
                const SizedBox(height: 6),
                _nextCheckin(l),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _greetingRow(L l) {
    final greeting = state.displayName.isEmpty
        ? _greeting(l)
        : '${_greeting(l)}，${state.displayName}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            greeting,
            key: const Key('home-greeting'),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w700,
              color: AnchorTheme.ink,
              height: 1.15,
            ),
          ),
        ),
        if (state.flowers > 0) _flowerChip(l),
      ],
    );
  }

  /// Encouragement only: a count, never a score or a level.
  Widget _flowerChip(L l) {
    return Container(
      key: const Key('home-flowers'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AnchorTheme.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.local_florist, size: 24, color: AnchorTheme.ochre),
          const SizedBox(width: 6),
          Text(
            '${state.flowers}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AnchorTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceHint(L l) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        l.invitationDeviceHint,
        key: const Key('invitation-device-hint'),
        style: const TextStyle(
          fontSize: 22,
          color: AnchorTheme.inkSoft,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _secondaryActions(BuildContext context, L l, bool wide) {
    // Only the family call is left beside the voice disc: activities now happen
    // inside the conversation (product decision 2026-11-10), so a separate
    // "play" entry would be a second door to the same room.
    return _secondaryBar(
      key: const Key('primary-call'),
      icon: Icons.phone_in_talk,
      label: l.actionCall,
      iconColor: AnchorTheme.jade,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => CallScreen(state: state))),
    );
  }

  Widget _secondaryBar({
    required Key key,
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AnchorTheme.paperRaised,
      borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AnchorTheme.buttonRadius),
            border: Border.all(color: AnchorTheme.line, width: 1.5),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AnchorTheme.ink,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 30,
                color: AnchorTheme.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsButton(BuildContext context, L l) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: OutlinedButton.icon(
        key: const Key('primary-settings'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(state: state)),
        ),
        icon: const Icon(Icons.settings, size: 30),
        label: Text(l.actionSettings, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  Widget _nextCheckin(L l) {
    final plan = state.nextReminder;
    final label = plan == null
        ? l.noNextCheckin
        : '${plan.localDate} ${plan.localTimeLabel}';
    return Text(
      '${l.nextCheckin}: $label',
      style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
    );
  }
}

/// The one big thing on the home screen: a physical-feeling disc.
///
/// A single deliberate motion (scale to 0.97 while pressed) stands in for the
/// scatter of hover effects; nothing else on this screen moves.
class _VoiceDisc extends StatelessWidget {
  const _VoiceDisc({
    required this.size,
    required this.label,
    required this.hint,
    required this.pressed,
    required this.onTap,
    required this.onPressChange,
  });

  final double size;
  final String label;
  final String hint;
  final bool pressed;
  final VoidCallback onTap;
  final ValueChanged<bool> onPressChange;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: '$label. $hint',
      child: GestureDetector(
        onTapDown: (_) => onPressChange(true),
        onTapCancel: () => onPressChange(false),
        onTapUp: (_) => onPressChange(false),
        child: AnimatedScale(
          key: const Key('primary-talk'),
          scale: pressed ? 0.97 : 1,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          child: Material(
            color: AnchorTheme.jade,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.mic,
                      size: size * 0.34,
                      color: AnchorTheme.onPrimary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: size * 0.15,
                        fontWeight: FontWeight.w700,
                        color: AnchorTheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
