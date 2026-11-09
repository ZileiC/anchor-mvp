import '../services/api_client.dart';

/// Bilingual copy: Chinese is the default, English is used when the locale is
/// `en` (SPEC §9 "UI text is bilingual"). No health or diagnostic wording.
class L {
  const L(this.locale);

  final String locale;

  static const L zh = L('zh-CN');
  static const L en = L('en');

  static L of(String? value) => value == 'en' ? en : zh;

  bool get isEnglish => locale == 'en';

  String t(String chinese, String english) => isEnglish ? english : chinese;

  // -- global ---------------------------------------------------------------
  String get appName => 'Anchor';
  String get tagline => t('安心陪伴', 'A calm companion');
  String get stop => t('停止', 'Stop');
  String get notNow => t('现在不要', 'Not now');
  String get stopHint => t('随时可以让它停下来', 'You can stop at any time');
  String get stoppedTitle => t('已经停下了', 'Stopped');
  String get back => t('返回', 'Back');
  String get retry => t('再试一次', 'Try again');
  String get cancel => t('取消', 'Cancel');
  String get ok => t('好的', 'OK');
  String get save => t('保存', 'Save');
  String get close => t('关闭', 'Close');
  String get loading => t('正在连接…', 'Connecting…');
  String get unknownError =>
      t('出了点小问题，再试一次。', 'Something went wrong. Please try again.');
  String get offlineTitle => t('现在无法上网', 'No internet right now');
  String get offlineBody => t(
    '在线聊天暂时用不了。你仍然可以停止、查看设置、玩已保存的活动，也可以打电话。',
    'Online conversation is unavailable. You can still stop, open settings, '
        'use saved activities and make a phone call.',
  );
  String get typeInstead => t('打字代替', 'Type instead');
  String get typeHere => t('也可以在这里打字', 'You can also type here');
  String get send => t('发送', 'Send');
  String get done => t('完成', 'Done');

  // -- login ----------------------------------------------------------------
  String get loginTitle => t('这是谁的手机？', 'Who is using this device?');
  String get loginSubtitle =>
      t('演示版：选一个身份就能进入。', 'Demo build: pick who is using it to enter.');
  String get loginSenior => t('我是老人', 'I am the older adult');
  String get loginCaregiver => t('我是家人', 'I am the family member');
  String get loginFailed => t(
    '进不去。后台可能还没启动，或者演示数据还没准备好。',
    'Could not sign in. The backend may not be running or the demo data is not seeded yet.',
  );
  String get backendLabel => t('后台地址', 'Backend');
  String get signIn => t('进入', 'Enter');

  // -- local backend startup ------------------------------------------------
  String get backendPreparing => t('正在准备本地服务…', 'Preparing the local service…');
  String get backendUnavailableTitle =>
      t('本地服务未启动', 'The local service is not running');
  String get backendMissingBody => t(
    '没有找到后台程序。它应该和本程序放在同一个文件夹里。',
    'The backend program was not found. It belongs in the same folder as this app.',
  );
  String get backendTimeoutBody =>
      t('后台程序启动得太慢，还没有准备好。', 'The backend is taking too long to be ready.');
  String get backendStarting =>
      t('正在重新启动本地服务…', 'Restarting the local service…');
  String backendExpectedPath(String path) =>
      t('需要的文件：$path', 'Expected file: $path');
  String get backendRetry => t('重试', 'Retry');

  // -- senior home ----------------------------------------------------------
  String get greetingMorning => t('早上好', 'Good morning');
  String get greetingAfternoon => t('下午好', 'Good afternoon');
  String get greetingEvening => t('晚上好', 'Good evening');
  String get homePrompt => t('想做什么？', 'What would you like to do?');
  String get actionTalk => t('聊一聊', 'Talk');
  String get actionTalkSub => t('说说话，我听着', 'Talk with me, I am listening');
  String get actionPlay => t('玩一玩', 'Play');
  String get actionPlaySub => t('做个小活动，几分钟', 'A short activity, a few minutes');
  String get actionCall => t('打电话', 'Call');
  String get actionCallSub => t('给家人打个电话', 'Call your family');
  String get actionSettings => t('设置', 'Settings');
  String get nextCheckin => t('下次问候', 'Next check-in');
  String get noNextCheckin => t('暂时没有安排', 'Nothing scheduled');
  String get invitationTitle => t('现在想聊聊天吗？', 'Would you like to chat now?');
  String get invitationBody =>
      t('我在。聊几句，或者今天先不用。', 'I am here. A few words, or not today.');
  String get invitationAccept => t('聊一会儿', 'Chat a while');
  String get invitationDismiss => t('今天不用', 'Not today');
  String get invitationDeviceHint => t(
    '这台设备还没有用来接收问候。可以在设置里打开“用这台设备接收问候”。',
    'This device is not the one for check-ins yet. Turn on “Use this device for check-ins” in settings.',
  );
  String get invitationFailed =>
      t('这次没能开始聊天，可以再试一次。', 'That could not start. You can try again.');

