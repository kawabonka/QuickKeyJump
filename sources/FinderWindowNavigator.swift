import Foundation
import AppKit

// MARK: - 错误定义

/// FinderWindowNavigator 可能遇到的错误类型
enum FinderNavigationError: Error, LocalizedError {
    case osascriptNotFound          // /usr/bin/osascript 不存在
    case scriptExecutionFailed(Int32, String) // 退出码和错误输出
    case permissionDenied           // 自动化权限被拒绝（-1743错误）
    case noFinderRunning            // Finder未运行
    case pathEscapeFailed           // 路径转义失败
    case unexpectedOutput           // 意外的脚本输出
    
    var errorDescription: String? {
        switch self {
        case .osascriptNotFound:
            return "/usr/bin/osascript 不存在"
        case .scriptExecutionFailed(let code, let message):
            return "AppleScript执行失败 (退出码 \(code)): \(message)"
        case .permissionDenied:
            return "自动化权限被拒绝。请前往 系统设置 > 隐私与安全 > 自动化，允许本应用控制Finder"
        case .noFinderRunning:
            return "Finder未运行"
        case .pathEscapeFailed:
            return "路径转义失败"
        case .unexpectedOutput:
            return "AppleScript返回意外输出"
        }
    }
}

// MARK: - AppleScript模板

/// Finder导航用的AppleScript脚本模板
private enum AppleScriptTemplates {

    /// 组合导航脚本：有窗口则复用 front Finder window，无则新建
    /// %@ 占位符替换为转义后的路径
    static let navigateCombined = """
        tell application "Finder"
            activate
            try
                if (count of Finder windows) > 0 then
                    set target of front Finder window to (POSIX file "%@")
                else
                    open (POSIX file "%@")
                end if
            on error
                open (POSIX file "%@")
            end try
        end tell
        """

    /// 测试脚本权限（简单的 tell 语句）
    static let testPermission = """
        tell application "Finder"
            return "ok"
        end tell
        """
}

// MARK: - 核心导航类

/// Finder窗口导航器
///
/// 通过AppleScript (osascript) 控制Finder窗口导航。
/// 如果Finder已有打开窗口，则在前置窗口中导航到目标路径；
/// 如果没有窗口，则打开新窗口。
///
/// 需要"自动化"权限：系统设置 > 隐私与安全 > 自动化 > 允许本应用控制Finder
final class FinderWindowNavigator {
    
    // MARK: 单例
    
    /// 共享实例
    static let shared = FinderWindowNavigator()
    
    // MARK: 私有常量
    
    /// osascript可执行文件路径
    private let osascriptPath = "/usr/bin/osascript"
    
    /// 日志分类标识
    private let logPrefix = "[FinderWindowNavigator]"
    
    /// AppleScript权限被拒绝的错误码
    private let permissionDeniedErrorCode: Int32 = -1743
    
    // MARK: 初始化
    
    private init() {
        // 私有初始化，强制使用单例
    }
    
    // MARK: - 公开接口
    
    /// 导航到指定目录
    ///
    /// 如果Finder已有窗口，则在前置窗口中打开目标目录；
    /// 如果Finder没有窗口，则打开一个新窗口。
    ///
    /// - Parameter path: 目标目录路径（支持~展开）
    func navigateTo(_ path: String) {
        guard !path.isEmpty else {
            print("\(logPrefix) 路径为空，取消导航")
            return
        }

        guard FileManager.default.fileExists(atPath: osascriptPath) else {
            print("\(logPrefix) \(osascriptPath) 不存在，尝试 NSWorkspace fallback")
            fallbackOpenWithWorkspace(path: path)
            return
        }

        let expandedPath = expandTilde(in: path)

        guard let escapedPath = escapeAppleScriptString(expandedPath) else {
            print("\(logPrefix) 路径转义失败: \(expandedPath)")
            return
        }

        // 单一组合脚本：activate 在前，有窗口则复用，无窗口则新建，出错则 fallback open
        let script = String(
            format: AppleScriptTemplates.navigateCombined,
            escapedPath, escapedPath, escapedPath
        )

        do {
            let (_, errorOutput, exitCode) = try executeAppleScript(script)
            if exitCode == 0 {
                print("\(logPrefix) 已导航到: \(expandedPath)")
                // 额外确保 Finder 被激活（LSUIElement 应用场景下）
                ensureFinderActivated()
            } else {
                print("\(logPrefix) AppleScript 失败 (\(exitCode)): \(errorOutput)，尝试 NSWorkspace fallback")
                fallbackOpenWithWorkspace(path: expandedPath)
            }
        } catch FinderNavigationError.permissionDenied {
            print("\(logPrefix) 自动化权限被拒绝，请前往 系统设置 > 隐私与安全 > 自动化 授权")
            fallbackOpenWithWorkspace(path: expandedPath)
        } catch {
            print("\(logPrefix) 导航失败: \(error.localizedDescription)")
            fallbackOpenWithWorkspace(path: expandedPath)
        }
    }

