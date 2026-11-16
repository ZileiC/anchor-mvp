Everhere — Windows 自包含版（无需安装）
======================================

双击 anchor_app.exe 即可。App 会在后台自动启动内置后端（backend\anchor_backend.exe），
等它就绪后进入登录页；退出 App 时会自动关闭它。不需要安装 Python / Flutter，也不需要手动开后端。

（文件名沿用 anchor_app.exe / anchor_backend.exe，是为了不打断已有的快捷方式和装机目录；
窗口标题、应用名、图标都是 Everhere。）

首次启动会在 backend\data\anchor.db 生成演示数据（林秀兰 + 家人 Mei）。
如果程序目录不可写，数据库会放到 %LOCALAPPDATA%\Anchor\anchor.db。

演示账号
  1 = 林秀兰（老人）
  2 = Mei（家人）

这台电脑上没有设置界面
  电脑是给老人用的「终端」：说话、我的选择、打电话、停止，就这些。
  所有配置（AI 模型、语音识别 key、家人联系方式、周报）都在家人的手机 App 上做，
  手机和电脑连同一个 Wi-Fi（或手机热点）即可。手机端不提供语音功能。

手机怎么连上电脑
  打开手机 App 时会自动在局域网里找这台电脑，找到就显示「已连上」。
  找不到时点「换一个地址」，填 http://电脑的IP:8077（这台电脑的首页会显示该地址）。

接入真模型（否则回复是离线模板）
  在手机 App 的「AI 接入」里填 DeepSeek API Key（预设已是 base URL + deepseek-flash）
  和语音识别 key（预设已是 SiliconFlow base URL + Qwen3-ASR），保存后测试。
  Key 只保存在这台电脑的 backend\data\anchor.db，接口返回时打码。

声音
  * 优先用 DeepSeek 语音合成（和对话同一个 key），实测说完到出声约 2 秒。
  * 合成失败或超时会自动换成微软 Edge 神经语音（约 7 秒），再不行退回 Windows 系统语音。
  * 「说慢一点」只对备用语音（Edge）生效，DeepSeek 接口没有语速参数。

老人自己的选择（电脑端「我的选择」）
  * 允许/关闭云端处理、主动问候、与家人分享哪些话题、停止全部分享。
  * 给机器人起名字：点「它叫什么名字」，输入后聊天里就用这个名字。
  * 用哪个声音说话：女声 / 男声（对应 DeepSeek 的 stella / tide）。

演示提示
  * 主动问候只在 App 前台、且在问候窗口内出现；演示数据默认窗口 09:00–21:00。
  * 所有姓名/记录都是合成演示数据，不是真实老人数据。
  * 后端数据目录：backend\data\（删掉即可重置演示）。
  * 诊断日志：backend\data\backend.log（若存在）。

已知限制
  * 这是 Flutter Debug 构建，启动略慢、体积偏大。
  * 后端监听 0.0.0.0:8077（手机端才能连上）；若端口被占用，App 会当作已有后端。
  * 这台电脑必须开着（最小化可以，关掉窗口手机就断了）。
  * 详细限制见仓库 docs/limitations.md。