  // -- talk -----------------------------------------------------------------
  String get talkTitle => t('聊天', 'Talk');
  String get talkStarting => t('正在打开麦克风…', 'Opening the microphone…');
  String get talkEmpty => t('说一句话开始吧。', 'Say something to begin.');
  String get you => t('你', 'You');
  String get anchor => t('Anchor', 'Anchor');
  String get micOn => t('麦克风已打开', 'Microphone is on');
  String get micOff => t('麦克风已关闭', 'Microphone is off');
  String get listening => t('我在听', 'Listening');
  String get listeningHint =>
      t('说完了按“说完了”，或者直接打字。', 'When you are done, tap Done, or type instead.');
  String get doneSpeaking => t('说完了', 'Done');
  String get startTalking => t('开始说话', 'Start talking');
  String get repeat => t('再说一遍', 'Say that again');
  String get repeatNothing => t('还没有可以重复的话。', 'Nothing to repeat yet.');
  String get resumeTalk => t('继续聊天', 'Start again');
  String get talkConsentNeeded => t(
    '要先在设置里打开“语音在云端处理”，我才能陪你聊天。',
    'Turn on “process speech in the cloud” in settings before we can talk.',
  );
  String get goToSettings => t('去设置', 'Open settings');
  String get micUnavailable => t(
    '这个设备的麦克风用不了，可以打字。',
    'The microphone is unavailable here. You can type instead.',
  );
  String get turnFailed => t('这句话没送出去。', 'That message did not go through.');
  String get sessionStopped => t('这次聊天已经停了。', 'This conversation has stopped.');
  String get needConsentCloud => t(
    '还差一个同意：语音在云端处理。',
    'One permission is missing: cloud processing of speech.',
  );

  // -- activity -------------------------------------------------------------
  String get activityTitle => t('玩一玩', 'Play');
  String get activityTrivia => t('小问答', 'Quiz');
  String get activityStory => t('小故事', 'Story');
  String get activityMemory => t('记一记', 'Remember');
  String get activityChoose => t('选一个', 'Choose one');
  String get activityThink => t('想一想，慢慢来', 'Take your time');
  String get activityThanks => t('谢谢你告诉我。', 'Thank you for telling me.');
  String get activityEmpty =>
      t('活动暂时打不开。', 'Activities are unavailable right now.');
  String get activityCached =>
      t('正在用上次保存的活动。', 'Using the activities saved earlier.');
  String get activityFinish => t('结束这个活动', 'Finish this activity');
  String get activityDone =>
      t('活动结束了，谢谢你。', 'That is the end of this activity. Thank you.');
  String get activityAnother => t('换一个', 'Another one');
  String get activityNoCache => t(
    '还没有下载过活动，等能上网时再来。',
    'No saved activities yet. Come back when the connection is available.',
  );
  String activityMinutesLeft(int minutes) =>
      t('还有 $minutes 分钟', '$minutes min left');
  String activitySecondsLeft(int seconds) =>
      t('还有 $seconds 秒', '$seconds s left');

  // -- call -----------------------------------------------------------------
  String get callTitle => t('打电话', 'Call');
  String get callPick => t('给谁打？', 'Who would you like to call?');
  String callConfirm(String name) => t('要打电话给$name吗？', 'Call $name?');
  String get callYes => t('打吧', 'Yes, call');
  String get callNo => t('先不打', 'Not now');
  String callLaunchFailed(String phone) => t(
    '没能打开电话，号码是：$phone',
    'Could not open the phone app. The number is: $phone',
  );
  String get callNoContacts => t('还没有保存的电话号码。', 'No saved phone numbers yet.');
  String get callAddContact => t('添加一个号码', 'Add a number');
  String get callName => t('怎么称呼', 'Name');
  String get callNumber => t('电话号码', 'Phone number');
  String get callDidHappen => t('打完了吗？', 'Did the call happen?');
  String get callRecorded => t('已经记下了。', 'Recorded.');
  String get callContactsUnavailable => t(
    '联系人服务暂时不可用，下面是这台设备上保存的号码。',
    'The contact service is unavailable; showing numbers saved on this device.',
  );
  String get callOfflineHint =>
      t('打电话不需要上网。', 'Making a phone call does not need the internet.');

