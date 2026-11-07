<p align="center">
  <img src="sources/AppIcon.icns" width="96" alt="QuickKeyJump" />
</p>

<h3 align="center">QuickKeyJump</h3>
<p align="center">Global shortcuts · Window management · Quick folder jump · File manager<br>for macOS</p>

<p align="center">
  <a href="README.zh-CN.md">中文</a>
</p>

---

## Why QuickKeyJump?

On Windows, [Listary](https://www.listary.com/) is a godsend. Press `Ctrl+G` anywhere—even inside a Save dialog—and a floating panel shows your most recent folders. Tap a number key. Done. It becomes muscle memory within a day.

Then you switch to macOS.

There's nothing like it. Alfred's File Navigation requires extra steps. Raycast Quicklinks need manual setup. Default Folder X costs $40 and buries the one feature you need under a dozen you don't.

So I built QuickKeyJump. It started as a faithful Listary clone for macOS. Then it grew—because once you have a global hotkey engine, why stop at folder jumping? Window management, file manager, all at your fingertips.

---

## Features

| Action | Default | Description |
|---|---|---|
| Quick Jump | `⌥⌘G` | Show 5 most recent Finder folders, pick with number keys |
| File Manager | `⌘E` | Open Finder home directory |
| Left Half | `⌃⇧←` | Window occupies left half of screen |
| Right Half | `⌃⇧→` | Window occupies right half of screen |
| Maximize | `⌃⌥↑` | Maximize window (preserve menu bar / Dock) |
| Almost Maximize | `⌥⌘↑` | 90% width × 90% height, centered |
| Next Display | `⌃⌥→` | Move to next display and maximize |
| Reasonable Size | `⌃⌥↓` | 70% × 80% centered |

> All shortcuts are customizable in **Preferences** (`⌘,`)

## Install

Download `QuickKeyJump.dmg` from the [latest release](https://github.com/kawabonka/QuickKeyJump/releases), mount it, and drag `QuickKeyJump.app` to `Applications`.

On first launch, grant **Accessibility** permission when prompted. Window management and quick jump require this.

### Build from source

```bash
git clone https://github.com/kawabonka/QuickKeyJump.git
cd QuickKeyJump/sources
make build
open Build/QuickKeyJump.app
```

**Requirements**: macOS 11.0+, Xcode Command Line Tools

## Preferences (`⌘,`)

- Customize each action's global shortcut (click to record)
- Click the action icon to test it directly from settings
- **Launch at Login** toggle
- **Accessibility** permission shortcut
- **中文 / English** language switcher
- Reset all to defaults

## Tech Stack

- **Swift 5** · `swiftc` command-line build (no Xcode project)
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** v2.0.0 — CGEvent-based global hotkey engine
- **AX API** — window position/size (Rectangle-style)
- **SwiftUI** — Preferences window with shortcut recorder
- **SMAppService** — launch-at-login (macOS 13+)

## Credits

- [kawabonka/QuickKeyJump](https://github.com/kawabonka/QuickKeyJump)
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT)
- [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle)

## License

MIT

### Default input source

In Preferences, choose an enabled input source and turn on **Restore Default Input Source**. QuickKeyJump restores it after each app activation while allowing manual switching within the active app. This feature is off initially. If the saved input source is removed or disabled, choose another in Preferences.

### Diagnostic logging (4.6.1)

Enable **Diagnostic Logging** in Preferences, reproduce the file-picker navigation issue, then disable logging and use **Open Log Folder…** to find the new `.log` file. Logging is off by default and stored locally in `~/Library/Logs/QuickKeyJump/`. Logs include app/process/window identities, window titles, target folder paths, focus transitions and navigation results, but no text-field contents or ordinary keystrokes. This release adds diagnostics; file-picker compatibility is still under investigation.

### Open Finder folders (4.6.3)

Quick Jump samples the folders currently displayed in open Finder windows in the background, merges them with recent history and Spotlight, and keeps the freshest observation per path. Open folders can appear even if their contents have not changed. Ignore rules and the 10-item limit still apply. Allow Finder automation access if macOS asks.

## Clipboard Converter

Choose **Clipboard Converter…** below **Clean Memory** in the menu bar. Paste or type Markdown, HTML, Slack, or plain text on the left, choose an output format on the right, and copy the result to another application with `⌘V`. Rich text copying includes both HTML and plain text. All conversion runs offline without saving input. Slack supports common emphasis, strikethrough, and links; mathematical typesetting is not included.
