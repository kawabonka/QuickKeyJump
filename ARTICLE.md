# 没了 Listary 的 Ctrl+G，我在 macOS 上活不下去，于是自己写了一个

> 从 Windows 叛逃 macOS 一年，我复刻了 Listary 的灵魂——而且它还附赠了 Rectangle 的窗口管理和一个自定义快捷键启动器。

---

## 那个刻进肌肉记忆的 Ctrl+G

如果你在 Windows 上用过 **Listary**，你一定懂这个瞬间：

正在 Photoshop 里导出图片，弹出保存对话框。你不去看那个密密麻麻的文件夹树，只是左手小指一按 `Ctrl`，无名指跟上 `G`——弹出一个半透明的悬浮面板，上面是你最近访问的五个文件夹。按 `1`，回车。存好了。

整个过程不到一秒。不需要碰鼠标，不需要在几百个文件夹里翻找，不需要回忆「上次那个客户方案到底放在哪个项目下面了」。

这是 Listary 最核心的功能：**任意对话框里，一键跳转到最近文件夹**。它不是「方便」，它是「一旦用过就再也回不去」。

然后我换了 Mac。

---

## Finder 很好，但没人告诉我有这个坑

macOS 有很多令人愉悦的设计。Spotlight 很快，Mission Control 很优雅，触控板手势无可挑剔。

但当我第一次在 Photoshop for Mac 里导出文件，弹出那个熟悉的保存对话框时，我的左手自动按下了 `⌥⌘G`——

什么也没发生。

那一瞬间的失落感，任何 Listary 老用户都懂。

我去搜了各种替代品。Alfred 的 File Navigation 不够直接。Raycast 的 Quicklinks 需要提前配置。Default Folder X 要 $40 而且功能过载。**没有一个能做到「弹窗→选最近文件夹→确认」这条最短路径**。

于是我打开了 Xcode。

好吧，准确地说，我打开了 Terminal，敲了 `swiftc`。

---

## QuickKeyJump：不只是 Listary 替代品

最初我只想复刻那个 `Ctrl+G` 的肌肉记忆。但写着写着，我发现这个思路可以扩展——**为什么不用同一套全局快捷键机制，去做更多事？**

于是 QuickKeyJump 从一个「快速文件夹跳转工具」变成了一个**通用快捷操作启动器**：

### 🗂 快速跳转（⌥⌘G）

核心功能。在任何地方按下 `⌥⌘G`，弹出最近 5 个 Finder 文件夹。`1`-`5` 数字键直达，`↑↓` 选择，`↵` 确认。Finder 窗口和保存/打开对话框都支持。

它做的事情说起来简单：读取 `~/Library/Preferences/com.apple.finder.plist` 里的 `FXRecentFolders`，解析 bookmark data，然后在 Finder 里通过 AppleScript 直接设置 `target of front Finder window`，对话框里通过 Accessibility API 模拟 `⌘⇧G` 粘贴路径。

实现起来，踩了无数 AX API 的坑。

### 📁 文件管理器（⌘E）

一键打开 Finder 主目录。比点击 Dock 上的 Finder 图标再导航快得多。

### 🪟 窗口管理 × 6（⌃⇧← → 参照 Rectangle）

这是我开发到一半决定加进去的。既然已经有全局快捷键系统了，为什么不把窗口管理也集成进来？

参照 [Rectangle](https://github.com/rxhanson/Rectangle) 的算法——`visibleFrame` 精准计算（自动扣除菜单栏和 Dock 高度）、8px 间距、三级 AX API fallback（焦点窗口→主窗口→窗口列表）——实现了六个窗口操作：

| 操作 | 默认快捷键 |
|---|---|
| 左半屏 | `⌃⇧←` |
| 右半屏 | `⌃⇧→` |
| 最大化 | `⌃⌥↑` |
| 几乎最大化 | `⌥⌘↑` |
| 下一显示器 | `⌃⌥→` |
| 合适大小 | `⌃⌥↓` |

每一个快捷键都可以在偏好设置里**自定义录制**——用的是 Sindre Sorhus 的 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 库，基于 CGEvent tap，不会像自己手写的那样被其他 app 抢焦点。

### ⚙️ 偏好设置（⌘,）

打开设置面板，你会看到每个操作旁边都有一个**快捷键录制按钮**。点击后按下你想用的组合键，即刻生效。不满意？左下角「恢复默认」一键还原。

此外还有：
- **开机自启**开关
- **辅助功能权限**直达按钮
- **中文 / English**双语切换

---

## 安装

### 方式一：下载 DMG

从 [GitHub Releases](https://github.com/kawabonka/QuickKeyJump) 下载 `QuickKeyJump.dmg`，挂载后拖入 `Applications`。

### 方式二：自行编译

```bash
git clone https://github.com/kawabonka/QuickKeyJump.git
cd QuickKeyJump/sources
make build
open Build/QuickKeyJump.app
```

不需要 Xcode 项目。`swiftc` 纯命令行编译，SDK 自动检测。

### 首次启动

macOS 会弹出**辅助功能权限**对话框。窗口管理和快速跳转需要这个权限（用的是 `AXUIElement` API）。授权后菜单栏会出现一个 `Q⌘` 图标，表示它在后台运行。

---

## 技术栈

这个项目全程用 `swiftc` 命令行编译——没有 Xcode 项目文件，没有 Storyboard，没有 CocoaPods。

| 组件 | 方案 |
|---|---|
| 全局快捷键 | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) v2.0.0 (CGEvent tap) |
| 窗口管理 | AX API + `visibleFrame` 计算（参照 Rectangle） |
| 设置界面 | SwiftUI + `NSHostingView` |
| 快捷键录制 | `KeyboardShortcuts.RecorderCocoa` |
| 开机自启 | `SMAppService.mainApp` (macOS 13+) |
| 国际化 | 自研 `L(zh, en)` 辅助函数 |

完整开发历程和所有 commit 都在仓库里。

---

## 最后

这个 App 从最初只支持文件夹跳转的 `QuickFolderJump` v2.0.0，迭代到现在的 `QuickKeyJump` v4.2.2——集成了文件夹跳转、窗口管理、文件管理器、双语切换、自定义快捷键——总共花了几十个 commit。大部分代码是和 [Codex](https://openai.com/index/introducing-codex/) 一起写的。

如果你也是从 Windows 转到 macOS 的 Listary 用户，或者你只是想要一个轻量、不打扰的快捷操作工具，欢迎试试。

**Star 和 PR 都欢迎。**

🔗 [github.com/kawabonka/QuickKeyJump](https://github.com/kawabonka/QuickKeyJump)