  // -- settings -------------------------------------------------------------
  String get settingsTitle => t('设置', 'Settings');
  String get settingsGreeting => t('问候时间', 'Greeting window');
  String get settingsFrom => t('从', 'From');
  String get settingsTo => t('到', 'To');
  String get settingsQuiet => t('安静时间', 'Quiet hours');
  String get settingsQuietHint =>
      t('这段时间不会主动打扰你。', 'No proactive contact during this time.');
  String get settingsPause => t('暂停问候', 'Pause check-ins');
  String get settingsPauseHint =>
      t('打开后不会主动来找你。', 'When on, no proactive invitations are sent.');
  String get settingsPace => t('说话快慢', 'Voice pace');
  String get settingsPaceSlow => t('慢一点', 'Slower');
  String get settingsPaceNormal => t('正常', 'Normal');
  String get settingsShort => t('回答简短一些', 'Keep replies short');
  String get settingsLanguage => t('语言', 'Language');
  String get settingsLanguageZh => t('中文', 'Chinese');
  String get settingsLanguageEn => t('English', 'English');
  String get settingsMemories => t('记住的事情', 'Saved memories');
  String get settingsMemoriesEmpty => t('还没有记住的事情。', 'Nothing saved yet.');
  String get settingsMemoryProposed => t('等你确认', 'Waiting for you');
  String get settingsMemoryApprove => t('记住它', 'Remember it');
  String get settingsMemoryDelete => t('删掉', 'Delete');
  String get settingsSharing => t('可以告诉家人的话题', 'Topics you share with family');
  String get settingsSharingHint => t(
    '默认什么都不分享。要不要分享，由你决定。',
    'Nothing is shared by default. You decide what to share.',
  );
  String get settingsConsents => t('这些事要我怎么做', 'What I am allowed to do');
  String get settingsConsentCloud =>
      t('语音在云端处理', 'Process speech in the cloud');
  String get settingsConsentProactive => t('主动来问候', 'Proactive check-ins');
  String get settingsConsentMemory => t('记住我说的事情', 'Remember things I say');
  String get settingsConsentObserve =>
      t('记录用于周简报的内容', 'Record observations for updates');
  String get settingsDigest => t('给家人的简报', 'Weekly update for family');
  String get settingsDigestEmpty => t('这周还没有简报。', 'No update yet this week.');
  String get settingsDigestApprove => t('同意发给家人', 'Approve for family');
  String get settingsDigestEdit => t('改一下说法', 'Edit the wording');
  String get settingsDigestApproved =>
      t('已经同意，家人可以看了。', 'Approved. Family can read it now.');
  String get settingsDigestWaiting =>
      t('等你同意才会发给家人。', 'It is only sent to family after you approve.');
  String get settingsRevoke => t('断开家人的访问', 'Revoke family access');
  String get settingsRevokeConfirm => t(
    '确定要断开吗？断开后家人看不到你的简报。',
    'Revoke access? Family will no longer see your updates.',
  );
  String get settingsDeleteData => t('删除我的数据', 'Delete my data');
  String get settingsDeleteConfirm => t(
    '这会删除全部聊天记录、记住的事情和简报。确定吗？',
    'This deletes all conversations, saved memories and updates. Continue?',
  );
  String get settingsDeleted => t('已经删除了。', 'Deleted.');
  String get settingsSignOut => t('退出', 'Sign out');
  String get settingsInvite => t('邀请家人', 'Invite family');
  String settingsInviteCode(String token) =>
      t('把这个码告诉家人：$token', 'Give this code to your family: $token');
  String get settingsInviteFailed =>
      t('没有生成邀请码。', 'Could not create an invite code.');
  String get settingsFamily => t('我的家人', 'My family');
  String get settingsRelPending => t('等待你同意', 'Waiting for your approval');
  String get settingsRelAccepted => t('已连接', 'Connected');
  String get settingsRelRevoked => t('已断开', 'Revoked');
  String get settingsApproveRel => t('同意连接', 'Approve connection');
  String get settingsNoFamily => t('还没有家人连接。', 'No family connected yet.');
  String get settingsProposals => t('家人的建议', 'Suggestions from family');
  String get settingsNoProposals => t('暂时没有建议。', 'No suggestions right now.');
  String get settingsProposalAccept => t('同意这个安排', 'Accept this schedule');
  String get settingsProposalDecline => t('不用了', 'No thanks');
  String get settingsUpdated => t('已经保存。', 'Saved.');
  String get settingsSaveFailed =>
      t('没保存上，再试一次。', 'Could not save. Please try again.');
  String get settingsSnooze => t('今天先不要问候', 'Skip today');
  String get settingsSnoozed => t('今天不会再主动问候。', 'No more check-ins today.');
  String get settingsDesignatedDevice =>
      t('用这台设备接收问候', 'Use this device for check-ins');
  String get settingsDesignatedDeviceHint => t(
    '一条问候只送到一台设备。换了设备要重新打开。',
    'A check-in goes to one device. Turn this on again if you switch devices.',
  );
  String get settingsNextCheckin => t('下次问候时间', 'Next check-in');
  String get settingsRefresh => t('刷新', 'Refresh');

