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
