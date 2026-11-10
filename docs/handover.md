# Anchor 交接说明：电脑端给老人、手机端给家人

> 架构调整日期：2026-11-10（同日完成老人端整体 UI 重做）
> 本文覆盖：Windows / Android 两端形态拆分（语音只在电脑，设置只在手机）+ 手机端 setup 首页 + 老人端新界面
> 代码状态：`mobile/lib`、`mobile/test` 内已完成并已提交推送；`flutter analyze` 无问题，`flutter test` **286 个测试全绿**，后端 `pytest` **399 全绿**。Windows 包已在本机装机验证；**Android APK 只验证了「能构建 + 清单权限正确」，没有真机装过。**
> 交接对象：接下来做「周报 / 家人提醒」的同学。**第 5 节是给这份工作的任务说明书（生成 → 排版 → 子女端查收 → 演示样例）**。

---

## 0. 2026-11-10 当天改了什么（按提交顺序）

| 提交 | 内容 |
|---|---|
| `62d65f8` | 游戏里可以「说出答案」（录音 → `/transcribe` → 匹配选项 → 与点击同样判分）；ASR 默认模型换成 `Qwen/Qwen3-ASR-1.7B`（同一音频实测 0.52–0.65 s；原 SenseVoice 2.9 s，且出现过 15–43 s 尖峰） |
| `7aa5f44` | 语音输出不再静默失败：长连接播放器回退为「一句话一个短命子进程」，校验播放器退出码（非 0 → 自动用系统语音兜底并记日志），客户端超时 15 s → 90 s，启动清理残留 mp3 |
| `57cbd0d` | 活动进聊天流（第 3 句后自然出现，答完接着聊）；答对 +1 朵小花（只加不减、`GET /rewards`）；停止立即生效；后端冻结版监听 `0.0.0.0:8077`；Android 神经语音（just_audio） |
| `31f5bcc` | 产品形态拆分：`PlatformPolicy` 唯一平台判断；Windows 无任何设置入口；手机登录即 setup 首页；`AppState` 七个语音入口在手机端直接返回 |
| `8808ce9` | 老人端首页去掉「玩一玩」入口（活动已在对话里）；停止条只在「有东西在跑」时出现，按停止后立即消失 |
| 本文提交 | 交接文档更新（设计说明、限制、文件清单） |

老人端界面这一天的重做见 `docs/design/senior-ui.md`：登录页（两张大牌：老人 / 家人）、首页（一个大圆盘 + 打电话）、聊天页（紧凑字幕 + 固定底部麦克风，停止条只在该出现时出现）。

---

## 1. 这套产品的形态

一句话：**一台电脑 + 一台手机，各做一件事。**

| | 老人用的电脑（Windows） | 家人用的手机（Android） |
|---|---|---|
| 定位 | 老人身边的「终端」 | 家人的「配置与联络端」 |
| 首页 | **一个大圆圈「聊一聊」+ 一个「打电话」**（2026-11-10 重做：不再有三等分入口，也没有「玩一玩」入口） | 设置与联络（AI 接入、家人与联系、消息与操作记录） |
| 能做的事 | 语音聊天、聊天里随机出现的小活动（答对攒小花）、给家人打电话、聊天中可停止 | 配置对话模型与语音识别、邀请/接受家人、看周报、建议问候时间；老人账号还能看自己的设置 |
| 明确没有 | **任何设置界面**；也**没有「玩一玩」独立入口**（活动只在对话里出现） | **任何语音交互**：没有麦克风按钮、不朗读回复、没有语音答题、也没有「停止」 |

**停止按钮的唯一规则（2026-11-10 定稿）**：只在「有东西在跑」的地方出现——也就是聊天页。首页没有停止条；聊天页按下停止后，停止条**立即消失**，屏幕上只剩「已经停下来了」面板与「继续聊天」。这偏离了 SPEC §9「每个老人页面都有 Stop」的字面要求，是产品明确选择：老人抱怨「按了停止它还赖在那里」。