  // -- AI providers (model + speech recognition) ---------------------------
  String get aiProvidersTitle =>
      t('AI 接入（模型/语音）', 'AI connection (model / speech)');
  String get aiProvidersEntryHint => t(
    '接上真的对话模型和语音识别。不接也能用，但回复是离线模板，语音不会假装听懂。',
    'Connect a real chat model and speech recognition. Without them the app '
        'still works, but replies are offline templates and speech is never faked.',
  );
  String get aiProvidersSeniorOnly => t(
    '由老人管理。家人不能修改 AI 接入。',
    'Managed by the older adult. Family members cannot change AI settings.',
  );
  String get aiLlmSection => t('对话模型（DeepSeek）', 'Chat model (DeepSeek)');
  String get aiLlmHint => t(
    '填入 DeepSeek 的地址和密钥后，回复就来自真的模型。密钥只保存在本机后台。',
    'With a DeepSeek URL and key, replies come from the real model. The key is '
        'only stored by the local backend.',
  );
  String get aiBaseUrl => t('接口地址', 'Base URL');
  String get aiModel => t('模型名', 'Model');
  String get aiApiKey => t('API 密钥', 'API key');
  String get aiKeepKey =>
      t('留空 = 保持已保存的密钥', 'Leave blank to keep the saved key');
  String aiSavedKeyHint(String hint) => t('已保存密钥：$hint', 'Saved key: $hint');
  String get aiDeepSeekPreset => t('填入 DeepSeek 预设', 'Fill in DeepSeek preset');
  String get aiDeepSeekPresetHint =>
      t('api.deepseek.com · deepseek-flash', 'api.deepseek.com · deepseek-flash');
  String get aiAsrPreset => t('填入硅基流动预设', 'Fill in SiliconFlow preset');
  String get aiAsrPresetHint => t(
    'api.siliconflow.cn · SenseVoiceSmall',
    'api.siliconflow.cn · SenseVoiceSmall',
  );
  String get aiStatusLine => t('状态', 'Status');
  String get aiStatusHttp => t('已接入 · http', 'Connected · http');
  String get aiStatusOfflineLlm =>
      t('未配置 · 离线模板回复', 'Not configured · offline template replies');
  String get aiStatusUnknown => t('还没读取到状态', 'Status not loaded yet');
  String get aiTestLlm => t('测试连接', 'Test connection');
  String get aiTesting => t('正在测试…', 'Testing…');
  String get aiTestOk => t('连接正常', 'Connection OK');
  String aiTestOkDetail(int latencyMs, String sample) => t(
    '连接正常（${latencyMs}ms）：$sample',
    'Connection OK (${latencyMs}ms): $sample',
  );
  String aiTestFailed(String message) =>
      t('连接失败：$message', 'Connection failed: $message');
  String get aiTestNotConfigured => t(
    '还没配置 HTTP 对话接口，现在是离线模板回复。',
    'No HTTP chat endpoint is configured; replies are offline templates.',
  );
  String get aiClearSection => t('清除这一项', 'Reset this section');
  String get aiNothingToSave => t('没有可以保存的内容。', 'Nothing to save.');
  String get aiSavedAgain => t('已经保存。', 'Saved.');
  String get aiAsrSection => t('语音识别', 'Speech recognition');
  String get aiAsrHint => t(
    '这台电脑默认用本机离线识别。填了下面的云端地址和密钥才会改用云端。',
    'This computer uses on-device offline recognition by default. The cloud '
        'endpoint below is only used when both URL and key are filled in.',
  );
  String get aiAsrEngineWindows => t('本机离线语音', 'On-device offline speech');
  String get aiAsrEngineHttp => t('已接入 · http', 'Connected · http');
  String get aiAsrEngineNone => t('未接入', 'Not connected');
  String get aiAsrEngineFake => t('测试替身（不真实）', 'Test fake (not real)');
  String get aiAsrTestMic => t('测试麦克风识别', 'Test microphone recognition');
  String get aiAsrTesting =>
      t('正在录音，请说一句话…', 'Recording — please say a sentence…');
  String get aiAsrNoSample =>
      t('没有录到声音，请再试一次。', 'No audio was captured. Please try again.');
  String aiAsrTranscript(String text) => t('识别结果：$text', 'Recognised: $text');
  String aiAsrError(String message) =>
      t('识别失败：$message', 'Recognition failed: $message');
  String get aiAsrNotConfigured => t(
    '语音识别还没有接入，先在下面配置，或者改用打字。',
    'Speech recognition is not connected yet. Configure it below, or type instead.',
  );
  String get aiAsrReasonNoSample =>
      t('没有音频样本，无法测试。', 'No audio sample, so nothing can be tested.');
  String get aiAsrReasonInvalidSample =>
      t('音频样本无效，无法测试。', 'The audio sample is invalid.');
  String get aiAsrReasonNotConfigured =>
      t('语音识别还没有接入。', 'Speech recognition is not configured.');
  String get aiMicUnavailable =>
      t('这个设备的麦克风用不了。', 'The microphone is unavailable here.');
  String get aiEngineNone => t('未接入', 'Not connected');
  String get aiLlmNotConfiguredProbe => t(
    '没有配置 HTTP 对话接口（离线模式）。',
    'No HTTP chat endpoint is configured (offline mode).',
  );

