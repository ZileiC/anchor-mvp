# Anchor 交接说明：电脑端给老人、手机端给家人

> 架构调整日期：2026-11-10
> 本文覆盖：Windows / Android 两端形态拆分（语音只在电脑，设置只在手机）+ 手机端 setup 首页
> 代码状态：`mobile/lib`、`mobile/test` 内已完成；`flutter analyze` 无问题，`flutter test` **276 个测试全绿**（原有 263 + 新增 13）。**未提交、未打包、未在真机上验证。**
> 交接对象：接下来做「周报 / 家人提醒」的同学（重点看第 5 节）。

---

## 1. 这套产品的形态

一句话：**一台电脑 + 一台手机，各做一件事。**

| | 老人用的电脑（Windows） | 家人用的手机（Android） |
|---|---|---|
| 定位 | 老人身边的「终端」 | 家人的「配置与联络端」 |
| 首页 | 聊一聊 / 玩一玩 / 打电话 + 一直存在的「停止」 | 设置与联络（AI 接入、家人与联系、消息与操作记录） |
| 能做的事 | 语音聊天、小活动（含小花）、给家人打电话、随时停止 | 配置对话模型与语音识别、邀请/接受家人、看周报、建议问候时间；老人账号还能看自己的设置 |
| 明确没有 | **任何设置界面**：没有设置入口、没有 AI 接入页、没有填 Key 的地方 | **任何语音交互**：没有麦克风按钮、不朗读回复、没有语音答题、也没有「停止」 |

两端的观感都没变：正文 26px、可点区域 ≥56px、字号放大到 1.6 倍不溢出。

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

## 5. 周报（digests）——留给接手的同学

### 5.1 数据从哪来

1. **素材**：`observations` 表（对话 / 活动产生的观察，保留 35 天，由 `retention_purge` 清理）。只有老人开了 `record_observations` 且某些 `share_topic` 也同意的主题才会被读。
2. **组装**：`backend/app/digests/service.py` → `DigestService.ensure_weekly_digest(senior_id, period_start, period_end)`
   - 先查 `digests` 表同 `(senior_id, period_start)` 是否存在，存在就直接返回（幂等）。
   - `_build()`：`record_observations` 关 / 没有任何可分享主题 / `baseline.adequate_data()` 判断数据不够 → 状态 `insufficient_data`、`items` 为空（宁可不写，不凑数）。
   - 否则 `baseline.select_candidates()` 选素材 → `render.render_items()` 生成**最多 3 条** `{topic, text, evidence_ids:[...]}`，语言跟随老人 `locale`。
3. **存储**：`digests` 表一人一周一行，`UNIQUE(senior_id, period_start)`；状态机 `draft → awaiting_senior_approval → approved → delivered`，另有 `cancelled`、`insufficient_data`；正文在 `items_json`，另记 `consent_version`（批准时的同意版本）。
4. **家人能看的**：`GET /digests` 对家人只返回 `approved`/`delivered`，而且每条 item 会按**当前**关系和 `share_topic` 再过滤一遍（`_filter_items`）——撤销分享后，已批准的行也会被重新过滤。原始 observation 永不下发。

### 5.2 接口（以代码为准）

⚠️ 任务描述里的 `POST /api/v1/digests` **不存在**。现在的 surface 是：

| 方法 | 路径 | 谁能调 | 说明 |
|---|---|---|---|
| GET | `/api/v1/digests` | 任何登录用户 | 老人：自己全部状态；家人：只 approved/delivered。返回 `{"items":[...]}`，家人无数据时 `{"items":[],"note":"insufficient_information"}` |
| GET | `/api/v1/digests/{id}` | 任何登录用户 | 单条；家人读未批准 → 403 |
| PATCH | `/api/v1/digests/{id}` | **仅老人**（`require_senior`） | 改说法：items 写入 → `awaiting_senior_approval`，并取消未投递的 `notify_digest` |
| POST | `/api/v1/digests/{id}/approve` | **仅老人** | 同意 → `approved`，入队一条 `notify_digest` |

