# QuickFolderJump - macOS 快速目录跳转工具

类似 Windows Listary Ctrl+G 功能的 macOS 原生实现。按快捷键弹出最近使用的目录列表，一键跳转。

## 功能特性

- **全局快捷键** `Option+J` 快速呼出窗口（支持自定义）
- **5个最近目录** 从 `~/Library/Preferences/com.apple.finder.plist` 的 `FXRecentFolders` 读取，按时间排序
- **数字键 1-5** 直接跳转对应目录
- **上下箭头 + 回车** 选择并确认
- **保存/打开对话框跳转** 自动检测对话框，通过 Cmd+Shift+G 导航到指定目录
- **Finder 窗口导航** 有窗口则复用，无窗口则新建
- **菜单栏图标** 提供常用操作入口

## 技术方案概要

| 功能模块 | 实现方案 | 成功率 | 所需权限 |
|---------|---------|--------|---------|
| 读取最近目录 | 读取 `FXRecentFolders` + 解析 bookmarkData | ~100% | 无需权限 |
| Finder跳转 | AppleScript (`osascript`) 控制 Finder | ~95% | 自动化权限 |
| 对话框跳转 | 模拟 Cmd+Shift+G + 输入路径 + 回车 | ~95% | 辅助功能权限 |

## 构建方式

### 方式一：命令行构建（无需Xcode）

```bash
# 进入源码目录
cd /path/to/sources

# 构建 .app 应用包
make build

# 仅编译二进制（不打包）
make build-binary

# 编译并运行
make run

# 安装到 /Applications
make install

# 卸载
make uninstall

# 代码签名（ad-hoc，用于测试）
make sign
```

### 方式二：Xcode构建

1. 打开 Xcode，选择 **File > New > Project**
2. 选择 **macOS > App**，点击 Next
3. 填写项目名称 **QuickFolderJump**，选择 **Swift** + **SwiftUI**
4. 创建项目后，将所有 `.swift` 源文件拖入项目
5. 将 `Info.plist` 复制到项目目录并添加到项目
6. 在 **Build Settings** 中搜索 `Info.plist File`，设置为 `$(SRCROOT)/Info.plist`
7. 在 **Signing & Capabilities** 中关闭 Sandboxing（沙盒限制辅助功能API）
8. 按 `Cmd+B` 构建，`Cmd+R` 运行

### 方式三：直接编译

```bash
cd /path/to/sources

# 直接编译
swiftc -O \
  -parse-as-library \
  main.swift \
  RecentFolderManager.swift \
  KeyboardHandler.swift \
  QuickJumpView.swift \
  QuickJumpPanel.swift \
  DialogNavigator.swift \
  FinderWindowNavigator.swift \
  AppDelegate.swift \
  -framework Cocoa \
  -framework Carbon \
  -framework ApplicationServices \
  -framework SwiftUI \
  -o build/QuickFolderJump

# 运行
./build/QuickFolderJump
```

## 首次使用设置

### 1. 辅助功能权限（对话框跳转必需）

首次运行时，系统会弹出权限请求。如未弹出，可手动设置：

1. 打开 **系统设置 > 隐私与安全性 > 辅助功能**
2. 点击 **+** 添加应用
3. 选择 `QuickFolderJump.app`（或构建出的二进制文件）
4. 确保开关为 **开启** 状态

> 此权限用于检测前台是否有保存/打开对话框，以及向对话框发送按键事件。

### 2. 自动化权限（Finder跳转必需）

首次跳转到 Finder 时，系统会自动弹出权限请求：

1. 弹出对话框 "QuickFolderJump 想要控制 Finder"
2. 点击 **好**

或在 **系统设置 > 隐私与安全性 > 自动化** 中确保 QuickFolderJump 的 Finder 选项已勾选。

### 3. 设置开机启动（可选）

1. 打开 **系统设置 > 通用 > 登录项**
2. 点击 **+**
3. 选择 `/Applications/QuickFolderJump.app`

