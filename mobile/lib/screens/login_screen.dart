import 'package:flutter/material.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/anchor_scaffold.dart';
import '../widgets/status_banner.dart';

/// Demo role picker. There is no password anywhere (SPEC §4): the demo backend
/// issues a bearer token for a seeded user id.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _signingIn = false;
  bool _failed = false;

  Future<void> _enter(int userId) async {
    setState(() {
      _signingIn = true;
      _failed = false;
    });
    final ok = await widget.state.signInDemo(userId);
    if (!mounted) return;
    setState(() {
      _signingIn = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = state.l;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 680 : 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(
                        Icons.anchor,
                        size: 64,
                        color: AnchorTheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.appName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: AnchorTheme.ink,
                        ),
                      ),
                      Text(
                        l.tagline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          color: AnchorTheme.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l.loginTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AnchorTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.loginSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          color: AnchorTheme.inkSoft,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      BigActionButton(
                        key: const Key('login-senior'),
                        icon: Icons.elderly,
                        label: l.loginSenior,
                        subtitle: AnchorConfig.seniorDemo.displayName(
                          english: l.isEnglish,
                        ),
                        onPressed: _signingIn
                            ? null
                            : () => _enter(AnchorConfig.seniorDemo.userId),
                      ),
                      const SizedBox(height: 16),
                      BigActionButton(
                        key: const Key('login-caregiver'),
                        icon: Icons.family_restroom,
                        label: l.loginCaregiver,
                        subtitle: AnchorConfig.caregiverDemo.displayName(
                          english: l.isEnglish,
                        ),
                        background: AnchorTheme.accent,
                        foreground: AnchorTheme.onAccent,
                        onPressed: _signingIn
                            ? null
                            : () => _enter(AnchorConfig.caregiverDemo.userId),
                      ),
                      if (_signingIn) ...<Widget>[
                        const SizedBox(height: 20),
                        const LinearProgressIndicator(minHeight: 8),
                        const SizedBox(height: 8),
                        Text(
                          l.loading,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ],
                      if (_failed) ...<Widget>[
                        const SizedBox(height: 16),
                        StatusBanner(
                          l: l,
                          tone: BannerTone.problem,
                          title: l.loginFailed,
                          body: state.lastErrorText,
                          onRetry: () => _enter(AnchorConfig.seniorDemo.userId),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        '${l.backendLabel}: ${state.apiBaseLabel}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          color: AnchorTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