    /// 确保 Finder 被激活到前台（适用于 LSUIElement/accessory 应用）
    private func ensureFinderActivated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Finder")
                .first?.activate(options: .activateAllWindows)
        }
    }

    /// NSWorkspace fallback：直接打开路径（总是新窗口，不复用）
    private func fallbackOpenWithWorkspace(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    /// 检查是否有Finder自动化权限
    ///
    /// 通过执行一个简单的AppleScript来检测是否拥有控制Finder的权限。
    ///
    /// - Returns: 是否有权限
    func checkPermission() -> Bool {
        // 检查osascript是否存在
        guard FileManager.default.fileExists(atPath: osascriptPath) else {
            return false
        }
        
        do {
            let (_, _, exitCode) = try executeAppleScript(
                AppleScriptTemplates.testPermission
            )
            return exitCode == 0
        } catch FinderNavigationError.permissionDenied {
            return false
        } catch {
            print("\(logPrefix) 权限检查失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 私有方法 - AppleScript执行
    
    /// 执行AppleScript脚本
    ///
    /// 通过 /usr/bin/osascript 执行给定的AppleScript代码。
    ///
    /// - Parameter script: AppleScript脚本内容
    /// - Returns: (标准输出, 标准错误输出, 退出码) 元组
    private func executeAppleScript(_ script: String) throws -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        
        // 读取标准输出
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // 读取标准错误输出
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        // 检查是否是权限被拒绝错误
        if isPermissionDeniedError(output: errorOutput, exitCode: exitCode) {
            throw FinderNavigationError.permissionDenied
        }
        
        return (output, errorOutput, exitCode)
    }
    
    // MARK: - 私有方法 - 工具函数
    
    /// 检查错误是否是权限被拒绝
    ///
    /// 通过检查退出码和错误输出内容判断是否权限被拒绝。
    /// -1743 是 macOS AppleScript 权限被拒绝的标准错误码。
    ///
    /// - Parameters:
    ///   - output: 错误输出内容
    ///   - exitCode: 进程退出码
    /// - Returns: 是否是权限被拒绝错误
    private func isPermissionDeniedError(output: String, exitCode: Int32) -> Bool {
        // 检查错误码 -1743
        if exitCode == permissionDeniedErrorCode {
            return true
        }
        
        // 检查错误消息中是否包含权限相关关键词
        let lowercasedOutput = output.lowercased()
        let permissionKeywords = [
            "not allowed to send",
            "permission",
            "not authorized",
            "-1743",
            "osascript is not allowed",
            "assistive access"
        ]
        
        return permissionKeywords.contains { lowercasedOutput.contains($0) }
    }
    
    /// 转义AppleScript字符串中的特殊字符
    ///
    /// AppleScript中使用双引号包围字符串，需要将路径中的双引号转义为\"，
    /// 反斜杠转义为\\。
    ///
    /// - Parameter string: 原始字符串
    /// - Returns: 转义后的字符串，转义失败返回nil
    private func escapeAppleScriptString(_ string: String) -> String? {
        // 转义反斜杠（先处理）
        var escaped = string
        
        // 反斜杠 -> 双反斜杠
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        
        // 双引号 -> 反斜杠双引号
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        
        // 验证转义结果：不应含有未转义的双引号
        // 简单检查：转义后的字符串中，双引号应该只出现在反斜杠后面
        var isValid = true
        var previousWasBackslash = false
        for character in escaped {
            if character == "\\" {
                previousWasBackslash = true
            } else if character == "\"" {
                if !previousWasBackslash {
                    isValid = false
                    break
                }
                previousWasBackslash = false
            } else {
                previousWasBackslash = false
            }
        }
        
        guard isValid else {
            return nil
        }
        
        return escaped
    }
    
    /// 展开路径中的~为用户主目录
    ///
    /// - Parameter path: 可能包含~的路径
    /// - Returns: 展开后的完整路径
    private func expandTilde(in path: String) -> String {
        guard path.hasPrefix("~") else {
            return path
        }
        
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        
        guard !homeDirectory.isEmpty else {
            print("\(logPrefix) 无法解析用户主目录")
            return path
        }
        
        // 仅有 ~
        if path.count == 1 {
            return homeDirectory
        }
        
        // ~/xxx 格式
        if path.hasPrefix("~/") {
            return homeDirectory + path.dropFirst(1)
        }
        
        // ~username 格式（其他用户），无法自动展开
        return path
    }
}