## 使用说明

### 基本操作

| 操作 | 说明 |
|------|------|
| `Option + J` | 呼出/关闭跳转窗口 |
| `1` ~ `5` | 直接跳转对应目录 |
| `↑` / `↓` | 上下选择目录 |
| `↵` (回车) | 确认跳转当前选中项 |
| `Esc` | 取消关闭窗口 |

### 使用场景

**场景1：在 Finder 中跳转**
1. 确保 Finder 在前台（或没有其他对话框）
2. 按 `Option+J`
3. 按数字键 `1`~`5` 或上下箭头选择目录
4. Finder 窗口会导航到选定目录（有窗口则复用，无窗口则新建）

**场景2：在保存/打开对话框中跳转**
1. 打开任意应用的保存/打开对话框（如 TextEdit 的文件 > 存储）
2. 按 `Option+J`
3. 选择目标目录
4. 对话框会自动跳转到该目录（通过 Cmd+Shift+G 实现）

**场景3：通过菜单栏操作**
- 点击菜单栏图标，选择 "打开 QuickJump"
- 选择 "刷新最近目录" 手动刷新列表

## 自定义快捷键

编辑 `AppDelegate.swift` 第161行，修改注册的热键：

```swift
// 注册热键：Option + J（默认）
let hotKeyStatus = RegisterEventHotKey(
    UInt32(kVK_ANSI_J),        // 键码：J
    UInt32(optionKey),          // 修饰键：Option
    // ...
)
```

常用键码参考：

| 键 | 键码常量 | 十六进制值 |
|----|---------|-----------|
| A-Z | `kVK_ANSI_A` ~ `kVK_ANSI_Z` | 0x00 ~ 0x05, 0x08 ~ 0x11, 0x12 ~ 0x1A |
| G | `kVK_ANSI_G` | 0x05 |
| 0-9 | `kVK_ANSI_0` ~ `kVK_ANSI_9` | 0x1D, 0x12 ~ 0x19 |
| F1-F12 | `kVK_F1` ~ `kVK_F12` | 0x7A, 0x78, 0x63, ... |
| Space | `kVK_Space` | 0x31 |

修饰键参考：

| 修饰键 | 常量 | 值 |
|--------|------|-----|
| Command | `cmdKey` | 0x0100 |
| Option | `optionKey` | 0x0800 |
| Control | `controlKey` | 0x1000 |
| Shift | `shiftKey` | 0x0200 |

例如修改为 `Ctrl+G`：

```swift
let hotKeyStatus = RegisterEventHotKey(
    UInt32(kVK_ANSI_G),         // G
    UInt32(controlKey),          // Ctrl
    EventHotKeyID(signature: kQuickJumpHotKeyIdentifier, id: 1),
    GetEventDispatcherTarget(),
    0,
    &hotKeyRef
)
```

## Raycast 集成（可选）

如果你使用 Raycast，可以将此工具注册为 Raycast 脚本命令：

1. 将构建的 `QuickFolderJump` 二进制文件复制到 Raycast 脚本目录：
   ```bash
   cp build/QuickFolderJump ~/.config/raycast/scripts/
   ```
2. 在 Raycast 中配置脚本命令，设置快捷键触发

或者使用 Swift 代码中已有的全局快捷键（`Option+J`），无需额外配置即可与 Raycast 共存。

## 文件结构

```
sources/
├── main.swift                    # 应用入口 @main
├── AppDelegate.swift             # 应用委托，协调所有模块
├── RecentFolderManager.swift     # 读取 FXRecentFolders 数据源
├── KeyboardHandler.swift         # 键盘事件处理（1-5/箭头/回车/Esc）
├── QuickJumpView.swift           # SwiftUI 界面
├── QuickJumpPanel.swift          # NSPanel 窗口管理
├── DialogNavigator.swift         # 保存/打开对话框跳转
├── FinderWindowNavigator.swift   # Finder 窗口导航
├── Info.plist                    # 应用配置（LSUIElement 等）
└── Makefile                      # 命令行构建脚本
```

