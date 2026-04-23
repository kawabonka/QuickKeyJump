import Foundation
import AppKit
import ApplicationServices

// MARK: - 错误定义

/// DialogNavigator 可能遇到的错误类型
enum DialogNavigationError: Error, LocalizedError {
    case accessibilityPermissionDenied     // 辅助功能权限被拒绝
    case invalidPath                       // 无效的路径
    case pathEmpty                         // 路径为空
    case homeDirectoryResolutionFailed     // 用户主目录解析失败
    case scriptExecutionFailed(String)     // AppleScript执行失败

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "需要辅助功能权限，请在 系统设置 > 隐私与安全 > 辅助功能 中添加本应用"
        case .invalidPath:
            return "无效的路径"
        case .pathEmpty:
            return "路径不能为空"
        case .homeDirectoryResolutionFailed:
            return "无法解析用户主目录"
        case .scriptExecutionFailed(let msg):
            return "System Events 执行失败: \(msg)"
        }
    }
}

// MARK: - 核心导航类

/// 对话框导航器
///
/// 当保存/打开对话框处于前台时，通过 System Events + AppleScript
/// 让对话框跳转到指定路径。
///
/// 工作原理：
/// 1. 将目标路径写入剪贴板
/// 2. 通过 System Events 发送 Cmd+Shift+G 打开"前往文件夹"面板
/// 3. 全选 + 粘贴路径（处理中文等 Unicode 字符）
/// 4. 发送 Return 确认导航
///
/// 需要辅助功能权限：系统设置 > 隐私与安全 > 辅助功能
final class DialogNavigator {

    // MARK: 私有常量

    private static let logPrefix = "[DialogNavigator]"
    private static let accessibilityOptionsKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    // MARK: - 公开接口

    /// 导航对话框到指定路径
    ///
    /// - Parameter path: 目标路径（支持~展开为完整路径）
    /// - Returns: 是否成功执行导航序列
    static func navigateTo(path: String) -> Bool {
        guard checkPermission() else {
            print("\(logPrefix) 辅助功能权限未授予，无法发送按键事件")
            return false
        }

        guard !path.isEmpty else {
            print("\(logPrefix) 路径为空")
            return false
        }

        let expandedPath = expandTilde(in: path)

        guard !expandedPath.isEmpty else {
            print("\(logPrefix) 路径展开后为空")
            return false
        }

        // 备份剪贴板内容，导航后恢复
        let pasteboard = NSPasteboard.general
        let savedClipboard = pasteboard.string(forType: .string)

        // 将路径写入剪贴板（可靠处理 Unicode/中文路径）
        pasteboard.clearContents()
        pasteboard.setString(expandedPath, forType: .string)

        // System Events 通过 Accessibility 框架路由，可正确到达 PowerBox 对话框进程
        // key code 5 = G 键; key code 36 = Return
        let scriptSource = """
        tell application "System Events"
            key code 5 using {command down, shift down}
            delay 0.4
            keystroke "a" using {command down}
            keystroke "v" using {command down}
            key code 36
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
            print("\(logPrefix) 无法创建 NSAppleScript 对象")
            restorePasteboard(pasteboard, content: savedClipboard)
            return false
        }

        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)

        // 延迟恢复剪贴板，等待粘贴操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            restorePasteboard(pasteboard, content: savedClipboard)
        }

        if let err = errorDict {
            print("\(logPrefix) System Events 执行失败: \(err)")
            return false
        }

        print("\(logPrefix) 已导航到路径: \(expandedPath)")
        return true
    }

    /// 检查是否有辅助功能权限
    static func checkPermission() -> Bool {
        let options: [String: Bool] = [accessibilityOptionsKey: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 请求辅助功能权限（弹出系统对话框）
    static func requestPermission() {
        let options: [String: Bool] = [accessibilityOptionsKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("\(logPrefix) 已请求辅助功能权限，等待用户授权...")
    }

    // MARK: - 私有方法

    /// 恢复剪贴板内容
    private static func restorePasteboard(_ pasteboard: NSPasteboard, content: String?) {
        pasteboard.clearContents()
        if let content = content {
            pasteboard.setString(content, forType: .string)
        }
    }

    /// 展开路径中的~为用户主目录
    private static func expandTilde(in path: String) -> String {
        guard path.hasPrefix("~") else { return path }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homeDirectory.isEmpty else {
            print("\(logPrefix) 无法解析用户主目录")
            return path
        }

        if path.count == 1 { return homeDirectory }
        if path.hasPrefix("~/") { return homeDirectory + path.dropFirst(1) }

        // ~username 格式（其他用户），无法自动展开
        return path
    }
}
