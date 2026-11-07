<p align="center">
  <img src="sources/AppIcon.icns" width="96" alt="QuickKeyJump" />
</p>

<h3 align="center">QuickKeyJump</h3>
<p align="center">全局快捷键 · 窗口管理 · 快速文件夹跳转 · 文件管理器<br>专为 macOS 打造</p>

<p align="center">
  <a href="README.md">English</a>
</p>

---

## 为什么做这个？

Windows 上，[Listary](https://www.listary.com/) 是一个神器。在任何地方按 `Ctrl+G`——甚至包括保存对话框——一个悬浮面板列出你最近访问的文件夹。按数字键直达，整个过程不到一秒。用过一天就变成肌肉记忆。

然后你换到了 macOS。

没有这样的工具。Alfred 的 File Navigation 需要多步操作。Raycast 的 Quicklinks 要手动配置。Default Folder X 售价 $40，把你要的唯一功能淹没在十几个不需要的功能里。

于是我自己写了一个。QuickKeyJump 最初只是对 Listary 的忠实复刻。后来它变大了——有了全局快捷键引擎，为什么只做文件夹跳转？窗口管理、文件管理器，都在你指尖。

---

## 功能

| 操作 | 默认快捷键 | 说明 |
|---|---|---|
| 快速跳转 | `⌥⌘G` | 弹出最近 5 个 Finder 文件夹，数字键直达 |
| 文件管理器 | `⌘E` | 打开 Finder 用户主目录 |
| 左半屏 | `⌃⇧←` | 窗口占据屏幕左半 |
| 右半屏 | `⌃⇧→` | 窗口占据屏幕右半 |
| 最大化 | `⌃⌥↑` | 窗口最大化（保留菜单栏/Dock） |
| 几乎最大化 | `⌥⌘↑` | 90% 宽 × 90% 高，居中显示 |
| 下一显示器 | `⌃⌥→` | 移至下一屏幕并最大化 |
| 合适大小 | `⌃⌥↓` | 70% × 80% 居中 |

> 所有快捷键可在 **偏好设置**（`⌘,`）中自定义

当前打开的 Finder 窗口所展示的目录也会在唤醒时加入候选，即使目录内容没有修改；按本次采样时间合并、去重，并遵循忽视清单。

## 文本转换粘贴

菜单栏点击 **文本转换粘贴…**（位于“清理内存”下方），打开左右双栏转换窗口。

- 左侧粘贴或输入内容，支持自动识别，也可手动指定 Markdown、HTML、Slack、纯文本。
- 右侧选择目标格式，实时查看富文本预览或源码，点击“复制转换结果”后在目标应用按 `⌘V`。
- 富文本复制同时提供 HTML 与纯文本；转换全部在本机完成，无需联网，不保存输入内容。
- Slack 支持常见加粗、删除线和链接转换；不含公式及 LaTeX/Typst 转换。

## 安装

从 [最新 Release](https://github.com/kawabonka/QuickKeyJump/releases) 下载 `QuickKeyJump.dmg`，挂载后拖入 `Applications`。

首次启动时授予**辅助功能**权限。窗口管理和快速跳转需要此权限。

### 从源码编译

```bash
git clone https://github.com/kawabonka/QuickKeyJump.git
cd QuickKeyJump/sources
make build
open Build/QuickKeyJump.app
```

**要求**：macOS 11.0+，Xcode Command Line Tools

## 偏好设置（`⌘,`）

- 自定义每个操作的全局快捷键（点击录制按钮）
- 点击操作图标直接在设置里试用
- **默认输入法**：选择系统已启用的输入法并开启自动恢复，每次切换 App 后恢复默认；当前 App 内仍可手动切换。首次使用默认关闭。
- **诊断日志**：可选开启，复现跳转问题后通过“打开日志文件夹…”取得 `.log` 文件，默认关闭。日志位于 `~/Library/Logs/QuickKeyJump/`，仅保存在本机。
- **开机自启**开关
- **辅助功能权限**直达按钮
- **中文 / English**语言切换
- 一键恢复默认设置

## 技术栈

- **Swift 5** · `swiftc` 命令行编译（无 Xcode 项目）
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** v2.0.0 — CGEvent 全局热键引擎
- **AX API** — 窗口位置/尺寸操作（参照 Rectangle）
- **SwiftUI** — 偏好设置界面
- **SMAppService** — 开机自启（macOS 13+）

## 致谢

- [kawabonka/QuickKeyJump](https://github.com/kawabonka/QuickKeyJump)
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT)
- [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle)

## 许可证

MIT
