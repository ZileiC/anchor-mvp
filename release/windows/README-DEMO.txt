Anchor MVP — Windows 自包含演示版
=================================

双击 anchor_app.exe 即可。App 会在后台自动启动内置后端（backend\anchor_backend.exe），
等它就绪后进入登录页；退出 App 时会自动关闭它。不需要安装 Python / Flutter，也不需要手动开后端。

首次启动会在 backend\data\anchor.db 生成演示数据（林秀兰 + 家人 Mei）。
如果程序目录不可写，数据库会放到 %LOCALAPPDATA%\Anchor\anchor.db。

演示账号
  1 = 林秀兰（老人）
  2 = Mei（家人）

这台电脑上没有设置界面
  电脑是给老人用的「终端」：说话、玩一玩、打电话、停止，就这些。
  所有配置（AI 模型、语音识别 key、家人联系方式、周报）都在**家人的手机 App** 上做，
  手机和电脑连同一个 Wi-Fi 即可。手机端不提供语音功能。

接入真模型（否则回复是离线模板）
  在手机 App 的「AI 接入」里填 DeepSeek API Key（预设已是 base URL + deepseek-flash）
  和语音识别 key（预设已是 SiliconFlow base URL + Qwen3-ASR），保存后测试。
  Key 只保存在这台电脑的 backend\data\anchor.db，接口返回时打码。

声音
  * 默认走后端在线神经语音（微软 Edge 神经音色，中文自然），需要联网。
  * 断网或合成失败时自动退回 Windows 系统语音（SAPI），能出声但很机器人。
  * 说完到出声之间会有几秒合成等待。

演示提示
  * 主动问候只在 App 前台、且在问候窗口内出现；演示数据默认窗口 09:00–21:00。
  * 所有姓名/记录都是合成演示数据，不是真实老人数据。
  * 后端数据目录：backend\data\（删掉即可重置演示）。
  * 诊断日志：backend\data\backend.log（若存在）。

已知限制
  * 这是 Flutter Debug 构建，启动略慢、体积偏大。
  * 后端监听 0.0.0.0:8077（手机端才能连上）；若端口被占用，App 会当作已有后端。
  * 详细限制见仓库 docs/limitations.md。