  // -- provider states on the Talk screen ----------------------------------
  String get asrNotConnectedTitle =>
      t('语音识别还没有接入', 'Speech recognition is not connected yet');
  String get asrNotConnectedBody => t(
    '现在按麦克风不会录音，也不会显示假的文字。可以先去设置接入，或者改用打字。',
    'The microphone will not record, and no fake transcript is shown. Connect '
        'speech recognition in settings, or type instead.',
  );
  String get micNotConnected => t('语音识别未接入', 'Speech recognition off');
  String get llmOfflineBadge => t('离线模板回复', 'Offline template reply');
  String get providerUnavailableTitle =>
      t('语音服务暂时连不上', 'The speech service is not reachable');
  String get providerUnavailableBody => t(
    '这句话没有被转成文字，也没有回复。可以再试一次，或者改用打字。',
    'That sentence was not transcribed and no reply was given. Try again, or type instead.',
  );

  // -- caregiver ------------------------------------------------------------
  String get caregiverTitle => t('家人这边', 'Family');
  String get caregiverStatus => t('连接状态', 'Connection status');
  String caregiverConnectedTo(String name) =>
      t('已连接：$name', 'Connected to $name');
  String get caregiverPending =>
      t('还在等老人同意。', 'Waiting for the older adult to approve.');
  String get caregiverNotLinked => t(
    '还没有连接。请让家人给你一个邀请码。',
    'Not connected yet. Ask your family member for an invite code.',
  );
  String get caregiverPrivacy => t(
    '你只能看到老人同意分享的内容，看不到聊天记录。',
    'You only see what the older adult agreed to share. Conversations stay private.',
  );
  String get caregiverDigest => t('本周简报', 'Weekly update');
  String get caregiverDigestTitle => t('本周简报', 'This week at a glance');
  String get caregiverCallCheckin => t('打个电话问候', 'Call to check in');
  String get caregiverNoDigest =>
      t('本周还没有可以看的简报。', 'No update available this week.');
  String get caregiverDigestUnavailable =>
      t('简报服务还没接通。', 'The update service is not connected yet.');
  String get caregiverInsufficient => t(
    '这周的信息还不够，先不下结论。',
    'Not enough information this week, so no conclusions.',
  );
  String get caregiverPrefs => t('提议问候时间', 'Propose a check-in schedule');
  String get caregiverInvite => t('输入邀请码', 'Enter invite code');
  String get caregiverAccept => t('接受邀请', 'Accept invitation');
  String get caregiverAccepted => t(
    '邀请已接受。等老人同意后，连接就完成了。',
    'Invitation accepted. The link is complete once the older adult approves.',
  );
  String get caregiverInvalid =>
      t('这个邀请码不能用了。', 'This invite code is no longer valid.');
  String get caregiverProposeSent =>
      t('建议已经送给老人了。', 'Suggestion sent to the older adult.');
  String get caregiverProposeFailed => t('没送出去。', 'Could not send.');
  String get caregiverMyProposals => t('我的建议', 'My suggestions');
  String get caregiverNoProposals => t('还没有提过建议。', 'No suggestions yet.');
  String get caregiverProposeHint => t(
    '你只能建议问候时间和暂停，老人同意后才生效。',
    'You can suggest a greeting window and a pause. They only apply after the older adult agrees.',
  );
  String get caregiverNoDigestContact =>
      t('暂时没有可拨打的号码。', 'No phone number available right now.');
  String get proposalPending => t('等待老人决定', 'Waiting for a decision');
  String get proposalApproved => t('老人已同意', 'Approved');
  String get proposalRejected => t('已取消', 'Cancelled');
  String get caregiverSettingsOnly =>
      t('设置只给老人用。', 'Settings belong to the older adult.');