通知（家人提醒的数据源）：`GET /api/v1/notifications`、`PATCH /api/v1/notifications/{id}`（标已读）。

### 5.3 生成入口现在在哪里

1. `backend/app/jobs.py` → `enqueue_due_jobs(ctx)`：对每个老人按他的时区算「上一个 ISO 周」和「本周一 09:00」（`WEEKLY_DIGEST_HOUR = 9`）。到点入队 `weekly_digest`，幂等键 `weekly_digest:{senior_id}:{period_start}`；同时入队当天的 `retention_purge`。
2. `JobRunner._weekly_digest` → `DigestService.ensure_weekly_digest(...)`（重复跑不会多出行）。
3. 老人 `approve` → 入队 `notify_digest` → `DigestService.deliver(digest_id)`：再检查状态 / 关系 / 同意，写一行 `notifications(kind='digest_ready')`（通用文案，不含周报正文），digest 置 `delivered`。
4. **运行方式**：`scripts/run_worker.ps1`（常驻，默认 60s 一轮）或 `scripts/run_worker.ps1 -Once`（= `python -m app.worker --once`，演示/冒烟）。演示数据用 `scripts/seed_demo.py`（它会顺手生成上一周的周报）。
5. worker 必须**单实例**：SQLite + `jobs` 表的租约（`ANCHOR_JOB_LEASE_SECONDS`）保护，多实例同库会互相抢租约。

### 5.4 手机端现在能看到什么

- **setup 首页**「消息与操作记录」卡片（`lib/screens/setup/setup_home_screen.dart`）：
  - `setup-records-digest`：一行状态（还没有生成 / 等老人同意后才会发出 / 已经同意，家人可以看了 / 这周的信息还不够）
  - `setup-records-note`：一句「谁改过设置、谁打过电话，电脑端都有记录；手机上的查看界面还没做」
- **家人屏幕**：hub → 家人与联系 → 本周简报（`DigestScreen`）读 `GET /digests`，只显示已批准/已投递的，可「打个电话问候」。
- **老人账号**：hub → 设置与设备 → `SettingsScreen` 的「给家人的简报」区，可以改说法、同意发给家人（这是现有审批 UI）。

### 5.5 还缺什么（按优先级）

1. **家人端提醒（最缺）**：`notifications` 表有数据、接口也有，但手机 `ApiClient` 没有对应方法，也没有列表或未读角标。最小闭环：hub 显示未读数 → 点开看到 `digest_ready` → 进 `DigestScreen`。
2. **真推送**：没有 FCM / APNs，也没有本地通知插件（`docs/limitations.md` 第 6 条同样适用）。现在的提醒只能靠 App 前台轮询，App 不在前台就收不到。
3. **审批流 UI 细节**：老人端 PATCH→approve 的先后、按钮禁用态、`insufficient_data` 空态、批准后重新拉取（现在 `AppState.digests` 是本地替换，没有重新 GET）；setup hub 的状态行也应在批准后就地刷新。
4. **手机端「立刻生成」**：没有生成接口，worker 之外没法补生成。要做得后端加一个受控入口（仅老人 + 幂等 + 审计），本次约定不动 `backend/`。
5. **家人账号改不了 AI 接入**：`GET/PUT /providers` 都是 `require_senior`，家人点进 AI 接入会看到「由老人管理」。演示时用**老人身份**登录手机即可配置；要真的让家人配，这是后端权限问题（本次不动 `backend/`）。

### 5.6 验收标准（可执行）

