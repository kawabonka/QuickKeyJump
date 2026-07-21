<p align="center">
  <img src="sources/AppIcon.icns" width="96" alt="QuickKeyJump" />
</p>

<h3 align="center">QuickKeyJump</h3>
<p align="center">全局快捷键 · 窗口管理 · 快速文件夹跳转 · 文件管理器<br>专为 macOS 打造</p>

<p align="center">
  <a href="README.md">English</a>
</p>

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
