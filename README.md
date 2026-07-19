# QuickFolderJump

macOS Listary-style quick folder jump tool. Press **⌥⌘G** anywhere to pop up your 5 most recent Finder folders, then jump instantly.

## Features

- **⌥⌘G** global hotkey to summon the panel
- Displays your 5 most recently used Finder folders
- `1`–`5` keys for instant selection, `↑↓` to navigate, `Enter` to confirm, `Esc` to cancel
- **Finder mode**: directly sets `target of front Finder window` via AppleScript — no flicker, no dialog
- **Dialog mode**: when a Save/Open dialog is frontmost, navigates via Cmd+Shift+G + paste
- Menu bar icon with quick access to refresh, check permissions, or quit

## Requirements

- macOS 11.0+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Automation permission for Finder (granted on first use)

## Build

```bash
cd sources && make build
```

The built app will be at `sources/.build/QuickFolderJump.app`.

## Usage

1. Open `QuickFolderJump.app` (it runs in the background with a menu bar icon)
2. Press **⌥⌘G** in Finder or any Save/Open dialog
3. Select a folder with `1`–`5` or arrow keys + `Enter`
4. Your Finder window or dialog jumps to that folder

## v2.0.0

- Fixed: Finder navigation now uses native AppleScript (`set target of front Finder window`) instead of Cmd+Shift+G dialog workaround
- Fixed: Navigation is now routed correctly — Finder uses `FinderWindowNavigator`, dialogs use `DialogNavigator`
- Cleaned up dead code and orphaned files
- Build: MacOSX15.sdk compatibility