老人端观感在 2026-11-10 整体重做，设计说明与 token 见 `docs/design/senior-ui.md`（暖石纸底、玉青主轴、单一大圆盘、紧凑字幕、发丝线分隔）。正文仍是 26px、可点区域 ≥56px，1.3 倍字号在手机上不溢出（有测试钉住）。

代码层面的三条硬规则（都已有测试盯着）：

1. 电脑端的 `SettingsScreen` / `AiProvidersScreen` **打不开**：首页没有入口，就算有人手搓路由或深链恢复，这两个页面自己会渲染 `ClosedOnDevice` 并在下一帧退回首页。
2. 手机端**没有任何对话入口**：登录后无论老人还是家人账号，一律进 setup 首页；页面上没有聊一聊/玩一玩/打电话/停止。
3. 手机端的语音调用全部是空操作：`AppState` 里每个麦克风/扬声器入口先过 `_voiceBlocked()`，返回前只打一行日志。误触、旧路由恢复、后台主动问候都开不了麦。

---

## 2. 为什么这样分

1. **老人不该看到配置项。** base URL、模型名、API Key 是给愿意折腾的人看的。老人看到只会困惑；而一旦误改，整条语音链路就断了。
2. **配置是一次性的，聊天是每天发生的。** 家人头一天把 AI 接好、把家人和问候时间设好，之后就不用再碰。老人那端只保留每天要按的四个大按钮。
3. **语音必须跟着麦克风和扬声器走。** 这套 demo 的 ASR 在电脑上（本机 System.Speech 或云端），TTS 也是电脑上调的神经语音。手机既不该开麦也不该出声，否则一次误触就把手机变成监听器。

---

## 3. 代码在哪：平台策略只有一处

新增 `mobile/lib/platform_policy.dart`：

```dart
class PlatformPolicy {
  const PlatformPolicy({required this.seniorAppliance});
  const PlatformPolicy.seniorAppliance();   // Windows：老人终端
  const PlatformPolicy.setupApp();          // Android：家人配置端
  factory PlatformPolicy.fromPlatform();    // Platform.isWindows
  final bool seniorAppliance;
  bool get setupApp => !seniorAppliance;    // 永远互补
  static PlatformPolicy instance = PlatformPolicy.fromPlatform();
}
```

`AppState` 持有一个 `policy`（不传就用 `PlatformPolicy.instance`，即真实平台），所有界面从 `state.policy` 读。**界面和状态层不再自己判断 `Platform.isWindows`**；语音服务内部原有的平台判断保持原样没动（`speaker_factory_io.dart` 用 `Platform.operatingSystem` 选实现，`backend_bootstrapper_io.dart` 只在 Windows 端起本地后端——那是「这台机器上哪种实现存在」，不是「这是哪个产品」）。

| 位置 | 作用 |
|---|---|
| `lib/platform_policy.dart` | 唯一的平台判断 |
| `lib/state/app_state.dart` | 持有 `policy`；**语音开关**（见下） |
| `lib/app.dart` `RootScreen` | 登录后分流：手机 → `SetupHomeScreen`；电脑 → 老人 `SeniorHomeScreen` / 家人 `CaregiverHomeScreen` |
| `lib/screens/setup/setup_home_screen.dart` | 手机首页（AI 接入 / 家人与联系 / 消息与操作记录 / 「这台手机只负责设置」卡片） |
| `lib/screens/senior/home_screen.dart` | 电脑首页：设置入口只在 `setupApp` 时渲染（即电脑上不渲染） |
| `lib/screens/senior/settings_screen.dart`、`ai_providers_screen.dart` | 开头硬兜底：非 `setupApp` 直接回首页 |
| `lib/widgets/closed_on_device.dart` | 「这台电脑上没有设置」+ 退回首页 |
| `lib/widgets/anchor_scaffold.dart` | 手机端不渲染 StopBar（没有语音可停） |
| `lib/screens/senior/talk_screen.dart` | 「去设置」动作只在手机端出现；电脑端文案改成「在家人的手机上打开」 |

