import 'package:flutter/material.dart';

import '../config.dart';
import '../services/backend_address_store.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/status_banner.dart';

/// Demo role picker, redesigned 2026-11-10 (docs/design/senior-ui.md).
///
/// Not a form: one question ("who is using this computer?") and two plates. The
/// senior plate is the product's front door, so it gets the whole visual weight;
/// the family plate is visibly quieter because it is a one-off setup errand.
/// There is no password anywhere (SPEC §4): the demo backend issues a bearer
/// token for a seeded user id.
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

  /// The phone's backend address is entered here, on the phone (2026-11-12).
  ///
  /// It used to be compiled in with `--dart-define`, which meant the address and
  /// the network had to agree at build time: the computer's IP changes per Wi-Fi,
  /// so the app went offline the moment the network did. Typing it once fixes
  /// that for good. The Windows appliance keeps the compiled-in loopback address
  /// and never shows this.
  Future<void> _changeBackend() async {
    final state = widget.state;
    final l = state.l;
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _BackendAddressDialog(initial: state.apiBaseLabel, l: l),
    );
    if (result == null || !mounted) return;
    final address = result.trim();
    if (address.isEmpty) return;
    if (!state.api.retarget(address)) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.backendAddressInvalid)));
      return;
    }
    state.retargetBackend(address);
    await const BackendAddressStore().save(address);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(l.backendAddressSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = state.l;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 900 : 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _wordmark(l),
                  const SizedBox(height: 40),
                  Text(
                    l.loginTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AnchorTheme.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.loginSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      color: AnchorTheme.inkSoft,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _seniorPlate(l),
                  const SizedBox(height: 18),
                  _familyPlate(l),
                  if (_signingIn) ...<Widget>[
                    const SizedBox(height: 28),
                    const LinearProgressIndicator(
                      minHeight: 8,
                      color: AnchorTheme.jade,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.loading,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ],
                  if (_failed) ...<Widget>[
                    const SizedBox(height: 20),
                    StatusBanner(
                      l: l,
                      tone: BannerTone.problem,
                      title: l.loginFailed,
                      body: state.lastErrorText,
                      onRetry: () => _enter(AnchorConfig.seniorDemo.userId),
                    ),
                  ],
                  const SizedBox(height: 28),
                  // Honest about where the address came from (2026-11-12): on the
                  // phone a compiled-in value is a guess, so it is labelled 还没设置
                  // instead of being shown as if it were the computer's address.
                  Text(
                    state.policy.setupApp
                        ? '${l.backendLabel}: ${state.apiBaseLabel}'
                              '（${state.addressChosenHere ? l.backendAddressLastUsed : l.backendAddressNotSet}）'
                        : '${l.backendLabel}: ${state.apiBaseLabel}'
                              '（${l.backendAddressComputer}）',
                    key: const Key('backend-address-line'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      color: AnchorTheme.inkSoft,
                    ),
                  ),
                  // Only the phone (the setup app) gets this: its address is a
                  // real choice. The Windows appliance talks to the backend
                  // bundled next to it and has nothing to configure.
                  if (state.policy.setupApp)
                    TextButton.icon(
                      key: const Key('backend-change'),
                      onPressed: _signingIn ? null : _changeBackend,
                      icon: const Icon(Icons.lan_outlined, size: 22),
                      label: Text(
                        l.backendAddressChange,
                        style: const TextStyle(fontSize: 22),
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

  Widget _wordmark(L l) {
    // The real mark (a bowl with three sound waves) instead of a Material anchor
    // icon, 2026-11-12. It is the same file the launcher and the Windows icon are
    // generated from, so the app looks like itself everywhere.
    //
    // Wrap, not Row, for the two pieces of text: at 1.3x text they no longer fit
    // a 390 px phone and a Row would clip the tagline.
    return Column(
      children: <Widget>[
        Image.asset(
          'assets/images/anchor-logo.png',
          width: 104,
          height: 104,
          filterQuality: FilterQuality.high,
          semanticLabel: l.appName,
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: <Widget>[
            Text(
              l.appName,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.jade,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              l.tagline,
              style: const TextStyle(fontSize: 22, color: AnchorTheme.inkSoft),
            ),
          ],
        ),
      ],
    );
  }

  /// The senior's front door: the whole plate is one target.
  Widget _seniorPlate(L l) {
    final name = AnchorConfig.seniorDemo.displayName(english: l.isEnglish);
    return Semantics(
      button: true,
      label: '${l.loginSenior} $name',
      child: Material(
        color: AnchorTheme.jade,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        child: InkWell(
          key: const Key('login-senior'),
          borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
          splashColor: AnchorTheme.jadeDeep,
          onTap: _signingIn
              ? null
              : () => _enter(AnchorConfig.seniorDemo.userId),
          child: Container(
            constraints: const BoxConstraints(minHeight: 196),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            child: Row(
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AnchorTheme.paperRaised.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AnchorTheme.paperRaised.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.elderly,
                    size: 52,
                    color: AnchorTheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: AnchorTheme.onPrimary,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.loginSenior,
                        style: TextStyle(
                          fontSize: 26,
                          color: AnchorTheme.onPrimary.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 40,
                  color: AnchorTheme.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The family plate: visibly secondary, for a one-off setup errand.
  Widget _familyPlate(L l) {
    final name = AnchorConfig.caregiverDemo.displayName(english: l.isEnglish);
    return Semantics(
      button: true,
      label: '${l.loginCaregiver} $name',
      child: Material(
        color: AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        child: InkWell(
          key: const Key('login-caregiver'),
          borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
          onTap: _signingIn
              ? null
              : () => _enter(AnchorConfig.caregiverDemo.userId),
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.family_restroom,
                  size: 34,
                  color: AnchorTheme.inkSoft,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '$name · ${l.loginCaregiver}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: AnchorTheme.ink,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 32,
                  color: AnchorTheme.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The address editor: a small stateful dialog so the controller lives exactly as
/// long as the dialog does (disposing one from the caller crashed the field).
class _BackendAddressDialog extends StatefulWidget {
  const _BackendAddressDialog({required this.initial, required this.l});

  final String initial;
  final L l;

  @override
  State<_BackendAddressDialog> createState() => _BackendAddressDialogState();
}

class _BackendAddressDialogState extends State<_BackendAddressDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Text(l.backendAddressTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.backendAddressHint,
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.inkSoft,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('backend-address-field'),
            controller: _controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 24),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'http://'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('backend-address-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('backend-address-save'),
          onPressed: _submit,
          child: Text(l.save),
        ),
      ],
    );
  }
}
