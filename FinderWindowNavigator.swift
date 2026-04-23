// ============================================
// FinderWindowNavigator.swift
// macOS 快速目录跳转工具 - Finder 窗口控制器
// 
// 功能：
// - 导航到指定目录，优先复用已有 Finder 窗口
// - 没有窗口时自动新建
// - 自动激活 Finder 并获取焦点
// - 支持 LSUIElement 后台应用
//
// 使用方法：
//   FinderWindowNavigator.shared.navigate(to: "~/Documents")
//   FinderWindowNavigator.shared.navigate(to: "/Users/xxx/Desktop")
//
// 需要权限：
// - 自动化权限（首次使用时会请求）
//
// 系统要求：macOS 11.0+
// ============================================

import Foundation
import AppKit
import os.log

// MARK: - Finder 窗口导航器

/// Finder 窗口导航器
/// 核心职责：将 Finder 窗口导航到指定目录，优先复用已有窗口
public final class FinderWindowNavigator {
    
    // MARK: Types
    
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
        public var forceNewWindow: Bool
        /// 激活 Finder 时的延迟（秒），用于 LSUIElement 应用
        public var activationDelay: TimeInterval
        /// 是否记录详细日志
        public var enableLogging: Bool
        
        public init(
            forceNewWindow: Bool = false,
            activationDelay: TimeInterval = 0.15,
            enableLogging: Bool = false
        ) {
            self.forceNewWindow = forceNewWindow
            self.activationDelay = activationDelay
            self.enableLogging = enableLogging
        }
    }
    
    // MARK: Singleton
    
    public static let shared = FinderWindowNavigator()
    
    // MARK: Properties
    
    private let logger = Logger(subsystem: "com.finder.navigator", category: "navigation")
    
    // MARK: Init
    
    private init() {}
    
    // MARK: - Public API
    
    /// 导航到指定目录（核心方法）
    /// - Parameters:
    ///   - path: 目标目录路径（支持 ~ 展开和相对路径）
    ///   - options: 导航选项
    /// - Returns: 导航结果
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
        
        log("导航到: \(resolvedPath)", options: options)
        
        // 2. 主方案：AppleScript（最推荐，可复用窗口）
        if case .success = navigateWithAppleScript(path: resolvedPath, options: options) {
            log("AppleScript 导航成功", options: options)
            ensureFinderActivated(options: options)
            return .success(())
        }
        
        log("AppleScript 失败，尝试 fallback", level: .warning, options: options)
        
        // 3. Fallback 1：NSWorkspace（总是创建新窗口）
        if case .success = navigateWithWorkspace(path: resolvedPath) {
            log("NSWorkspace 导航成功", options: options)
            return .success(())
        }
        
        // 4. Fallback 2：open 命令
        if case .success = navigateWithOpenCommand(path: resolvedPath) {
            log("open 命令导航成功", options: options)
            return .success(())
        }
        
        log("所有导航方式均失败", level: .error, options: options)
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
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    
    /// 获取 Finder 窗口数量
    public func windowCount() -> Int {
        let script = """
        tell application "Finder"
            return count of Finder windows
        end tell
        """
        guard let output = runScriptWithOutput(script),
              let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return count
    }
    
    /// 检查是否有 Finder 自动化权限
    public func hasAutomationPermission() -> Bool {
        let script = "tell application \"Finder\" to return name"
        let result = runScriptWithOutput(script)
        // 如果返回 "Finder" 说明有权限
        return result?.contains("Finder") ?? false
    }
    
    // MARK: - Private Methods
    
    /// 路径解析和验证
    private func resolvePath(_ path: String) -> Result<String, NavigationError> {
        var resolved = (path as NSString).expandingTildeInPath
        resolved = (resolved as NSString).standardizingPath
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir) else {
            return .failure(.pathNotFound(resolved))
        }
        
        guard isDir.boolValue else {
            return .failure(.notADirectory(resolved))
        }
        
        return .success(resolved)
    }
    
    /// 主方案：AppleScript 导航
    /// 核心逻辑：有窗口则 set target，无窗口则 open
    private func navigateWithAppleScript(
        path: String,
        options: Options
    ) -> Result<Void, NavigationError> {
        
        let escapedPath = escapeForAppleScript(path)
        
        let script: String
        if options.forceNewWindow {
            // 强制新建窗口
            script = """
            tell application "Finder"
                activate
                make new Finder window
                set target of front Finder window to (POSIX file "\(escapedPath)")
            end tell
            """
        } else {
            // 优先复用已有窗口
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
    
    /// Fallback 1：NSWorkspace.open()
    /// 注意：这会创建新窗口，无法复用已有窗口
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
    
    /// 确保 Finder 被激活（用于 LSUIElement 应用和焦点管理）
    private func ensureFinderActivated(options: Options) {
        // 使用延迟确保 AppleScript 执行完成后再激活
        DispatchQueue.main.asyncAfter(deadline: .now() + options.activationDelay) {
            let finders = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.Finder"
            )
            
            if let finder = finders.first {
                // activateAllWindows 将所有窗口带到前面
                finder.activate(options: .activateAllWindows)
            }
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
                
                // -1743 = 权限被拒绝
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
    
    /// 执行 AppleScript 并返回输出
    private func runScriptWithOutput(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    /// 转义 AppleScript 字符串中的特殊字符
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    /// 日志输出
    private func log(
        _ message: String,
        level: OSLogType = .info,
        options: Options
    ) {
        guard options.enableLogging else { return }
        logger.log(level: level, "\(message)")
    }
}

// MARK: - 便捷扩展

extension FinderWindowNavigator {
    
    /// 导航到 URL
    public func navigate(to url: URL, options: Options = Options()) -> Result<Void, NavigationError> {
        navigate(to: url.path, options: options)
    }
    
    /// 导航到用户主目录下的文件夹
    public func navigateToHome(subPath: String = "", options: Options = Options()) -> Result<Void, NavigationError> {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = subPath.isEmpty ? home : (home as NSString).appendingPathComponent(subPath)
        return navigate(to: path, options: options)
    }
}

// MARK: - 使用示例

/*
 
 // ===== 基本使用 =====
 
 // 导航到 Documents
 FinderWindowNavigator.shared.navigate(to: "~/Documents")
 
 // 导航到绝对路径
 FinderWindowNavigator.shared.navigate(to: "/Users/xxx/Desktop/Projects")
 
 // 导航到 URL
 let url = URL(fileURLWithPath: "/Users/xxx/Downloads")
 FinderWindowNavigator.shared.navigate(to: url)
 
 
 // ===== 带选项的使用 =====
 
 // 强制新建窗口
 var options = FinderWindowNavigator.Options()
 options.forceNewWindow = true
 FinderWindowNavigator.shared.navigate(to: "~/Downloads", options: options)
 
 // LSUIElement 应用使用（增加激活延迟）
 var uiOptions = FinderWindowNavigator.Options()
 uiOptions.activationDelay = 0.3
 FinderWindowNavigator.shared.navigate(to: "~/Desktop", options: uiOptions)
 
 
 // ===== 错误处理 =====
 
 let result = FinderWindowNavigator.shared.navigate(to: "~/SomeFolder")
 switch result {
 case .success:
     print("导航成功")
 case .failure(let error):
     print("导航失败: \(error.localizedDescription)")
     if case .privacyDenied = error {
         // 引导用户开启权限
     }
 }
 
 
 // ===== 查询状态 =====
 
 // 获取当前窗口路径
 if let path = FinderWindowNavigator.shared.getCurrentPath() {
     print("当前: \(path)")
 }
 
 // 检查是否有打开窗口
 let hasWindows = FinderWindowNavigator.shared.hasOpenWindows()
 let count = FinderWindowNavigator.shared.windowCount()
 
 // 检查权限
 let hasPermission = FinderWindowNavigator.shared.hasAutomationPermission()
 
 */
