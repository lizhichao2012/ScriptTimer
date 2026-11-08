# ScriptTimer

macOS 上的定时脚本工具：填入 Shell / Python 脚本，设置执行时间和重复规则，到点自动执行。

- **任务只在 ScriptTimer 运行时执行**：关闭主窗口后 App 仍在菜单栏运行，任务照常执行；退出 App 后不再执行，也不会在系统中注册任何后台任务
- 可在菜单栏或主窗口左下角开启“开机时自动启动”
- 主窗口管理任务、编辑脚本、查看运行历史和输出；菜单栏图标显示即将执行的任务、最近结果，并可立即运行
- 重复方式：仅一次 / 每隔 N 分钟·小时 / 每天 / 每周几 / 每月几号 / Cron 表达式
- 失败时可发送系统通知；每个任务保留最近 50 份日志

## 安装

```sh
brew install xcodegen   # 如未安装
./scripts/build.sh      # 构建 Release、签名并安装到 /Applications
```

开发：`xcodegen generate` 后用 Xcode 打开 `ScriptTimer.xcodeproj`。
测试：`xcodebuild -project ScriptTimer.xcodeproj -scheme ScriptTimer -destination 'platform=macOS' test`

发给其他 Mac：对方首次需右键 →“打开”，或执行 `xattr -dr com.apple.quarantine /Applications/ScriptTimer.app`。
若要无提示分发，需要 Apple Developer 账号做 Developer ID 签名和公证。App 关闭了沙盒，无法上架 Mac App Store。

## 工作原理

App 内置调度器每秒检查一次到点的任务，到点后用 `runner.sh`（打包在 App 内）启动脚本，由它记录输出、写执行历史、发送失败通知。
App 声明了后台活动以避免 App Nap，窗口关闭或隐藏时计时依然准确（不影响电脑正常睡眠）。

| 位置 | 内容 |
|---|---|
| `~/Library/Application Support/ScriptTimer/tasks.json` | 任务配置 |
| `…/scripts/<id>.sh\|.py` | 脚本正文 |
| `…/logs/<id>/` | 每次运行的输出 `*.log` 和 `history.jsonl` |

## 注意事项

- **App 未运行期间错过的执行不会补跑**；一次性任务若在 App 关闭期间到点，会显示“已停用（时间已过）”。
- **睡眠**：电脑睡眠期间错过的执行，唤醒后补跑一次，然后按原规则继续。
- **不会并发**：上一次执行还没结束时，到点的这一次会跳过。
- **退出 App 时正在运行的脚本**会继续跑完，之后不再有新的执行。
- **PATH**：任务使用你交互式登录 Shell（`zsh -il`）的 PATH，所以能找到 Homebrew 等工具；也可在任务里填写解释器的绝对路径或覆盖环境变量。
- **“每隔”类任务**从 App 启动或任务保存、启用时开始计时，不对齐整点；需要对齐请用 Cron（如 `*/15 * * * *`）。
- **隐私权限**：脚本读写“桌面 / 文稿 / 下载”等目录时，系统可能会弹窗请求 ScriptTimer 的访问权限，允许即可；也可在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中添加 ScriptTimer。
- **Cron** 支持 `* , - /`、月份/星期英文缩写和 `@daily` 等宏。
- 卸载：退出并删除 App，再删除 `~/Library/Application Support/ScriptTimer`。