**语音开关的确切位置**：`mobile/lib/state/app_state.dart`

```dart
bool get voiceAllowed => !policy.setupApp;            // 电脑 true，手机 false
bool _voiceBlocked(String what) { ... debugPrint(...); return true; }  // 手机直接返回
```

加在 7 个入口的第一行：

- `startRecording()` → 返回 `false`（**测试断言：`FakeMicrophoneInput.startCalls == 0`**）
- `stopRecordingAndSend()`、`cancelRecording()`
- `captureProbeClip()`（AI 接入页的识别测试用）
- `listenForAnswer()`（玩一玩的语音答题）
- `_speak()`（所有朗读的唯一出口：回复、问候、活动反馈、再说一遍）
- `stopAll()` 里的 `microphone.cancel()` / `speaker.stop()`

另外 `refresh()` 里 `invitations.start()` 也只在 `voiceAllowed` 时执行——主动问候属于会说话的那台设备，手机不去抢当天那一次。

测试注入方式：`buildTestState(api, policy: const PlatformPolicy.setupApp())`。不传时**默认按 Windows 终端**，这样 CI 机器是 Linux 时整套测试行为不会漂移。

---

## 4. 两个端怎么连

- **同一局域网**：同一个 Wi-Fi / 交换机。访客网络一般做了客户端隔离，别用。
- **后端跑在电脑上**：`anchor_backend.exe`，打包后在 `AnchorDemo\backend\anchor_backend.exe`（App 会自动拉起 `<anchor_app.exe 所在目录>\backend\anchor_backend.exe`）。冻结版**默认监听 `0.0.0.0:8077`**（`backend/app/entrypoint.py`：frozen → `0.0.0.0`，可用 `ANCHOR_HOST` 覆盖）。
  - 开发时用 `scripts/run_backend.ps1` 跑的是 `uvicorn --host 127.0.0.1`，**手机连不上**。要在局域网里给手机用，必须 `ANCHOR_HOST=0.0.0.0`（或手动 `--host 0.0.0.0`）。
- **APK 里的地址是编译期写死的**：`mobile/lib/config.dart` 的 `AnchorConfig.apiBase` 来自 `--dart-define=ANCHOR_API_BASE`，默认 `http://127.0.0.1:8077`——在手机上等于指向手机自己，没用。**改地址 = 重新打包**：

```powershell
# 0) 查电脑的局域网地址：取 Wi-Fi 适配器的 IPv4，例如 192.168.1.100
ipconfig

# 1) 放行 8077（管理员 PowerShell，只需一次）
New-NetFirewallRule -DisplayName "Anchor backend 8077" -Direction Inbound -Protocol TCP -LocalPort 8077 -Action Allow

# 2) 重打包。仓库路径含非 ASCII 字符，必须走 ASCII 镜像
cd anchor
. .\scripts\_common.ps1
Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://192.168.1.100:8077
#    产物：build\app\outputs\flutter-apk\app-debug.apk

# 3) 装机（手机开 USB 调试）
flutter install --debug --dart-define=ANCHOR_API_BASE=http://192.168.1.100:8077
```

- **先验证通不通**：在手机浏览器打开 `http://192.168.1.100:8077/api/v1/health`，能看到 JSON 就说明网络 + 防火墙 OK，再开 App。
- **电脑端不用改**：它连 `http://127.0.0.1:8077`（默认值）并自己拉起同目录的后端。
- 手机和电脑必须连**同一个**后端；两端的账号仍是演示账号（1 = 林秀兰，2 = Mei），见第 6 节第 2 条。

### 自测命令（改完代码先跑这个）

```powershell
cd anchor
. .\scripts\_common.ps1
Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter analyze     # 期望：No issues found!
flutter test        # 期望：276 tests, All tests passed!
```

