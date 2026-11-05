import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';
import '../../widgets/call_helpers.dart';
import '../../widgets/status_banner.dart';

/// Call: saved family contacts, one confirmation, then the system dialer.
/// Calling keeps working with no network at all (SPEC §9 offline rule, S11).
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.state.hasContacts || widget.state.contactsFeatureMissing) {
      return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    await widget.state.loadContacts();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _call(Contact contact) async {
    final state = widget.state;
    await dialWithConfirmation(
      context,
      l: state.l,
      label: contact.label,
      phone: contact.phone,
      dial: () => state.callContact(contact),
    );
  }

  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final l = widget.state.l;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AnchorTheme.surface,
        title: Text(l.callAddContact, style: const TextStyle(fontSize: 28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('contact-name-field'),
              controller: nameController,
              style: const TextStyle(fontSize: 26),
              decoration: InputDecoration(labelText: l.callName),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('contact-phone-field'),
              controller: phoneController,
              style: const TextStyle(fontSize: 26),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l.callNumber),
            ),
          ],
        ),
        actions: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.cancel),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AnchorTheme.minTouchTarget,
            ),
            child: FilledButton(
              key: const Key('contact-save'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.save),
            ),
          ),
        ],
      ),
    );
    if (added != true) return;
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;
    widget.state.addLocalContact(label: name, phone: phone);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = state.l;
    return AnchorScaffold(
      state: state,
      title: l.callTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.offline)
            StatusBanner(
              l: l,
              title: l.offlineTitle,
              body: l.callOfflineHint,
              onRetry: _load,
            ),
          if (state.contactsFeatureMissing)
            StatusBanner(
              l: l,
              title: l.callContactsUnavailable,
              tone: BannerTone.notice,
            ),
          if (state.lastError != null && !state.offline)
            StatusBanner(
              l: l,
              tone: BannerTone.problem,
              title: state.lastErrorText ?? l.unknownError,
              onRetry: _load,
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(minHeight: 8),
            ),
          if (state.hasContacts) ...<Widget>[
            Text(l.callPick, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 12),
            for (final contact in state.contacts)
              _ContactTile(
                key: ValueKey<String>('contact-${contact.id}'),
                contact: contact,
                onTap: () => _call(contact),
              ),
          ] else if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.callNoContacts, style: AnchorTheme.reading),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('call-add-contact'),
            onPressed: _addContact,
            icon: const Icon(Icons.person_add, size: 30),
            label: Text(l.callAddContact, style: const TextStyle(fontSize: 24)),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({super.key, required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: '${contact.label}. ${contact.phone}',
        child: Material(
          color: AnchorTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AnchorTheme.border, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.phone_in_talk,
                    size: 40,
                    color: AnchorTheme.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          contact.label,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: AnchorTheme.ink,
                          ),
                        ),
                        Text(
                          contact.phone,
                          style: const TextStyle(
                            fontSize: 24,
                            color: AnchorTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 34),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
