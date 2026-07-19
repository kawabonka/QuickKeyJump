import Foundation

/// 开机自启管理器
///
/// 通过写入 ~/Library/LaunchAgents/com.quickfolderjump.app.plist
/// 实现登录时自动启动。兼容 macOS 11+。
final class LaunchManager {

    private static let label = "com.quickfolderjump.app"
    private static let userDefaultsKey = "LaunchAtLogin"

    /// LaunchAgent plist 路径
    private static var plistURL: URL {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        return agentsDir.appendingPathComponent("\(label).plist")
    }

    /// 当前是否已启用开机自启
    static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(getuid())/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 保存用户偏好
    static var userPreference: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    /// 启用开机自启
    static func enable() {
        let appPath = Bundle.main.bundlePath
        let executablePath = "\(appPath)/Contents/MacOS/QuickFolderJump"

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Background"
        ]

        let agentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: agentsDir,
                                                  withIntermediateDirectories: true)

        unload()

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: plistURL)
        } catch {
            print("[LaunchManager] 写入 plist 失败: \(error)")
            return
        }

        load()
        userPreference = true
        print("[LaunchManager] 开机自启已启用")
    }

    /// 禁用开机自启
    static func disable() {
        unload()
        try? FileManager.default.removeItem(at: plistURL)
        userPreference = false
        print("[LaunchManager] 开机自启已禁用")
    }

    /// 根据保存的偏好同步状态（启动时调用）
    static func syncWithPreference() {
        if userPreference {
            enable()
        } else {
            unload()
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    // MARK: - Private

    private static func load() {
        runLaunchctl("bootstrap", "gui/\(getuid())/\(label)")
    }

    private static func unload() {
        runLaunchctl("bootout", "gui/\(getuid())/\(label)")
    }

    @discardableResult
    private static func runLaunchctl(_ args: String...) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }

    private static func getuid() -> uid_t {
        return Foundation.getuid()
    }
}