---

## 5. 周报（weekly report）——**接手同学的主任务**

> 一句话：**让家人每周在手机上收到一份「够详实、排得好、能直接拿去 presentation」的周报。**

这一段是工作说明书，不是背景介绍。做完这四件事，这一块就算交付。

### 5.1 你要交付的四件东西（缺一不算完成）

| # | 交付物 | 完成的样子 |
|---|---|---|
| 1 | **周报生成（主责）** | 内容足够详实：这一周发生了什么、聊过哪些主题、参加了什么活动、情绪与社交线索、家人可以从哪里关心。不是现在的最多 3 句摘要 |
| 2 | **排版** | 子女端能扫读的版式：周期标题 → 一句话概览 → 分主题小节 → 证据可展开 → 底部「打个电话」 |
| 3 | **子女端查收** | 家人手机收到「本周简报」提醒（未读角标）→ 列表 → 详情 → 标已读，全链路可点通 |
| 4 | **presentation 用的一份 example** | 一份预置数据 + 生成好的那份周报（能当场打开的种子数据或截图）+ 30 秒讲解要点 |

### 5.2 内容要求：详实，但不越界

一份周报至少要有下面这些**分主题段落**，每段都要有具体事实，不要写"总体不错"这种空话：

1. **这一周的一句话概览**：例如「这周聊了 4 次，参加了 2 个小活动，提到最多的是老家的院子和孙子」。
2. **聊过的话题**：从 `observations` 里按主题归并（饮食/家人/活动/心情/睡眠/身体感受…），每段 1–3 句，写"她说了什么"，不要写"她很好"。
3. **参与情况**：哪天聊了、玩了什么活动、答对了几题（对应小花），是主动打开还是被问候拉进来的。
4. **情绪与社交线索**：出现过的情绪词、提到的人；**只陈述，不判断**——可以写"提到阿毛（孙子）时说了三次"，不能写"情绪低落"。
5. **家人可以怎么关心**：2–3 条具体、轻量的建议（"下次可以问问院子里的花"），不要建议就医、吃药、报警。
6. **数据不足时如实说**：素材不够就写"这周聊得少，只说了一件小事"，绝不凑数、不编造（现有 `baseline.adequate_data()` 已有这个判断，保留）。

**红线**：不写诊断、不写评分、不写"认知水平/记忆力"；不引用老人的原话超过必要长度；不出现其他家庭的任何信息；每条事实要能在 `evidence_ids` 里找到来源。

### 5.3 排版要求

- 载体是**手机上的家人端**（`SetupHomeScreen` → 家人与联系 → 本周简报），竖屏、字号不小于 16、单列。
- 结构固定：`周期（2026-11-03 ~ 11-09）` → 一句话概览（大字）→ 分主题小节（标题 + 2–3 句）→「这一周的记录」可展开的证据列表 → 底部主按钮「打个电话问候」。
- 空态/不足态要有话说（"这周信息还不够，等下周再看看"），不要显示空白页。
- 复用现有主题（`mobile/lib/theme.dart` 的 paper/jade/ink），不要引入新配色体系。

### 5.4 子女端查收（现在缺的部分）

现状：`digests` 与 `notifications` 表都有数据，接口也有；**手机端没有对应界面**，家人只能靠开发者工具调接口。

要补的最小闭环：

1. setup 首页显示未读角标（`GET /api/v1/notifications`，`kind='digest_ready'`）。
2. 点开进入「本周简报」列表（`GET /api/v1/digests`，家人只拿到 `approved`/`delivered`）。
3. 详情页渲染 5.3 的排版；点「已读」写 `PATCH /api/v1/notifications/{id}`。
4. 没有 FCM/APNs 的前提下，用前台轮询即可（每 60 s），不要假装有推送。

### 5.5 presentation 用的 example（明确交付）

