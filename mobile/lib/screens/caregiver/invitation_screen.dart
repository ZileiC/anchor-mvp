import 'package:flutter/material.dart';

import '../../app.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/hub.dart';
import '../../widgets/status_banner.dart';

/// Caregiver invitation acceptance: accepting creates a *pending* link only, so
/// nothing is shared until the older adult approves (SPEC §6.1, S12).
///
/// Redesign 2026-11-11: the consequence is stated before the field, not after a
/// failure, and the screen keeps a single filled action.
class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key, required this.state});

  final AppState state;

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _accepted = false;
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _busy = true;
      _invalid = false;
      _accepted = false;
    });
    final ok = await widget.state.acceptInvitation(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _accepted = ok;
      _invalid = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    final l = state.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.caregiverInvite)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              HubNote(
                icon: Icons.qr_code_2,
                title: l.caregiverInvite,
                body: l.caregiverInviteHint,
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('invitation-token-field'),
                controller: _controller,
                style: const TextStyle(fontSize: 26, color: AnchorTheme.ink),
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _accept(),
                decoration: InputDecoration(labelText: l.caregiverInvite),
              ),
              const SizedBox(height: 16),
              HubPrimaryButton(
                key: const Key('invitation-accept'),
                icon: Icons.link,
                label: l.caregiverAccept,
                onPressed: _busy ? null : _accept,
              ),
              if (_busy) ...<Widget>[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 8),
              ],
              if (_accepted) ...<Widget>[
                const SizedBox(height: 16),
                StatusBanner(
                  l: l,
                  title: l.caregiverAccepted,
                  tone: BannerTone.notice,
                ),
              ],
              if (_invalid) ...<Widget>[
                const SizedBox(height: 16),
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: l.caregiverInvalid,
                  body: state.lastErrorText,
                  onRetry: _accept,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
