import Foundation
import ServiceManagement

/// 开机自启管理器
///
/// 使用 SMAppService.mainApp (macOS 13+) 注册/取消开机自启。
/// 参考 Tungsten Edge 的实现：用户偏好通过 UserDefaults 持久化，
/// 每次启动时调用 syncWithPreference() 同步实际注册状态。
final class LaunchManager {

    private static let userDefaultsKey = "com.quickfolderjump.launchAtLogin"

    /// 当前是否已注册为登录项（实时查询系统状态）
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 用户在菜单栏中设置的开机自启偏好（持久化存储）
    static var userPreference: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    /// 启用开机自启
    static func enable() {
        do {
            try SMAppService.mainApp.register()
            userPreference = true
            print("[LaunchManager] 开机自启已启用")
        } catch {
            print("[LaunchManager] 注册开机自启失败: \(error.localizedDescription)")
            userPreference = false
        }
    }

    /// 禁用开机自启
    static func disable() {
        do {
            try SMAppService.mainApp.unregister()
            userPreference = false
            print("[LaunchManager] 开机自启已禁用")
        } catch {
            print("[LaunchManager] 取消开机自启失败: \(error.localizedDescription)")
        }
    }

    /// 启动时根据持久化偏好同步登录项注册状态
    ///
    /// 在 applicationDidFinishLaunching 中调用，
    /// 确保登录项注册状态与用户上次保存的偏好一致。
    static func syncWithPreference() {
        let shouldBeEnabled = userPreference
        let currentlyEnabled = SMAppService.mainApp.status == .enabled

        if shouldBeEnabled && !currentlyEnabled {
            do {
                try SMAppService.mainApp.register()
                print("[LaunchManager] 同步: 已重新注册开机自启")
            } catch {
                print("[LaunchManager] 同步注册失败: \(error.localizedDescription)")
            }
        } else if !shouldBeEnabled && currentlyEnabled {
            do {
                try SMAppService.mainApp.unregister()
                print("[LaunchManager] 同步: 已取消开机自启")
            } catch {
                print("[LaunchManager] 同步取消失败: \(error.localizedDescription)")
            }
        } else {
            print("[LaunchManager] 同步: 状态一致 (enabled=\(currentlyEnabled))")
        }
    }
}