- 一份**可重复生成**的种子：`scripts/seed_demo.py` 现在会生成上一周的周报，请在它基础上补一份"素材丰富的一周"（至少 4 天对话、2 个活动、3 个主题、1 条提到家人的记录）。
- 一份**已经生成好的周报正文**（Markdown 或截图），放在 `docs/digest-example.md`，用来直接在投影上讲。
- 一段 **30 秒讲解**：这周她聊了什么 → 系统怎么归并 → 家人看到什么 → 为什么这样对老人和家人都好。

### 5.6 现有链路（直接用，不要重写）

1. **素材**：`observations` 表（保留 35 天，`retention_purge` 清理）。只有老人开了 `record_observations` 且主题在 `share_topic` 里才读。
2. **组装**：`backend/app/digests/service.py` → `ensure_weekly_digest(senior_id, period_start, period_end)`
   - 幂等：同 `(senior_id, period_start)` 已存在直接返回；
   - `_build()`：同意关 / 无可分享主题 / `baseline.adequate_data()` 不够 → `insufficient_data` + 空 items（不凑数）；
   - 否则 `baseline.select_candidates()` → `render.render_items()`，语言跟随老人 `locale`。
3. **存储**：`digests` 表一人一周一行，`UNIQUE(senior_id, period_start)`；状态 `draft → awaiting_senior_approval → approved → delivered`，另有 `cancelled` / `insufficient_data`；正文在 `items_json`，另记 `consent_version`。
4. **家人可见**：`GET /digests` 对家人只返回 `approved`/`delivered`，每条 item 再按当前关系与 `share_topic` 过滤（`_filter_items`）；原始 observation 永不下发。

### 5.7 接口（以代码为准）

⚠️ 任务描述里的 `POST /api/v1/digests` **不存在**。

| 方法 | 路径 | 谁能调 | 说明 |
|---|---|---|---|
| GET | `/api/v1/digests` | 登录用户 | 老人：全部状态；家人：仅 approved/delivered；无数据时 `{"items":[],"note":"insufficient_information"}` |
| GET | `/api/v1/digests/{id}` | 登录用户 | 单条；家人读未批准 → 403 |
| PATCH | `/api/v1/digests/{id}` | 仅老人 | 改说法 → `awaiting_senior_approval`，并取消未投递的通知 |
| POST | `/api/v1/digests/{id}/approve` | 仅老人 | 批准 → 入队 `notify_digest` |
| GET / PATCH | `/api/v1/notifications[/{id}]` | 登录用户 | 家人提醒与已读 |

**要补的生成入口**：周报由 worker 定时生成（`jobs.py::enqueue_due_jobs` → `JobRunner._weekly_digest`），没有"立刻生成"接口。若要在演示时补生成，加一个受控入口（仅老人、幂等、写审计），不要用脚本直接改库。

### 5.8 验收标准（可执行）

1. `flutter analyze` 无问题、`flutter test` 全绿；`pytest backend/tests -q` 全绿（当前 286 / 399）。
2. 同一 `(senior, period)` 跑两遍 worker 只出 1 行 digest、1 条通知（`backend/tests/test_digests.py` 已有）。
3. 家人端：未读角标 → 列表 → 详情 → 已读，全链路手工点通一遍（截图留证）。
4. 周报正文满足 5.2 的六段结构与红线；`language_guard.py` 仍拦截诊断/评分措辞。
5. 撤销分享后再拉取，已批准的 item 也会被过滤掉（现有测试覆盖，改渲染不能破坏它）。
6. `docs/digest-example.md` 里的示例与种子脚本一致，可以现场复现。

### 5.9 红线（写在这里免得返工）

- 不新增真实老人数据；示例全部是合成数据。
- 不在周报里出现原始对话全文、音频、其他家庭、供应商 key。
- 不做医疗建议、不评估认知、不做排名。
- 不为了让演示好看而伪造"数据充分"，不足就如实显示不足。

最小复现命令（在 `anchor/` 下）：

