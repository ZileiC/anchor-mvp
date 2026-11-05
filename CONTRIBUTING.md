# 协作方式（组员必读）

这个仓库现在**公开可看**，但 `main` 分支只保留给集成负责人。组员请走 **fork + Pull Request**，不要直接往 `main` push。

## 一次完整流程

```bash
# 1. 在 GitHub 上点 Fork（ZileiC/anchor-mvp -> 你自己的账号）
# 2. clone 你自己的 fork
git clone https://github.com/<你的用户名>/anchor-mvp.git
cd anchor-mvp

# 3. 每次改动开一个分支（名字说清楚改什么）
git checkout -b feat/digest-wording
# ...改代码...
git add -A
git commit -m "digest: 调整中文措辞并补测试"
git push origin feat/digest-wording

# 4. 在 GitHub 上对你的分支发起 Pull Request 指向 ZileiC/anchor-mvp:main
```

## 提交前必须自测

```powershell
cd anchor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify.ps1 -SkipBuild
```

- 后端测试（pytest）、`dart format`、`flutter analyze`、`flutter test` 必须全绿。
- 涉及 Windows 构建的改动，再跑一次完整 `scripts\verify.ps1`。
- **不要**为了让测试过而删测试/放宽断言；契约问题先改 `SPEC.md` 并写进 `DECISIONS.md`。

## 不要提交的东西

`.venv/`、`backend/data/*.db`、`mobile/build/`、`mobile/dist/`、`*.log`、临时探测脚本。
这些已在 `.gitignore` 里，`git status` 应该保持干净。

## 环境提醒

- 仓库路径含非 ASCII 字符时，CMake 4.x 和 Dart analysis server 会崩；所有 Flutter 命令都走
  `scripts/verify.ps1` / `scripts/build_windows.ps1` 的 ASCII 镜像（`%LOCALAPPDATA%\anchor-build\mobile`），
  不要直接在工作区路径 `flutter build windows`。
- 前端只保证 `flutter analyze` + `flutter test`；真实 exe 由集成负责人统一重建。
- 演示数据库是本地生成的（`backend/data/anchor.db`，已 gitignore）；需要 demo 数据跑
  `python scripts/seed_demo.py`。

## PR 检查清单

- [ ] 变更范围只碰自己负责的目录（backend / mobile / docs 之一），避免大范围格式重排
- [ ] 新增行为都有测试；新端点有鉴权/越权用例
- [ ] `scripts\verify.ps1 -SkipBuild` 绿
- [ ] 涉及契约的改动已更新 `SPEC.md` + `DECISIONS.md`
- [ ] 没有提交密钥、真实老人数据或本地大文件
