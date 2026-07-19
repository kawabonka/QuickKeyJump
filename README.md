# QuickKeyJump

<p align="center">
  <img src="sources/AppIcon.icns" width="128" alt="QuickKeyJump" />
</p>

<p align="center">
  <strong>macOS 快捷操作工具</strong> · 全局快捷键 · 窗口管理 · 快速跳转 · 文件管理器<br>
  <em>A macOS quick-action launcher — global hotkeys, window management, folder jump, file manager</em>
</p>

---

## 功能 / Features

| 操作 | 默认快捷键 | 说明 |
|---|---|---|
| 快速跳转 | `⌥⌘G` | 弹出最近 5 个 Finder 文件夹，数字键直达 |
| 文件管理器 | `⌘E` | 打开 Finder 用户主目录 |
| 左半屏 | `⌃⇧←` | 窗口占据屏幕左半 |
| 右半屏 | `⌃⇧→` | 窗口占据屏幕右半 |
| 最大化 | `⌃⌥↑` | 窗口最大化（保留菜单栏/Dock） |
| 几乎最大化 | `⌥⌘↑` | 90% 宽高居中 |
| 下一显示器 | `⌃⌥→` | 移至下一屏幕并最大化 |
| 合适大小 | `⌃⌥↓` | 70% × 80% 居中 |

> **所有快捷键可在偏好设置中自定义 (⌘,)**

| Action | Default Shortcut | Description |
|---|---|---|
| Quick Jump | `⌥⌘G` | Show 5 most recent Finder folders, pick with number keys |
| File Manager | `⌘E` | Open Finder home directory |
| Left Half | `⌃⇧←` | Window occupies left half of screen |
| Right Half | `⌃⇧→` | Window occupies right half of screen |
| Maximize | `⌃⌥↑` | Maximize window (preserve menu bar / Dock) |
| Almost Maximize | `⌥⌘↑` | 90% width × 90% height, centered |
| Next Display | `⌃⌥→` | Move window to next display and maximize |
| Reasonable Size | `⌃⌥↓` | 70% × 80% centered |

> **All shortcuts are customizable in Preferences (⌘,)**

---

## 安装 / Install

Download the latest `QuickKeyJump.dmg` from [Releases](https://github.com/kawabonka/QuickKeyJump/releases), mount it, and drag `QuickKeyJump.app` to `Applications`.

首次启动会弹出辅助功能权限授权对话框。窗口管理和快速跳转需要此权限。

On first launch, the Accessibility permission dialog will appear. Window management and quick jump require this permission.

## 构建 / Build

```bash
cd sources && make build
```

产物 / Output: `sources/Build/QuickKeyJump.app`

**要求 / Requirements**: macOS 11.0+, Xcode Command Line Tools

## 偏好设置 / Preferences

`⌘,` 打开偏好设置窗口：
- 自定义每个操作的全局快捷键（点击快捷键按钮录制）
- 点击操作图标直接在设置里试用功能
- 开机自启开关
- 辅助功能权限跳转按钮
- 一键恢复默认设置

`⌘,` opens the Preferences window:
- Customize each action's global shortcut (click to record)
- Click the icon to test the action directly
- Auto-launch at login toggle
- Accessibility permission shortcut button
- Reset all to defaults

## 技术 / Tech Stack

- **Swift 5** · `swiftc` command-line build (no Xcode project)
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** v2.0.0 — CGEvent-based global hotkey engine
- **AX API** — window position/size manipulation (Rectangle-style best-effort)
- **SwiftUI** — Preferences window with native shortcut recorder
- **SMAppService** — launch-at-login registration (macOS 13+)

## 感谢 / Credits

- [kawabonka/QuickKeyJump](https://github.com/kawabonka/QuickKeyJump) — original project
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global shortcut library (MIT)
- [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) — window management reference

## License

MIT