```powershell
. .\scripts\_common.ps1
scripts\run_worker.ps1 -Once        # 入队并跑一遍：上周的周报 + 保留期清理
# 用老人身份换 token：POST /api/v1/dev/login {"user_id":1}
curl.exe -H "Authorization: Bearer <senior-token>" http://127.0.0.1:8077/api/v1/digests
```

---

## 6. 已知限制（演示前必须知道）

1. **没有 TLS**：全程明文 HTTP，同一 Wi-Fi 上抓包就能看到内容和 token。只在可信局域网演示。
2. **登录是 dev 登录**：`POST /api/v1/dev/login` 直接传 user id（1 = 老人，2 = 家人），没有密码。生产前必须换掉（`ANCHOR_ENV=production` + 真 `ANCHOR_SECRET`）。
3. **防火墙要放行 8077**（命令见第 4 节），访客 Wi-Fi 通常做了隔离。
4. **APK 是 debug 签名**（`flutter build apk --debug`）：体积大（150 MiB 量级）、启动慢，不是发布包。
5. **APK 里仍声明 `RECORD_AUDIO`**：这个权限是 `record` 插件自己的 manifest 带进来的。手机端代码已经全部不走录音（第 3 节），但「安装包里有这个权限」在隐私说明里要主动讲；要彻底去掉得把录音插件从 Android 构建里拆开（本次没做）。
6. **两台设备共用同一个 device id**：`AnchorConfig.deviceId` 目前写死 `anchor-win-demo-1`，手机和电脑报给后端的是同一个值，「一台设备接收问候」的规则分不出这两台。要做真双端演示，应改成编译期参数（`--dart-define=ANCHOR_DEVICE_ID`）并给两台机器不同的值。
7. **老人电脑上撤销「语音在云端处理」后，电脑端改不回来**：电脑没有设置页，Talk 的提示已改成「在家人的手机上打开」，但真要恢复必须去手机（老人账号 → 设置与设备）。这是个产品决策点：建议后续让「语音同意」也能在手机端由老人自己确认。
8. **文案一致性**：`scripts/package_windows.ps1` 生成的 `README-DEMO.txt` 已在 2026-11-10 更新为「电脑上没有设置界面，配置在家人手机上」；`mobile/README-android.md` 的「Android 语音路径」整节写的是 11-10 之前的设计（手机已不做语音），读到时以本文为准。
9. **没有真机验证**：本机没有 Android 设备/模拟器，手机端只经过 widget 测试和静态分析，没有在真机上点过一遍（连不上后端、防火墙、字体渲染都未验证）。
10. **「玩一玩」独立页面仍在代码里，但已无入口**：`activity_screen.dart` 保留（判分规则与测试都在里面，Play 的判分逻辑和聊天内卡片共用 `state/activity_grading.dart`），首页不再有它的入口；如果后续确认不需要，可以整页删除并迁移相关测试。
11. **家人账号不能改 AI 配置**：后端 `/providers` 是 `require_senior`，家人账号在手机上点「AI 接入」会看到「由老人管理」。演示时用老人账号（1）登录手机配置即可；要放开需要改后端授权（产品决策）。
12. **ASR 供应商延迟会抖**：SiliconFlow 的 Qwen3-ASR 平时 0.5–0.9 s，但同一网络下曾出现 15–43 s 的尖峰（同一音频不同时刻）。适配器超时 20 s，超时就 503。演示前建议现场先用手机/电脑跑一次识别，确认当时的速度。
13. **TTS 走微软 Edge 的公共接口**：无 SLA，限流或改协议时会退回 Windows 系统语音（机械音，但有声）。每次合成 3–7 s，说完到出声之间有这段等待。
14. **格式检查**：`dart format --set-exit-if-changed` 在 `mobile/lib/services/android_tts_speaker.dart`、`mobile/test/android_tts_speaker_test.dart` 两个历史文件上仍报格式差异，所以 `scripts/verify.ps1` 的格式步骤会因此报红——与本轮改动无关，`flutter analyze` 与全部测试是绿的。

