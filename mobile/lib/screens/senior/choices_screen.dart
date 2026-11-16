import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/anchor_scaffold.dart';

/// Personal decisions stay on the senior's device; provider setup stays on the phone.
class ChoicesScreen extends StatefulWidget {
  const ChoicesScreen({super.key, required this.state});
  final AppState state;
  @override
  State<ChoicesScreen> createState() => _ChoicesScreenState();
}

class _ChoicesScreenState extends State<ChoicesScreen> {
  bool _working = false;
  String? _message;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !state.isSenior) return;
      await _run(() async {
        await state.loadConsents();
        await state.loadMemories();
        await state.loadDigests();
        await state.loadRelationships();
        return state.lastError == null;
      });
    });
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    state.clearError();
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = ok ? null : state.lastErrorText ?? state.l.unknownError;
    });
  }

  /// One of the two voice buttons. Selected is filled jade; the other is an
  /// outline, so the current choice is readable without colour alone.
  Widget _voiceButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final style = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: selected ? AnchorTheme.paper : AnchorTheme.jadeDeep,
    );
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(label, textAlign: TextAlign.center, style: style),
    );
    return selected
        ? FilledButton(
            key: key,
            onPressed: _working ? null : onPressed,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: _working ? null : onPressed,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
            child: child,
          );
  }

  /// Asks for the name, then saves it. One field, one button pair.
  ///
  /// Blank is a legitimate answer ("use the default"), so the dialog offers
  /// 「用回 Anchor」 as a second action instead of leaving the senior to guess.
  Future<void> _editAssistantName() async {
    final l = state.l;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        initial: state.assistantName,
        title: l.t('它叫什么名字', 'What is it called'),
        hint: l.t(
          '写您想叫的名字，比如「小安」。留空就用 Everhere。',
          'Type the name you want, for example “Xiao An”. Leave it blank for '
              'Everhere.',
        ),
        cancelLabel: l.cancel,
        saveLabel: l.save,
      ),
    );
    if (result == null || !mounted) return;
    await _run(() => state.setAssistantName(result));
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(state.l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(state.l.ok),
            ),
          ],
        ),
      ) ??
      false;

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _permission(
    String title,
    String capability,
    bool value, {
    String topic = '',
  }) => SwitchListTile(
    key: ValueKey('choice-$capability-$topic'),
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 24)),
    value: value,
    onChanged: _working
        ? null
        : (allowed) => _run(
            () => state.setConsent(
              capability: capability,
              topic: topic,
              allowed: allowed,
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    AnchorScope.of(context);
    final l = state.l;
    if (!state.isSenior) {
      return Scaffold(
        appBar: AppBar(title: Text(l.t('我的选择', 'My choices'))),
        body: Center(
          child: Text(
            l.t('这些选择由老人本人决定。', 'These choices belong to the older adult.'),
          ),
        ),
      );
    }
    return AnchorScaffold(
      state: state,
      title: l.t('我的选择', 'My choices'),
      showStop: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.t(
              '由您决定记住什么、分享什么。技术设置仍在家人的手机上。',
              'You decide what is remembered and shared. Technical setup stays on the family phone.',
            ),
            style: AnchorTheme.reading,
          ),
          if (_working) const LinearProgressIndicator(),
          if (_message != null)
            Text(
              _message!,
              key: const Key('choices-error'),
              style: AnchorTheme.reading,
            ),
          const SizedBox(height: 20),
          _section(l.t('聊天与声音', 'Conversation and voice'), [
            _permission(
              l.t(
                '允许云端处理语音和聊天',
                'Allow cloud voice and conversation processing',
              ),
              Capabilities.cloudProcessing,
              state.consent.cloudProcessing,
            ),
            Text(
              l.t(
                '语音和聊天内容可能发送给配置的云服务。关闭后在线聊天不可用。',
                'Speech and conversation may be sent to the configured cloud services. Online conversation needs this permission.',
              ),
            ),
            _permission(
              l.t('允许主动问候', 'Allow invitations to chat'),
              Capabilities.proactiveInvitations,
              state.consent.proactiveInvitations,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.t('说慢一点', 'Speak more slowly')),
              value: state.preferences?.isSlowPace ?? true,
              onChanged: _working
                  ? null
                  : (value) => _run(
                      () => state.updatePreferences({
                        'voice_pace': value ? 'slow' : 'normal',
                      }),
                    ),
            ),
            // Which of the two provider voices speaks (2026-11-16). Two big
            // buttons rather than a switch: a switch needs a label like "female
            // voice on/off", which is a riddle; a button pair is the answer.
            Text(
              l.t('用哪个声音说话', 'Which voice speaks'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: _voiceButton(
                    key: const Key('voice-female'),
                    label: l.t('女声', 'Female voice'),
                    selected: !state.prefersMaleVoice,
                    onPressed: () => _run(() => state.setVoiceGender(false)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _voiceButton(
                    key: const Key('voice-male'),
                    label: l.t('男声', 'Male voice'),
                    selected: state.prefersMaleVoice,
                    onPressed: () => _run(() => state.setVoiceGender(true)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // What the older adult calls the companion (2026-11-16). A row rather
            // than a bare text field: the name is a decision, and tapping it opens
            // one big field where they can type whatever they like.
            ListTile(
              key: const Key('choice-assistant-name'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                l.t('它叫什么名字', 'What is it called'),
                style: const TextStyle(fontSize: 24),
              ),
              subtitle: Text(
                state.assistantName.isEmpty ? l.anchor : state.assistantName,
                key: const Key('choice-assistant-name-value'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                ),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 26),
              onTap: _working ? null : _editAssistantName,
            ),
          ]),
          _section(l.t('与家人分享', 'Sharing with family'), [
            _permission(
              l.t('记录用于简报的日常信息', 'Keep observations for weekly updates'),
              Capabilities.recordObservations,
              state.consent.recordObservations,
            ),
            for (final topic in ShareTopics.all)
              _permission(
                l.topicLabel(topic),
                Capabilities.shareTopic,
                state.consent.shareTopicAllowed(topic),
                topic: topic,
              ),
            OutlinedButton.icon(
              key: const Key('stop-all-sharing'),
              icon: const Icon(Icons.lock_outline),
              onPressed: _working
                  ? null
                  : () async {
                      if (await _confirm(
                        l.t('停止全部分享？', 'Stop all sharing?'),
                        l.t(
                          '家人将无法再读取这些主题。已看过或复制的内容无法收回。',
                          'Future access to all topics will stop. Previously seen or copied content cannot be recalled.',
                        ),
                      )) {
                        await _run(state.stopAllSharing);
                      }
                    },
              label: Text(l.t('停止全部分享', 'Stop all sharing')),
            ),
          ]),
          _section(l.t('家人连接', 'Family connection'), [
            OutlinedButton(
              onPressed: _working
                  ? null
                  : () => _run(
                      () async => await state.createInvitation() != null,
                    ),
              child: Text(l.t('创建家人邀请码', 'Create a family invitation')),
            ),
            if (state.invitationToken != null)
              SelectableText(
                state.invitationToken!,
                style: AnchorTheme.reading,
              ),
            for (final relationship in state.relationships) ...[
              Text(
                relationship.counterpartName ?? l.t('家人', 'Family'),
                style: AnchorTheme.reading,
              ),
              if (relationship.isPending)
                FilledButton(
                  onPressed: _working
                      ? null
                      : () => _run(
                          () => state.approveRelationship(relationship.id),
                        ),
                  child: Text(l.t('允许这位家人连接', 'Allow this family connection')),
                ),
              if (relationship.isAccepted)
                OutlinedButton(
                  onPressed: _working
                      ? null
                      : () async {
                          if (await _confirm(
                            l.t('取消家人连接？', 'Disconnect family?'),
                            l.t(
                              '这位家人将无法再读取您的简报。',
                              'This person will lose access to your updates.',
                            ),
                          )) {
                            await _run(
                              () => state.revokeRelationship(relationship.id),
                            );
                          }
                        },
                  child: Text(l.t('取消连接', 'Disconnect')),
                ),
            ],
          ]),
          _section(l.t('先看简报，再决定是否分享', 'Review before sharing'), [
            Text(
              l.t(
                '生成上一个完整星期的简报。没有足够记录时，我们会如实说明。',
                'Prepare the last completed week. If there is not enough information, we will say so.',
              ),
            ),
            FilledButton.icon(
              key: const Key('generate-digest'),
              icon: const Icon(Icons.summarize_outlined),
              onPressed: _working ? null : () => _run(state.generateDigest),
              label: Text(l.t('准备上周简报', 'Prepare last week’s update')),
            ),
            for (final digest in state.digests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${digest.periodStart ?? ''} — ${digest.periodEnd ?? ''}',
                        style: const TextStyle(fontSize: 22),
                      ),
                      if (digest.isInsufficientData)
                        Text(
                          l.caregiverInsufficient,
                          style: AnchorTheme.reading,
                        ),
                      for (final item in digest.highlights)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '${l.topicLabel(item.topic)}: ${item.text}',
                            style: AnchorTheme.reading,
                          ),
                        ),
                      if (digest.status == 'delivered')
                        Text(
                          l.t(
                            '已分享；您仍可以关闭分享主题。',
                            'Shared. You can still turn off sharing topics.',
                          ),
                        ),
                      if (digest.canApprove || digest.status == 'approved')
                        FilledButton(
                          key: ValueKey('publish-digest-${digest.id}'),
                          onPressed: _working
                              ? null
                              : () async {
                                  if (await _confirm(
                                    l.t('分享这份简报？', 'Share this update?'),
                                    l.t(
                                      '只分享上面列出的内容给已连接的家人。',
                                      'Share only the listed highlights with your connected family.',
                                    ),
                                  )) {
                                    await _run(
                                      () => state.publishDigest(digest.id),
                                    );
                                  }
                                },
                          child: Text(
                            l.t('我已看过，允许分享', 'I have reviewed it — share'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ]),
          _section(l.t('记住的事情', 'Remembered facts'), [
            _permission(
              l.t('允许保存我批准的记忆', 'Allow memories I approve'),
              Capabilities.saveMemory,
              state.consent.saveMemory,
            ),
            if (state.memories.isEmpty)
              Text(l.t('目前没有保存的记忆。', 'No saved memories.')),
            for (final memory in state.memories)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(memory.fact, style: AnchorTheme.reading),
                      if (memory.isProposed)
                        FilledButton(
                          onPressed: _working
                              ? null
                              : () =>
                                    _run(() => state.approveMemory(memory.id)),
                          child: Text(l.t('允许记住', 'Allow this memory')),
                        ),
                      OutlinedButton(
                        key: ValueKey('delete-memory-${memory.id}'),
                        onPressed: _working
                            ? null
                            : () async {
                                if (await _confirm(
                                  l.t('忘记这件事？', 'Forget this fact?'),
                                  memory.fact,
                                )) {
                                  await _run(
                                    () => state.deleteMemory(memory.id),
                                  );
                                }
                              },
                        child: Text(l.t('忘记这件事', 'Forget this fact')),
                      ),
                    ],
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

/// One large text field, exactly as long as the dialog lives.
///
/// Same shape as the phone's address dialog: the controller belongs to the dialog
/// state, so a rebuild can never touch a disposed controller (a real crash on
/// 2026-11-12).
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initial,
    required this.title,
    required this.hint,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String initial;
  final String title;
  final String hint;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.hint,
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.inkSoft,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('assistant-name-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 12,
            style: const TextStyle(fontSize: 26, color: AnchorTheme.ink),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(counterText: ''),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('assistant-name-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          key: const Key('assistant-name-save'),
          onPressed: _submit,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