1. `flutter analyze` 无问题；`flutter test` 全绿（当前 276）。
2. 手机端（`PlatformPolicy.setupApp`）：hub 上没有「聊一聊/玩一玩/打电话/停止」，有 `setup-ai`、`setup-device-note`、`setup-records-digest` —— `test/platform_split_test.dart` 已覆盖。
3. 电脑端（`seniorAppliance`）：`primary-settings` 不存在；手搓 `SettingsScreen` / `AiProvidersScreen` 路由会退回首页 —— 同文件已覆盖。
4. 手机端任何路径都不碰麦克风：`AppState.startRecording()` 返回 `false`、`FakeMicrophoneInput.startCalls == 0`；`listenForAnswer()` / `captureProbeClip()` 都返回空 —— 已覆盖。
5. 周报链路（后端测试已有，改前端不用改后端）：同一 `(senior, period)` 跑两遍 worker 只出 1 行 digest、1 条通知；`draft` 状态家人 `GET /digests` 看不到（`backend/tests/test_digests.py`）。
6. 家人提醒（要新做的部分）：收到 `digest_ready` 后 hub 可见未读 → 点开能看到那份周报 → 「已读」写回 `PATCH /notifications/{id}`。
7. 内容约束：≤3 条、每条带 `evidence_ids`、无诊断/评分措辞（`backend/app/digests/language_guard.py`）。

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
8. **文案不一致的两处（本次没改，约定不动 `scripts/`）**：
   - `scripts/package_windows.ps1` 生成的 `README-DEMO.txt` 还写着「Settings → AI 接入」在电脑上配模型/语音——已经不存在了。
   - `mobile/README-android.md` 的「Android 语音路径」整节描述的是拆分前的 Android 语音实现。
9. **没有真机验证**：本机没有 Android 设备/模拟器，手机端只经过 widget 测试和静态分析，没有在真机上点过一遍（连不上后端、防火墙、字体渲染都未验证）。
10. `dart format --set-exit-if-changed` 对 `mobile/lib/services/android_tts_speaker.dart`、`mobile/test/android_tts_speaker_test.dart` 两个**本次未改动**的文件本来就报格式差异（历史遗留），所以 `scripts/verify.ps1` 的格式步骤会因此报红——与本次改动无关。

---

## 7. 本次改动的文件清单

**新增**

| 文件 | 内容 |
|---|---|
| `mobile/lib/platform_policy.dart` | 平台策略（唯一判断点） |
| `mobile/lib/screens/setup/setup_home_screen.dart` | 手机端 setup 首页 |
| `mobile/lib/widgets/closed_on_device.dart` | 不可用页面 → 退回首页 |
| `mobile/test/platform_policy_test.dart` | 策略单元测试（5 个） |
| `mobile/test/platform_split_test.dart` | 两端拆分行为测试（8 个） |

**修改**

| 文件 | 改了什么 |
|---|---|
| `mobile/lib/state/app_state.dart` | `policy` 字段 + 语音开关（7 个入口）+ 手机端不启动主动问候 |
| `mobile/lib/app.dart` | `RootScreen` 按平台分流 |
| `mobile/lib/screens/senior/home_screen.dart` | 电脑端不渲染设置入口 |
| `mobile/lib/screens/senior/settings_screen.dart` | 非手机端 → 回首页 |
| `mobile/lib/screens/senior/ai_providers_screen.dart` | 非手机端 → 回首页；ASR 测试在手机端不录音（改叫「测试语音识别配置」，后端如实回 `no_sample`） |
| `mobile/lib/screens/senior/talk_screen.dart` | 电脑端不推设置路由，同意/识别提示改指家人手机 |
| `mobile/lib/widgets/anchor_scaffold.dart` | 手机端不渲染 StopBar |
| `mobile/lib/l10n/strings.dart` | 新增手机端文案（中英） |
| `mobile/test/support/fakes.dart` | `buildTestState(..., policy:)`，默认 Windows 终端 |
| `mobile/test/home_widget_test.dart`、`ai_provider_test.dart`、`backend_startup_test.dart` | 按平台声明状态（设置类用例改走手机端 setup 首页；语音类用例显式声明电脑端） |

**没有改动**：`backend/`、`content/`、`scripts/`、以及任何语音服务实现（`backend_tts_speaker.dart`、`android_tts_speaker.dart`、`windows_sapi_speaker.dart`、`speech_input.dart` 全部原样保留，只在 `AppState` 里加了闸门）。