## 调试指南

### 1. 查看控制台日志

```bash
# 实时查看应用日志
log stream --predicate 'process == "QuickFolderJump"' --level debug

# 或使用 Console.app 搜索 QuickFolderJump
```

### 2. 直接运行查看输出

```bash
cd /path/to/sources
make run
```

应用会将日志输出到终端，如：
```
[QuickFolderJump] 全局热键 Option+J 注册成功
[RecentFolderManager] 加载了 5 个最近文件夹
[DialogNavigator] 已发送 Cmd+Shift+G 快捷键
[FinderWindowNavigator] 已在Finder现有窗口中导航到: /Users/xxx/Documents
```

### 3. 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|---------|---------|
| 按 `Option+J` 无反应 | 热键注册失败，或其他应用占用 | 检查控制台日志；尝试修改热键键码 |
| 窗口弹出后无焦点 | 激活策略切换失败 | 检查 `activateApplication()` 调用；尝试手动点击窗口 |
| 无法跳转Finder | 缺少自动化权限 | 系统设置 > 隐私与安全 > 自动化 > 勾选Finder |
| 对话框跳转无效 | 缺少辅助功能权限 | 系统设置 > 隐私与安全 > 辅助功能 > 添加应用 |
| 最近目录列表为空 | FXRecentFolders不存在 | 先用 Finder 访问几个不同目录，再试 |
| 编译失败 | 缺少框架或SDK | 运行 `xcode-select --install` 安装命令行工具 |

### 4. 使用 Accessibility Inspector 调试对话框检测

1. 打开 Xcode > Open Developer Tool > Accessibility Inspector
2. 选择目标应用（如 TextEdit）
3. 打开保存/打开对话框
4. 查看窗口的 Role 和 Subrole 属性
5. 确认是否显示为 `AXSheet` 或 `AXDialog`

### 5. 手动测试 AppleScript

```bash
# 测试 Finder 导航
osascript -e 'tell application "Finder" to set target of front window to (POSIX file "/Users/$USER/Documents")'

# 测试对话框检测（System Events需要辅助功能权限）
osascript -e 'tell application "System Events" to return (name of processes) contains "Finder"'
```

### 6. 检查 FXRecentFolders 数据

```bash
# 查看原始数据
plutil -p ~/Library/Preferences/com.apple.finder.plist | grep -A 100 "FXRecentFolders"

# 提取路径列表
plutil -p ~/Library/Preferences/com.apple.finder.plist | grep -E '"name"|"file-bookmark"|"_CFURLString"'
```

### 7. 性能分析

如果窗口弹出有延迟，检查：

```bash
# 测试读取 FXRecentFolders 耗时
time /usr/libexec/PlistBuddy -c "Print :FXRecentFolders" ~/Library/Preferences/com.apple.finder.plist > /dev/null

# 正常应该在 50ms 以内
```

### 8. 热键冲突排查

```bash
# 检查是否有其他应用注册了相同的热键
# 1. 临时关闭 Raycast/Hammerspoon 等工具
# 2. 重新运行 QuickFolderJump
# 3. 逐步开启其他工具，看是否冲突
```

## 安全说明

1. **权限最小化**：仅需辅助功能和自动化权限，无需网络访问
2. **本地运行**：所有代码本地执行，不涉及网络请求
3. **数据源**：仅读取系统 plist 文件，不修改系统配置
4. **开源透明**：纯 Swift 原生代码，可审计

## 系统要求

- macOS 11.0 (Big Sur) 或更高版本
- Apple Silicon 或 Intel Mac

## 技术栈

- Swift 5.9+
- SwiftUI（界面）
- AppKit/NSPanel（窗口管理）
- Carbon Event API（全局热键）
- CoreGraphics（按键模拟）
- Accessibility API（对话框检测）
- AppleScript/osascript（Finder控制）

## License

MIT License - 自由使用和修改。
