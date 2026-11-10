import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../state/invitation_controller.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/invitation_card.dart';
import '../../widgets/status_banner.dart';
import 'activity_screen.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'talk_screen.dart';

/// Senior home: exactly three primary actions plus Settings (SPEC §9, S4/S5).
///
/// Both layouts reach every task in one tap; only the arrangement differs
/// (phone: a column, tablet: a row of cards). While this screen is the visible
/// route it also lets [InvitationController] poll and render the foreground
/// invitation; leaving the screen (route covered or popped) stops that.
class SeniorHomeScreen extends StatefulWidget {
  const SeniorHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends State<SeniorHomeScreen> with RouteAware {
  ModalRoute<void>? _route;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // The initial route is pushed before this widget exists, so also ask on the
    // first frame; RouteAware then tracks every push/pop after that.
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TalkScreen(state: state)));
  }

  Future<void> _dismissInvitation() async {
    await state.invitations.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final l = state.l;
    return AnchorScaffold(
      state: state,
      title: l.appName,
      showBack: false,
      body: ListenableBuilder(
        listenable: state.invitations,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  state.displayName.isEmpty
                      ? _greeting(l)
                      : '${_greeting(l)}，${state.displayName}',
                  key: const Key('home-greeting'),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.homePrompt,
                  key: const Key('main-text'),
                  style: AnchorTheme.reading,
                ),
                const SizedBox(height: 16),
                if (state.offline)
                  StatusBanner(
                    l: l,
                    title: l.offlineTitle,
                    body: l.offlineBody,
                    onRetry: state.refresh,
                  ),
                if (state.lastError != null && !state.offline)
                  StatusBanner(
                    l: l,
                    tone: BannerTone.problem,
                    title: state.lastErrorText ?? l.unknownError,
                    onRetry: state.refresh,
                  ),
                if (state.invitations.offerVisible) ...<Widget>[
                  InvitationCard(
                    l: l,
                    busy: state.invitations.busy,
                    onAccept: _acceptInvitation,
                    onDismiss: _dismissInvitation,
                  ),
                  const SizedBox(height: 16),
                ],
                if (state.invitations.hint == InvitationHint.designatedDevice)
                  _deviceHint(l),
                _actions(context, l, wide),
                // The older adult's Windows appliance has no settings UI at all
                // (architecture change 2026-11-10); this tile only belongs to
                // the family/setup phone.
                if (state.policy.setupApp) ...<Widget>[
                  const SizedBox(height: 16),
                  _settingsButton(context, l),
                ],
                const SizedBox(height: 16),
                _nextCheckin(l),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _deviceHint(L l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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

  Widget _actions(BuildContext context, L l, bool wide) {
    final talk = _action(
      key: const Key('primary-talk'),
      icon: Icons.record_voice_over,
      label: l.actionTalk,
      subtitle: l.actionTalkSub,
      background: AnchorTheme.primary,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => TalkScreen(state: state))),
    );
    final play = _action(
      key: const Key('primary-play'),
      icon: Icons.extension,
      label: l.actionPlay,
      subtitle: l.actionPlaySub,
      background: AnchorTheme.accent,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ActivityScreen(state: state)),
      ),
    );
    final call = _action(
      key: const Key('primary-call'),
      icon: Icons.phone_in_talk,
      label: l.actionCall,
      subtitle: l.actionCallSub,
      background: AnchorTheme.primary,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => CallScreen(state: state))),
    );

    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: talk),
            const SizedBox(width: 16),
            Expanded(child: play),
            const SizedBox(width: 16),
            Expanded(child: call),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        talk,
        const SizedBox(height: 14),
        play,
        const SizedBox(height: 14),
        call,
      ],
    );
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color background,
    required VoidCallback onTap,
  }) {
    return BigActionButton(
      key: key,
      icon: icon,
      label: label,
      subtitle: subtitle,
      background: background,
      onPressed: onTap,
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
        icon: const Icon(Icons.settings, size: 32),
        label: Text(l.actionSettings, style: const TextStyle(fontSize: 28)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AnchorTheme.minTouchTarget, 72),
        ),
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
      style: const TextStyle(fontSize: 24, color: AnchorTheme.inkSoft),
    );
  }
}