---

## 7. 本次改动的文件清单

**设计文档**

| 文件 | 内容 |
|---|---|
| `docs/design/senior-ui.md` | 老人端重设计的 token、版面、动效与边界说明 |
| `docs/handover.md` | 本文 |

**新增（平台拆分 + 活动进聊天 + 奖励 + Android 语音）**

| 文件 | 内容 |
|---|---|
| `mobile/lib/platform_policy.dart` | 平台策略（唯一判断点） |
| `mobile/lib/screens/setup/setup_home_screen.dart` | 手机端 setup 首页 |
| `mobile/lib/widgets/closed_on_device.dart` | 不可用页面 → 退回首页 |
| `mobile/lib/state/inline_activity.dart` | 聊天内活动卡的状态 |
| `mobile/lib/state/activity_grading.dart` | 判分规则（Play 与聊天内共用） |
| `mobile/lib/widgets/inline_activity_card.dart` | 聊天内活动卡（含小花展示） |
| `mobile/lib/services/android_tts_speaker.dart` | Android 神经语音（just_audio，手机端已不启用） |
| `mobile/lib/services/answer_matcher.dart` | 语音答案 → 选项匹配（不猜） |
| `backend/migrations/003_inline_activities.sql` | 会话内活动发放记录 |
| `backend/migrations/004_activity_rewards.sql` | 小花计数 |
| `backend/app/api/asr.py` | `POST /api/v1/transcribe`（只转写，不建会话/不调模型） |
| `backend/tests/test_inline_activities.py`、`test_activity_rewards.py`、`test_asr_api.py` | 对应测试 |
| `mobile/test/*`（新增 7 个测试文件） | 平台拆分、聊天内活动、语音答题、奖励、Talk 版面等 |

**修改（主要项）**

| 文件 | 改了什么 |
|---|---|
| `mobile/lib/theme.dart` | 新调色板与圆角/尺寸 token；保留旧 token 名以免牵连其他页面 |
| `mobile/lib/screens/login_screen.dart` | 两张大牌的账号选择页 |
| `mobile/lib/screens/senior/home_screen.dart` | 大圆盘首页；去掉设置入口与「玩一玩」；不再渲染停止条 |
| `mobile/lib/screens/senior/talk_screen.dart` | 紧凑字幕流 + 固定底部麦克风；停止后隐藏停止条 |
| `mobile/lib/widgets/stop_bar.dart` | 常驻条改为紧凑贴条；抗大字号裁切 |
| `mobile/lib/widgets/anchor_scaffold.dart` | 新增 `aboveStop` 与 `showStop` |
| `mobile/lib/state/app_state.dart` | 平台策略、语音闸门、聊天内活动、小花、停止立即生效 |
| `mobile/lib/app.dart` | `RootScreen` 按平台分流 |
| `mobile/lib/services/backend_tts_speaker.dart` | 回退为单句短命播放进程 + 退出码校验 + 残留清理 |
| `mobile/lib/services/api_client.dart` | `/transcribe`、`/rewards`、活动会话带 `correct` |
| `backend/app/activities/engine.py` | 活动发放、判分后的花朵计数 |
| `backend/app/api/activities.py` | `correct` 字段（StrictBool）、`GET /rewards` |
| `backend/app/conversation/orchestrator.py` | 回合响应可带 `activity` |
| `backend/app/entrypoint.py` | 冻结版监听 `0.0.0.0`，开发版仍 `127.0.0.1` |
| `scripts/package_windows.ps1` | 打包 README 改为「配置在家人手机上」 |
| `content/activities.json` | 16 条成人向内容（5 题 / 4 故事 / 7 回忆） |
| 测试：`home_widget_test`、`activity_screen_test`、`activity_voice_test`、`platform_split_test`、`backend_startup_test`、`fakes.dart` | 按新首页与新停止规则更新 |