  // -- shared labels --------------------------------------------------------
  String get today => t('今天', 'Today');
  String get tomorrow => t('明天', 'Tomorrow');
  String topicsShareTitle(String topic) => topic;
  String topicLabel(String topic) => switch (topic) {
    'participation' => t('聊天参与', 'Taking part in chats'),
    'activities' => t('活动喜好', 'Activities you enjoy'),
    'mood' => t('心情', 'Mood'),
    'meals' => t('吃饭', 'Meals'),
    'wellbeing' => t('日常状态', 'General wellbeing'),
    _ => topic,
  };

  /// User-facing explanation for a structured API error (SPEC §6 codes).
  String errorText(ApiException error) => switch (error.code) {
    'offline' => offlineTitle,
    'unauthorized' => t(
      '登录过期了，请重新进入。',
      'Your sign-in expired. Please enter again.',
    ),
    'forbidden' => t('这件事现在做不了。', 'That is not allowed right now.'),
    'caregiver_scope_denied' => t(
      '聊天内容对家人是不可见的。',
      'Conversations stay private from family.',
    ),
    'relationship_inactive' => t(
      '和家人的连接还没有生效。',
      'The family connection is not active.',
    ),
    'consent_required' => t(
      '还差一个同意，请先在设置里打开。',
      'A permission is missing. Please turn it on in settings.',
    ),
    'consent_version_conflict' => t(
      '权限刚刚改过，请刷新后再改。',
      'Permissions changed. Refresh and try again.',
    ),
    'not_found' => t('没找到这项内容。', 'That was not found.'),
    'validation_error' => t('这一项填得不太对。', 'That value does not look right.'),
    'conflict' => t('现在有另一个进行中的操作。', 'Another action is in progress.'),
    'daily_cap_reached' => t('今天已经问候过了。', 'Today’s check-in already happened.'),
    'outside_greeting_window' => t(
      '现在不在问候时间里。',
      'It is outside the greeting window.',
    ),
    'quiet_hours' => t('现在是安静时间。', 'It is quiet time now.'),
    'not_designated_device' => t(
      '这台设备不是用来问候的那台。',
      'This is not the check-in device.',
    ),
    'session_stopped' => sessionStopped,
    'provider_unavailable' => t(
      '语音服务暂时连不上，可以打字。',
      'The speech service is unavailable. You can type instead.',
    ),
    'insufficient_information' => t(
      '信息还不够，先不下结论。',
      'Not enough information, so no conclusions.',
    ),
    'invitation_invalid' => caregiverInvalid,
    _ => unknownError,
  };
}
