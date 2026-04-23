# macOS Finder 窗口导航与激活 — 技术调研报告

> 调研目的：为快速目录跳转工具选择最优的 Finder 窗口控制方案

---

## 目录

1. [方案概览对比](#1-方案概览对比)
2. [方案一：NSWorkspace 打开](#2-方案一-nsworkspace-打开)
3. [方案二：Scripting Bridge 控制 Finder](#3-方案二-scripting-bridge-控制-finder)
4. [方案三：AppleScript / osascript](#4-方案三-applescript--osascript)
5. [窗口焦点与激活](#5-窗口焦点与激活)
6. [LSUIElement 后台应用的特殊处理](#6-lsuielement-后台应用的特殊处理)
7. [推荐方案与实现代码](#7-推荐方案与实现代码)
8. [性能对比与建议](#8-性能对比与建议)

---

## 1. 方案概览对比

| 方案 | 能否复用窗口 | 能否设置target | 需要权限 | 复杂度 | 推荐度 |
|------|------------|--------------|---------|--------|--------|
| NSWorkspace.open() | 否（总是新开） | 否 | 无 | 低 | ⭐⭐ 仅作fallback |
| NSWorkspace.selectFile() | 否（总是新开） | 否（仅reveal文件） | 无 | 低 | ⭐⭐ 仅作fallback |
| Scripting Bridge | ✅ 是 | ✅ 是 | 自动化权限 | 高 | ⭐⭐⭐⭐ 推荐 |
| AppleScript (osascript) | ✅ 是 | ✅ 是 | 自动化权限 | 中 | ⭐⭐⭐⭐⭐ **最推荐** |

> **核心结论**：AppleScript/osascript 方案实现最简单、功能最完整，是首选方案。Scripting Bridge 性能略好但配置复杂。NSWorkspace 适合简单场景但无法复用窗口。

---

## 2. 方案一：NSWorkspace 打开

### 2.1 API 说明

```swift
import AppKit

// 方式1：打开文件/文件夹（总是创建新窗口）
NSWorkspace.shared.open(url)

// 方式2：指定用 Finder 打开
NSWorkspace.shared.openFile(
    "/path/to/folder", 
    withApplication: "Finder"
)

// 方式3：选择文件并 reveal（总是创建新窗口）
NSWorkspace.shared.selectFile(
    "/path/to/file", 
    inFileViewerRootedAtPath: "/path/to/root"
)

// 方式4：用 openURL 配置
NSWorkspace.shared.open(
    url,
    configuration: NSWorkspace.OpenConfiguration(),
    completionHandler: nil
)
```

### 2.2 关键局限性

**致命问题：无法复用已有 Finder 窗口**。每次调用都会创建一个新的 Finder 窗口。

Finder 本身的行为是：
- 如果某个文件夹已经在窗口中打开，再次 `open` 该文件夹会**复用**已有窗口
- 但如果通过 `NSWorkspace.open()` 打开，系统会创建**新窗口**

```swift
// ❌ 这种方式无法做到：
// "如果已有窗口，切换target；否则新建窗口"
NSWorkspace.shared.open(folderURL) // 总是开新窗口
```

### 2.3 适用场景

- 只需要简单打开文件夹，不关心窗口复用
- 作为 **fallback** 方案，当 AppleScript/Scripting Bridge 失败时使用
- 不需要任何特殊权限

### 2.4 完整代码示例

```swift
import AppKit

/// 使用 NSWorkspace 打开文件夹（简单但总是创建新窗口）
func openFolderWithWorkspace(_ path: String) {
    let url = URL(fileURLWithPath: path)
    
    // 检查路径是否存在且是目录
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        print("路径不存在或不是目录: \(path)")
        return
    }
    
    // 方式1：直接打开（会创建新Finder窗口）
    NSWorkspace.shared.open(url)
    
    // 方式2：reveal模式（会选中文件而不是打开目录）
    // NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
}
```

---

## 3. 方案二：Scripting Bridge 控制 Finder

### 3.1 原理说明

Scripting Bridge 允许通过 Objective-C/Swift API 直接与 AppleScript 可脚本化的应用程序交互。需要：

1. 添加 `ScriptingBridge.framework`
2. 生成 Finder 的头文件（`.h`）或 Swift 协议
3. 通过 `SBApplication` 获取 Finder 实例

### 3.2 项目配置

#### 步骤1：添加 Scripting Bridge 框架

在 Xcode 中：
- 选择 Target → Build Phases → Link Binary With Libraries
- 添加 `ScriptingBridge.framework`

#### 步骤2：生成 Finder 头文件

```bash
# 生成 Objective-C 头文件
sdef /System/Library/CoreServices/Finder.app | sdp -fh --basename Finder

# 这会生成 Finder.h，需要添加到项目中
# 或者在 Build Rules 中配置自动生成
```

#### Build Rule 自动配置（推荐）

```
Process: Source files with names matching: *.app
Using: Custom Script:
    sdef "$INPUT_FILE_PATH" | sdp -fh -o "$DERIVED_FILES_DIR" --basename "$INPUT_FILE_BASE" --bundleid `defaults read "$INPUT_FILE_PATH/Contents/Info" CFBundleIdentifier`

Output files:
    $(DERIVED_FILES_DIR)/$(INPUT_FILE_BASE).h
```

然后将 `Finder.app` 拖入项目并添加到 Compile Sources。

#### 步骤3：创建 Bridging Header（Swift 项目）

```objc
// Finder-Bridging-Header.h
#import <ScriptingBridge/ScriptingBridge.h>
#import "Finder.h"  // 生成的头文件
```

### 3.3 Swift 代码示例

```swift
import ScriptingBridge
import AppKit

// 获取 Finder 应用实例
guard let finder = SBApplication(bundleIdentifier: "com.apple.Finder") as? FinderApplication else {
    print("无法连接 Finder")
    return
}

// 检查 Finder 是否正在运行
let isRunning = finder.isRunning

// 获取所有 Finder 窗口
let windows = finder.finderWindows?()

// 获取第一个窗口
guard let firstWindow = windows?.firstObject as? FinderFinderWindow else {
    // 没有窗口，创建新窗口
    return
}

// 获取窗口当前 target
let target = firstWindow.target

// 设置窗口 target（导航到新目录）
// target 期望一个 FinderItem 或 NSURL
firstWindow.target = // FinderItem 或 URL
```

### 3.4 完整的 Scripting Bridge 实现

```swift
import Foundation
import ScriptingBridge
import AppKit

// 需要先运行 sdef 生成 Finder.h 并导入
// sdef /System/Library/CoreServices/Finder.app | sdp -fh --basename Finder

class FinderScriptingBridge {
    
    private var finder: FinderApplication?
    
    init() {
        self.finder = SBApplication(bundleIdentifier: "com.apple.Finder") as? FinderApplication
    }
    
    /// 导航到指定目录（复用已有窗口或新建窗口）
    func navigateTo(_ path: String) -> Bool {
        guard let finder = finder else { return false }
        
        // 确保 Finder 在运行
        if !finder.isRunning {
            finder.activate()
        }
        
        // 将路径转换为 URL
        let url = URL(fileURLWithPath: path)
        
        // 获取 Finder 窗口列表
        let windows = finder.finderWindows?()
        let windowCount = windows?.count ?? 0
        
        if windowCount > 0, let firstWindow = windows?.object(at: 0) as? FinderFinderWindow {
            // 复用第一个窗口，设置 target
            // 注意：target 需要是一个 FinderItem，可以通过 URL 获取
            firstWindow.setTarget?(url)
        } else {
            // 没有窗口，创建新窗口
            // 方式1：通过 make new Finder window
            if let newWindow = (finder.classForScriptingClass?("Finder window") as? FinderFinderWindow.Type)?.init() {
                finder.finderWindows?().addObject(newWindow)
                newWindow.setTarget?(url)
            }
            
            // 方式2：使用 open 命令
            // finder.open?(url)
        }
        
        // 激活 Finder
        finder.activate()
        
        return true
    }
    
    /// 激活 Finder 应用
    func activateFinder() {
        finder?.activate()
    }
    
    /// 获取当前窗口路径
    func getCurrentWindowPath() -> String? {
        guard let finder = finder else { return nil }
        
        let windows = finder.finderWindows?()
        guard let firstWindow = windows?.firstObject as? FinderFinderWindow,
              let target = firstWindow.target else {
            return nil
        }
        
        // target 是 FinderItem，需要获取其 URL
        if let item = target as? FinderItem {
            return item.URL
        }
        return nil
    }
}
```

### 3.5 Scripting Bridge 的优缺点

**优点：**
- 类型安全（生成类型化的 API）
- 不需要运行时解析 AppleScript
- 性能略好于 AppleScript

**缺点：**
- 配置复杂（需要生成头文件、bridging header）
- Swift 支持不够完善（大量使用可选链、`AnyObject`）
- API 动态性导致很多方法需要可选调用（`?`）
- Finder.h 每次系统更新可能需要重新生成
- 某些 API 在 Swift 中难以直接使用

---

## 4. 方案三：AppleScript / osascript（推荐方案）

### 4.1 核心 AppleScript 命令

```applescript
-- 检查是否有打开的 Finder 窗口，有则切换 target，无则新建窗口
tell application "Finder"
    activate
    if (count of Finder windows) > 0 then
        set target of front Finder window to (POSIX file "/path/to/folder")
    else
        open (POSIX file "/path/to/folder")
    end if
end tell
```

### 4.2 Swift 中执行 AppleScript 的方式

#### 方式A：使用 NSAppleScript

```swift
import Foundation

func navigateWithNSAppleScript(_ path: String) -> Bool {
    let scriptSource = """
    tell application "Finder"
        activate
        if (count of Finder windows) > 0 then
            set target of front Finder window to (POSIX file "\(path)")
        else
            open (POSIX file "\(path)")
        end if
    end tell
    """
    
    guard let appleScript = NSAppleScript(source: scriptSource) else {
        return false
    }
    
    var errorInfo: NSDictionary?
    let result = appleScript.executeAndReturnError(&errorInfo)
    
    if let error = errorInfo {
        print("AppleScript 错误: \(error)")
        return false
    }
    
    return true
}
```

#### 方式B：使用 Process 执行 osascript（推荐）

```swift
import Foundation

func navigateWithOsaScript(_ path: String) -> Bool {
    // 转义路径中的双引号，防止注入
    let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
    
    let script = """
    tell application "Finder"
        activate
        if (count of Finder windows) > 0 then
            set target of front Finder window to (POSIX file "\(escapedPath)")
        else
            open (POSIX file "\(escapedPath)")
        end if
    end tell
    """
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let error = String(data: data, encoding: .utf8) {
                print("osascript 错误: \(error)")
            }
            return false
        }
        return true
    } catch {
        print("执行失败: \(error)")
        return false
    }
}
```

### 4.3 完整的 AppleScript 方案实现

```swift
import Foundation
import AppKit

/// 基于 AppleScript 的 Finder 控制器
class FinderAppleScriptController {
    
    // MARK: - 错误定义
    
    enum FinderError: Error, LocalizedError {
        case invalidPath(String)
        pathNotFound(String)
        case notADirectory(String)
        case scriptExecutionFailed(String)
        case privacyDenied(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidPath(let path):
                return "无效路径: \(path)"
            case .pathNotFound(let path):
                return "路径不存在: \(path)"
            case .notADirectory(let path):
                return "路径不是目录: \(path)"
            case .scriptExecutionFailed(let detail):
                return "脚本执行失败: \(detail)"
            case .privacyDenied(let detail):
                return "权限被拒绝: \(detail)"
            }
        }
    }
    
    // MARK: - 公共接口
    
    /// 导航到指定目录（核心方法）
    /// - 有窗口时复用 front window 切换 target
    /// - 无窗口时创建新窗口
    /// - 自动激活 Finder 并获取焦点
    func navigateTo(_ path: String) -> Result<Void, FinderError> {
        // 1. 验证路径
        let validation = validatePath(path)
        if case .failure(let error) = validation {
            return .failure(error)
        }
        
        let absolutePath = (try? validation.get()) ?? path
        
        // 2. 执行 AppleScript
        return executeNavigationScript(path: absolutePath)
    }
    
    /// 在新窗口中打开（强制新建）
    func openInNewWindow(_ path: String) -> Result<Void, FinderError> {
        let validation = validatePath(path)
        if case .failure(let error) = validation {
            return .failure(error)
        }
        
        let absolutePath = (try? validation.get()) ?? path
        let escapedPath = escapePath(absolutePath)
        
        let script = """
        tell application "Finder"
            activate
            make new Finder window
            set target of front Finder window to (POSIX file "\(escapedPath)")
        end tell
        """
        
        return runOsaScript(script)
    }
    
    /// 获取当前 Finder 窗口路径
    func getCurrentWindowPath() -> Result<String, FinderError> {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            else
                return ""
            end if
        end try
        """
        
        let result = runOsaScriptWithOutput(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .failure(.scriptExecutionFailed("没有打开的 Finder 窗口"))
            }
            return .success(trimmed)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// 检查是否有 Finder 窗口
    func hasOpenWindows() -> Bool {
        let script = """
        tell application "Finder"
            return (count of Finder windows) > 0
        end tell
        """
        
        let result = runOsaScriptWithOutput(script)
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }
        return false
    }
    
    // MARK: - 私有方法
    
    /// 验证路径有效性
    private func validatePath(_ path: String) -> Result<String, FinderError> {
        var resolvedPath = path
        
        // 支持 ~ 展开
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            resolvedPath = home + path.dropFirst()
        }
        
        // 转为绝对路径
        resolvedPath = (resolvedPath as NSString).standardizingPath
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) else {
            return .failure(.pathNotFound(resolvedPath))
        }
        
        guard isDirectory.boolValue else {
            return .failure(.notADirectory(resolvedPath))
        }
        
        return .success(resolvedPath)
    }
    
    /// 核心导航脚本
    private func executeNavigationScript(path: String) -> Result<Void, FinderError> {
        let escapedPath = escapePath(path)
        
        // 核心逻辑：有窗口则切换 target，无窗口则 open
        let script = """
        tell application "Finder"
            activate
            if (count of Finder windows) > 0 then
                set target of front Finder window to (POSIX file "\(escapedPath)")
            else
                open (POSIX file "\(escapedPath)")
            end if
        end tell
        """
        
        return runOsaScript(script)
    }
    
    /// 执行 AppleScript（无输出）
    private func runOsaScript(_ script: String) -> Result<Void, FinderError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                
                // 检测权限被拒绝
                if errorMessage.contains("-1743") || errorMessage.contains("Not authorized") {
                    return .failure(.privacyDenied("需要在系统设置 > 隐私与安全 > 自动化中授予权限"))
                }
                
                return .failure(.scriptExecutionFailed(errorMessage))
            }
            
            return .success(())
        } catch {
            return .failure(.scriptExecutionFailed(error.localizedDescription))
        }
    }
    
    /// 执行 AppleScript（有输出）
    private func runOsaScriptWithOutput(_ script: String) -> Result<String, FinderError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                
                if errorMessage.contains("-1743") || errorMessage.contains("Not authorized") {
                    return .failure(.privacyDenied("需要在系统设置 > 隐私与安全 > 自动化中授予权限"))
                }
                
                return .failure(.scriptExecutionFailed(errorMessage))
            }
            
            return .success(output)
        } catch {
            return .failure(.scriptExecutionFailed(error.localizedDescription))
        }
    }
    
    /// 转义路径中的双引号
    private func escapePath(_ path: String) -> String {
        return path.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

### 4.4 更健壮的 AppleScript（处理各种边界情况）

```applescript
-- 健壮的 Finder 导航脚本
tell application "Finder"
    -- 如果 Finder 没有运行，启动它
    if not running then launch
    
    activate
    
    try
        -- 检查是否有可见窗口
        if (count of (every Finder window where visible is true)) > 0 then
            -- 复用 front window
            set target of front Finder window to (POSIX file "/path/to/folder")
        else if (count of Finder windows) > 0 then
            -- 有窗口但不可见，设置 target 并显示
            set target of front Finder window to (POSIX file "/path/to/folder")
            set visible of front Finder window to true
        else
            -- 没有窗口，新建
            open (POSIX file "/path/to/folder")
        end if
    on error errMsg number errNum
        -- 出错时尝试直接 open
        try
            open (POSIX file "/path/to/folder")
        on error
            display dialog "无法打开文件夹: " & errMsg
        end try
    end try
end tell
```

---

## 5. 窗口焦点与激活

### 5.1 核心 API：NSRunningApplication

```swift
import AppKit

/// 激活 Finder 应用并前置窗口
func activateFinder() {
    // 方式1：通过 NSRunningApplication
    let finderApps = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.Finder"
    )
    
    guard let finder = finderApps.first else {
        // Finder 未运行，通过 LaunchServices 启动
        NSWorkspace.shared.launchApplication("Finder")
        return
    }
    
    // 激活选项
    let options: NSApplication.ActivationOptions = [
        .activateAllWindows  // 将所有窗口带到前面
    ]
    
    finder.activate(options: options)
    
    // 旧版 API（已废弃但仍可用）
    // finder.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
}
```

### 5.2 AppleScript 中的 activate

```applescript
-- AppleScript 的 activate 会同时激活应用和前置窗口
tell application "Finder"
    activate  -- 激活应用并前置窗口
end tell
```

在 AppleScript 中，`activate` 命令会：
1. 启动应用（如果未运行）
2. 将应用设为 frontmost
3. 将应用窗口带到当前 Space
4. 给予键盘焦点

### 5.3 处理 Spaces 和全屏应用

```swift
import AppKit

/// 在指定 Space 激活 Finder（处理多桌面）
func activateFinderOnCurrentSpace() {
    let script = """
    tell application "Finder"
        activate
        -- 确保窗口在当前 Space 显示
        set visible of front Finder window to false
        set visible of front Finder window to true
    end tell
    """
    
    // ... 执行脚本
}
```

**关于 Spaces 的注意事项：**

- macOS 默认行为：激活一个应用会**自动切换到该应用所在的 Space**
- 如果 Finder 窗口在其他 Space，系统会切换过去
- 可以通过系统设置 > 桌面与程序坞 > 取消勾选"切换应用程序时，会切换到打开该应用程序的桌面空间"来改变此行为
- **无法强制** 让 Finder 窗口在当前 Space 新建（除非使用私有 API）

### 5.4 让 Finder 窗口在最前面的完整逻辑

```swift
import AppKit

class FinderWindowManager {
    
    /// 完整的打开/导航流程，确保窗口在最前面
    func openAndFocus(_ path: String) {
        // 1. 先执行 AppleScript 导航
        let script = """
        tell application "Finder"
            -- 确保运行
            if not running then launch
            delay 0.1
            
            activate
            
            if (count of Finder windows) > 0 then
                set target of front Finder window to (POSIX file "\(path)")
            else
                open (POSIX file "\(path)")
            end if
            
            -- 确保窗口在最前面
            set frontmost to true
        end tell
        """
        
        runAppleScript(script)
        
        // 2. 额外确保 Finder 被激活（处理 LSUIElement 应用的情况）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.forceActivateFinder()
        }
    }
    
    /// 强制激活 Finder（适用于 LSUIElement 调用者）
    private func forceActivateFinder() {
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Finder"
        )
        apps.first?.activate(options: .activateAllWindows)
    }
    
    private func runAppleScript(_ script: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}
```

---

## 6. LSUIElement 后台应用的特殊处理

### 6.1 问题描述

当主应用设置为 `LSUIElement`（无 Dock 图标）时，存在以下限制：

- 应用不会出现在 Cmd+Tab 切换列表中
- 应用没有菜单栏
- **`activateIgnoringOtherApps` 在 macOS 14+ 已废弃且无效**
- 激活其他应用的能力可能受限

### 6.2 解决方案

#### 方案A：临时切换 Activation Policy

```swift
import AppKit

class UIElementAppHelper {
    
    /// 激活外部应用（从 LSUIElement 应用调用）
    static func activateExternalApp(bundleIdentifier: String) {
        // 方法1：直接激活目标应用（macOS 14+ 推荐）
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        
        if let app = apps.first {
            // 使用 activateAllWindows
            app.activate(options: .activateAllWindows)
        }
        
        // 方法2：如果需要确保切换，先激活自己再激活目标
        // （某些场景下需要）
        // NSRunningApplication.current.activate(options: .activateAllWindows)
        // app.activate(options: .activateAllWindows)
    }
    
    /// 临时切换为普通应用以获取完整激活能力
    static func temporarilyBecomeRegularApp(completion: @escaping () -> Void) {
        // 保存当前策略
        let originalPolicy = NSApp.activationPolicy
        
        // 切换为普通应用
        NSApp.setActivationPolicy(.regular)
        
        // 激活自己
        NSRunningApplication.current.activate(options: .activateAllWindows)
        
        // 执行操作
        completion()
        
        // 恢复 LSUIElement 状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(originalPolicy)
        }
    }
}
```

#### 方案B：使用 NSApp.activate

```swift
/// LSUIElement 应用中正确激活 Finder 的方式
func activateFinderFromUIElementApp() {
    // 步骤1：先激活当前应用（LSUIElement）
    NSApp.activate(ignoringOtherApps: true)
    
    // 步骤2：执行 AppleScript
    let script = """
    tell application "Finder" to activate
    """
    runAppleScript(script)
    
    // 步骤3：通过 NSRunningApplication 确保激活
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let finderApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Finder"
        )
        finderApps.first?.activate(options: .activateAllWindows)
    }
}
```

#### 方案C：使用 open 命令

```swift
/// 通过 open 命令激活 Finder（最简单可靠）
func openFinderWithOpenCommand(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Finder", path]
    try? process.run()
}
```

### 6.3 LSUIElement 应用的最佳实践

```swift
import AppKit

/// LSUIElement 应用的 Finder 激活管理器
final class FinderActivatorForUIElementApp {
    
    /// 推荐的主方法
    static func activateFinder(path: String) {
        // 1. 先尝试 AppleScript 方案（最完整）
        if runAppleScriptForFinder(path: path) {
            return
        }
        
        // 2. Fallback：使用 NSWorkspace
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    /// AppleScript 方案
    private static func runAppleScriptForFinder(path: String) -> Bool {
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "Finder"
            activate
            try
                if (count of Finder windows) > 0 then
                    set target of front Finder window to (POSIX file "\(escapedPath)")
                else
                    open (POSIX file "\(escapedPath)")
                end if
            on error
                open (POSIX file "\(escapedPath)")
            end try
        end tell
        """
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
```

### 6.4 LSUIElement 限制的注意事项

1. **macOS 版本差异**：
   - macOS 13 及以下：`activateIgnoringOtherApps` 有效
   - macOS 14+：`activateIgnoringOtherApps` 已废弃，需要使用新的激活协作机制

2. **权限需求**：
   - 首次运行 AppleScript 时，系统会弹出权限请求
   - 需要在「系统设置 > 隐私与安全 > 自动化」中授予权限
   - 可以通过 PPPC 配置文件在企业环境中预授权

3. **焦点传递**：
   - 从 LSUIElement 应用传递焦点到 Finder 通常需要 0.1-0.3 秒的延迟
   - 使用 `DispatchQueue.main.asyncAfter` 来确保激活顺序

---

## 7. 推荐方案与实现代码

### 7.1 推荐架构

```
主方案：AppleScript (osascript)
Fallback 1：NSWorkspace.open()  
Fallback 2：open -a Finder <path> 命令
```

### 7.2 完整推荐实现

```swift
// ============================================
// FinderWindowNavigator.swift
// 快速目录跳转工具 - Finder 窗口控制器
// ============================================

import Foundation
import AppKit
import os.log

/// Finder 窗口导航器
/// 核心职责：将 Finder 窗口导航到指定目录，优先复用已有窗口
public final class FinderWindowNavigator {
    
    // MARK: - Types
    
    public enum NavigationError: Error, LocalizedError {
        case invalidPath
        case pathNotFound(String)
        case notADirectory(String)
        case appleScriptFailed(String)
        case privacyDenied(String)
        case allMethodsFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidPath: return "无效的路径"
            case .pathNotFound(let p): return "路径不存在: \(p)"
            case .notADirectory(let p): return "路径不是目录: \(p)"
            case .appleScriptFailed(let d): return "AppleScript 执行失败: \(d)"
            case .privacyDenied(let d): return "缺少自动化权限: \(d)"
            case .allMethodsFailed: return "所有打开方式均失败"
            }
        }
    }
    
    public struct Options {
        /// 是否强制新建窗口（而非复用已有窗口）
        public var forceNewWindow: Bool = false
        /// 激活 Finder 时使用的延迟（秒）
        public var activationDelay: TimeInterval = 0.1
        /// AppleScript 执行超时（秒）
        public var scriptTimeout: TimeInterval = 5.0
        
        public init(
            forceNewWindow: Bool = false,
            activationDelay: TimeInterval = 0.1,
            scriptTimeout: TimeInterval = 5.0
        ) {
            self.forceNewWindow = forceNewWindow
            self.activationDelay = activationDelay
            self.scriptTimeout = scriptTimeout
        }
    }
    
    // MARK: - Singleton
    
    public static let shared = FinderWindowNavigator()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.yourapp.finder", category: "navigation")
    
    // MARK: - Init
    
    private init() {}
    
    // MARK: - Public API
    
    /// 导航到指定目录
    /// - Parameters:
    ///   - path: 目标目录路径（支持 ~ 展开和相对路径）
    ///   - options: 导航选项
    /// - Returns: 导航是否成功
    @discardableResult
    public func navigate(
        to path: String,
        options: Options = Options()
    ) -> Result<Void, NavigationError> {
        
        // 1. 解析并验证路径
        let resolvedPath: String
        switch resolvePath(path) {
        case .success(let p): resolvedPath = p
        case .failure(let e): return .failure(e)
        }
        
        logger.info("导航到: \(resolvedPath)")
        
        // 2. 主方案：AppleScript
        if case .success = navigateWithAppleScript(path: resolvedPath, options: options) {
            logger.info("AppleScript 导航成功")
            
            // 确保 Finder 被激活
            ensureFinderActivated(options: options)
            return .success(())
        }
        
        logger.warning("AppleScript 失败，尝试 fallback")
        
        // 3. Fallback：NSWorkspace
        if case .success = navigateWithWorkspace(path: resolvedPath) {
            logger.info("NSWorkspace 导航成功")
            return .success(())
        }
        
        // 4. 最终 Fallback：open 命令
        if case .success = navigateWithOpenCommand(path: resolvedPath) {
            logger.info("open 命令导航成功")
            return .success(())
        }
        
        logger.error("所有导航方式均失败")
        return .failure(.allMethodsFailed)
    }
    
    /// 快速导航（使用默认选项）
    @discardableResult
    public func navigate(to path: String) -> Result<Void, NavigationError> {
        navigate(to: path, options: Options())
    }
    
    /// 获取当前 Finder 窗口路径
    public func getCurrentPath() -> String? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            end if
        end tell
        return ""
        """
        
        guard let output = runScriptWithOutput(script),
              !output.isEmpty else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 检查是否有打开的 Finder 窗口
    public func hasOpenWindows() -> Bool {
        let script = """
        tell application "Finder"
            return (count of Finder windows) > 0
        end tell
        """
        guard let output = runScriptWithOutput(script) else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
    
    // MARK: - Private Methods
    
    /// 路径解析
    private func resolvePath(_ path: String) -> Result<String, NavigationError> {
        var resolved = path
        
        // 展开 ~
        if resolved.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            resolved = home + resolved.dropFirst()
        }
        
        // 标准化路径
        resolved = (resolved as NSString).standardizingPath
        
        // 验证存在性
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir) else {
            return .failure(.pathNotFound(resolved))
        }
        
        guard isDir.boolValue else {
            return .failure(.notADirectory(resolved))
        }
        
        return .success(resolved)
    }
    
    /// 主方案：AppleScript
    private func navigateWithAppleScript(
        path: String,
        options: Options
    ) -> Result<Void, NavigationError> {
        
        let escapedPath = escapeForAppleScript(path)
        
        let script: String
        if options.forceNewWindow {
            script = """
            tell application "Finder"
                activate
                make new Finder window
                set target of front Finder window to (POSIX file "\(escapedPath)")
            end tell
            """
        } else {
            script = """
            tell application "Finder"
                activate
                try
                    if (count of Finder windows) > 0 then
                        set target of front Finder window to (POSIX file "\(escapedPath)")
                    else
                        open (POSIX file "\(escapedPath)")
                    end if
                on error
                    open (POSIX file "\(escapedPath)")
                end try
            end tell
            """
        }
        
        return runScript(script)
    }
    
    /// Fallback 1：NSWorkspace
    private func navigateWithWorkspace(path: String) -> Result<Void, NavigationError> {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        return .success(())
    }
    
    /// Fallback 2：open 命令
    private func navigateWithOpenCommand(path: String) -> Result<Void, NavigationError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Finder", path]
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0 ? .success(()) : .failure(.allMethodsFailed)
        } catch {
            return .failure(.allMethodsFailed)
        }
    }
    
    /// 确保 Finder 被激活（用于 LSUIElement 应用）
    private func ensureFinderActivated(options: Options) {
        DispatchQueue.main.asyncAfter(deadline: .now() + options.activationDelay) {
            let finders = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.Finder"
            )
            finders.first?.activate(options: .activateAllWindows)
        }
    }
    
    // MARK: - Script Execution
    
    /// 执行 AppleScript（无输出）
    private func runScript(_ script: String) -> Result<Void, NavigationError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "未知错误"
                
                if errorMsg.contains("-1743") || errorMsg.contains("Not authorized") {
                    return .failure(.privacyDenied(errorMsg))
                }
                return .failure(.appleScriptFailed(errorMsg))
            }
            
            return .success(())
        } catch {
            return .failure(.appleScriptFailed(error.localizedDescription))
        }
    }
    
    /// 执行 AppleScript并返回输出
    private func runScriptWithOutput(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// 转义 AppleScript 字符串
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

### 7.3 使用示例

```swift
// 基本使用
FinderWindowNavigator.shared.navigate(to: "~/Documents")
FinderWindowNavigator.shared.navigate(to: "/Users/xxx/Desktop/Projects")

// 强制新建窗口
var options = FinderWindowNavigator.Options()
options.forceNewWindow = true
FinderWindowNavigator.shared.navigate(to: "~/Downloads", options: options)

// 错误处理
let result = FinderWindowNavigator.shared.navigate(to: "~/SomeFolder")
switch result {
case .success:
    print("导航成功")
case .failure(let error):
    print("导航失败: \(error.localizedDescription)")
}

// 获取当前路径
if let currentPath = FinderWindowNavigator.shared.getCurrentPath() {
    print("当前 Finder 窗口: \(currentPath)")
}
```

---

## 8. 性能对比与建议

### 8.1 性能测试数据（预估）

| 方案 | 首次执行 | 后续执行 | 窗口复用 | 额外权限 |
|------|---------|---------|---------|---------|
| NSWorkspace.open() | ~50ms | ~30ms | ❌ | 无 |
| NSWorkspace.selectFile() | ~60ms | ~40ms | ❌ | 无 |
| Scripting Bridge | ~100ms | ~50ms | ✅ | 自动化权限 |
| AppleScript (osascript) | ~200ms | ~150ms | ✅ | 自动化权限 |
| open 命令 | ~80ms | ~50ms | ❌ | 无 |

> 注：AppleScript 较慢是因为需要启动 osascript 进程并解析脚本。Scripting Bridge 稍快但差距不大。

### 8.2 选择建议

| 场景 | 推荐方案 |
|------|---------|
| 快速目录跳转工具（你的场景） | **AppleScript** ✅ |
| 简单打开文件夹（不关心窗口） | NSWorkspace.open() |
| 高性能批量操作 | Scripting Bridge |
| 需要与 Finder 深度交互（获取/设置大量属性） | Scripting Bridge |
| LSUIElement 后台工具 | AppleScript + NSRunningApplication |
| 没有自动化权限的环境 | NSWorkspace（fallback） |

### 8.3 最终建议

**推荐采用 AppleScript + Fallback 架构：**

1. **主方案**：AppleScript（osascript）— 功能最完整，能复用窗口，实现简单
2. **Fallback**：NSWorkspace.open() — 当 AppleScript 因权限问题失败时使用

**理由**：
- AppleScript 的 "set target of front window" 完美满足"复用已有窗口"的核心需求
- 代码简洁，不需要复杂的项目配置
- 性能差异（150ms vs 30ms）对于用户操作来说可接受
- Fallback 机制确保在各种环境下都能工作

---

## 9. 权限处理

### 9.1 首次运行权限请求

当第一次使用 AppleScript 控制 Finder 时，macOS 会弹出对话框：

> "XXX" 想要控制 "Finder"。

需要在「系统设置 > 隐私与安全 > 自动化」中授予权限。

### 9.2 检测权限状态

```swift
/// 检查是否有 Finder 自动化权限
func checkFinderPermission() -> Bool {
    let script = """
    tell application "Finder" to return name
    """
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    
    let errorPipe = Pipe()
    task.standardError = errorPipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
            return !errorMsg.contains("-1743")
        }
        return true
    } catch {
        return false
    }
}
```

### 9.3 引导用户授权

```swift
func promptForAutomationPermission() {
    let alert = NSAlert()
    alert.messageText = "需要自动化权限"
    alert.informativeText = "请前往「系统设置 > 隐私与安全 > 自动化」，授予本应用控制 Finder 的权限。"
    alert.alertStyle = .informational
    alert.addButton(withTitle: "打开设置")
    alert.addButton(withTitle: "取消")
    
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        )
    }
}
```

---

## 10. 总结

| 维度 | 评估 |
|------|------|
| **最推荐方案** | AppleScript (osascript) |
| **核心优势** | 可复用窗口、实现简单、功能完整 |
| **主要限制** | 需要自动化权限、执行略慢 (~150ms) |
| **Fallback** | NSWorkspace.open() |
| **LSUIElement 注意** | 需要额外激活步骤 |
| **权限处理** | 首次使用需用户授权 |
