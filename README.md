<p align="center">
  <img src="sources/AppIcon.icns" width="96" alt="QuickKeyJump" />
</p>

<h3 align="center">QuickKeyJump</h3>
<p align="center">Global shortcuts · Window management · Quick folder jump · File manager<br>for macOS</p>

<p align="center">
  <a href="README.zh-CN.md">中文</a>
</p>

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
