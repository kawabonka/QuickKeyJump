import Cocoa
import Carbon
import ApplicationServices
import SwiftUI

// MARK: - 全局快捷键标识符
private let kQuickJumpHotKeyIdentifier: FourCharCode = (81 << 24) | (74 << 16) | (77 << 8) | 80  // "QJMP"

/// AppDelegate - QuickFolderJump 应用委托
/// 协调所有模块：全局快捷键、面板显示、权限检查、菜单栏
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - 模块实例
    
    /// 最近目录管理器
    private let folderManager = RecentFolderManager()
    
    /// 快速跳转面板（单例）
    private let quickJumpPanel = QuickJumpPanel.shared
    
    /// 菜单栏状态图标
    private var statusItem: NSStatusItem?

    /// 热键事件引用（用于注销）
    private var hotKeyEventRef: EventHotKeyRef?

    /// 是否已显示首次权限提示
    private var hasShownPermissionAlert = false

    /// 弹出 panel 前记录的前台应用（用于判断导航目标）
    private var previousFrontmostApp: NSRunningApplication?
    
    // MARK: - 应用生命周期
    
    /// 应用完成启动后的初始化
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为 accessory 模式（配合 LSUIElement，无 Dock 图标）
        NSApp.setActivationPolicy(.accessory)
        
        // 初始化菜单栏图标
        setupStatusBarItem()
        
        // 注册全局快捷键 Option+J
        registerGlobalHotKey()
        
        // 初始化最近目录数据
        folderManager.loadRecentFolders(maxResults: 5)
        
        // 同步开机自启偏好
        LaunchManager.syncWithPreference()

        // 首次运行检查权限
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }
    
    /// 应用即将终止时的清理
    func applicationWillTerminate(_ notification: Notification) {
        // 注销全局快捷键
        unregisterGlobalHotKey()
    }
    
    // MARK: - 菜单栏设置
    
    /// 创建菜单栏状态图标和菜单
    private func setupStatusBarItem() {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // 使用文件夹图标作为菜单栏图标
        if let folderImage = NSImage(systemSymbolName: "folder.fill.badge.arrow.down",
                                      accessibilityDescription: "QuickFolderJump") {
            folderImage.isTemplate = true
            button.image = folderImage
        } else {
            // 降级方案：使用文字
            button.title = "QFJ"
        }
        
        // 创建菜单
        let menu = NSMenu(title: "QuickFolderJump")
        
        // 打开 QuickJump
        let openItem = NSMenuItem(
            title: NSLocalizedString("打开 QuickJump (⌥⌘G)", comment: ""),
            action: #selector(showQuickJumpPanel),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 刷新最近目录
        let refreshItem = NSMenuItem(
            title: NSLocalizedString("刷新最近目录", comment: ""),
            action: #selector(refreshFolders),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        // 开机自启开关
        let autoStartItem = NSMenuItem(
            title: NSLocalizedString("开机自动启动", comment: ""),
            action: #selector(toggleAutoStart),
            keyEquivalent: ""
        )
        autoStartItem.target = self
        autoStartItem.state = LaunchManager.isEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 检查权限
        let permissionItem = NSMenuItem(
            title: NSLocalizedString("检查辅助功能权限", comment: ""),
            action: #selector(checkPermissionFromMenu),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出应用
        let quitItem = NSMenuItem(
            title: NSLocalizedString("退出", comment: ""),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: - 全局快捷键 (Carbon RegisterEventHotKey)

    /// 注册全局快捷键 Option+Cmd+G
    private func registerGlobalHotKey() {
        // 创建事件处理器
        var eventHandler: EventHandlerRef?
        
        // 定义我们关心的事件类型：热键按下
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        // 安装事件处理器
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                return appDelegate.handleHotKeyEvent(eventRef)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        guard installStatus == noErr else {
            print("[QuickFolderJump] 安装热键事件处理器失败: \(installStatus)")
            return
        }
        
        // 注册热键：Option + Cmd + G
        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_G),                          // 虚拟键码：G
            UInt32(optionKey | cmdKey),                   // 修饰键：Option + Cmd
            EventHotKeyID(signature: kQuickJumpHotKeyIdentifier, id: 1),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus == noErr {
            self.hotKeyEventRef = hotKeyRef
            print("[QuickFolderJump] 全局热键 Option+Cmd+G 注册成功")
        } else {
            print("[QuickFolderJump] 注册热键失败: \(hotKeyStatus)")
        }
    }
    
    /// 注销全局快捷键
    private func unregisterGlobalHotKey() {
        if let hotKeyRef = hotKeyEventRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyEventRef = nil
        }
    }
    
    /// 处理热键事件回调
    private func handleHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef = eventRef else { return noErr }
        
        // 提取热键ID验证
        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard result == noErr else { return result }
        
        // 验证签名匹配
        guard hotKeyID.signature == kQuickJumpHotKeyIdentifier else { return noErr }
        
        // 在主线程触发面板显示
        DispatchQueue.main.async { [weak self] in
            self?.toggleQuickJumpPanel()
        }
        
        return noErr
    }
    
    // MARK: - QuickJump 面板逻辑
    
    /// 切换面板显示/隐藏
    @objc private func toggleQuickJumpPanel() {
        if quickJumpPanel.isVisible {
            quickJumpPanel.close()
        } else {
            showQuickJumpPanel()
        }
    }
    
    /// 显示 QuickJump 面板
    @objc private func showQuickJumpPanel() {
        // 在激活面板之前记录当前前台应用（用于后续判断是 Finder 还是对话框导航）
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication

        // 如果面板已在显示，先关闭再重新打开（刷新数据）
        if quickJumpPanel.isVisible {
            quickJumpPanel.close()
        }

        // 加载最新的最近目录列表
        folderManager.loadRecentFolders(maxResults: 5)
        
        // 显示面板，传入回调
        quickJumpPanel.show(
            folderManager: folderManager,
            onSelect: { [weak self] recentFolder in
                // 用户选择了目录
                self?.handleFolderSelection(recentFolder)
            },
            onCancel: { [weak self] in
                // 用户取消，关闭面板
                self?.quickJumpPanel.close()
            }
        )
    }
    
    /// 处理目录选择
    private func handleFolderSelection(_ folder: RecentFolder) {
        quickJumpPanel.close()
        handleNavigation(to: folder)
    }

    /// 将文件夹选择分发到正确的导航器：Finder 用 AppleScript，对话框用 Cmd+Shift+G
    private func handleNavigation(to folder: RecentFolder) {
        let prevApp = previousFrontmostApp
        previousFrontmostApp = nil

        guard let app = prevApp else { return }

        // Step 1：激活前一个 app
        app.activate(options: .activateAllWindows)

        let isFinder = app.bundleIdentifier == "com.apple.finder"

        if isFinder {
            // Finder 场景：直接通过 AppleScript 设置 Finder 窗口 target
            FinderWindowNavigator.shared.navigateTo(folder.path)
            return
        }

        // 非 Finder 场景（保存/打开对话框等）：用 AX + Cmd+Shift+G 导航
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.raiseDialogWindow(in: app)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.navigateDialog(to: folder.path)
            }
        }
    }

    /// 通过 DialogNavigator 执行 Cmd+Shift+G 导航序列
    private func navigateDialog(to path: String) {
        guard DialogNavigator.checkPermission() else {
            DialogNavigator.requestPermission()
            showPermissionAlert(for: .appleEvents)
            return
        }
        let success = DialogNavigator.navigateTo(path: path)
        if !success {
            print("[QuickFolderJump] 导航失败: \(path)")
        }
    }

    /// 通过 AX API 找到保存/打开对话框窗口并将其 raise 到前台（获得键盘焦点）
    ///
    /// - Sheet 形式：raise 带有 sheet 的父窗口，sheet 会自动成为 key responder
    /// - 独立对话框：直接 raise 该窗口
    private func raiseDialogWindow(in app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }

        for window in windows {
            // Sheet 形式：父窗口带有 AXSheets 子元素
            var sheetsValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, "AXSheets" as CFString, &sheetsValue) == .success,
               let sheets = sheetsValue as? [AXUIElement], !sheets.isEmpty {
                // raise 父窗口，modal sheet 会自动成为 key window
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                print("[QuickFolderJump] 已聚焦 Sheet 对话框所在窗口")
                return
            }

            // 独立对话框：subrole = AXDialog
            var subroleValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
               (subroleValue as? String) == "AXDialog" {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                print("[QuickFolderJump] 已聚焦独立对话框窗口")
                return
            }

            // modal 窗口兜底
            var modalValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXModalAttribute as CFString, &modalValue) == .success,
               (modalValue as? Bool) == true {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                print("[QuickFolderJump] 已聚焦 modal 窗口")
                return
            }
        }

        print("[QuickFolderJump] 未找到对话框窗口，键盘事件将发送到当前焦点窗口")
    }
    
    /// 检查当前系统焦点窗口是否为文件打开/保存对话框
    ///
    /// 在调用前应先激活目标 app 并等待其获得焦点，
    /// 使用系统级 AX 元素查询，可以捕获 PowerBox 托管的对话框。
    private func isFocusedWindowAFileDialog() -> Bool {
        let sysElement = AXUIElementCreateSystemWide()

        // 获取当前焦点应用的 AX 元素
        var focusedAppObj: AnyObject?
        guard AXUIElementCopyAttributeValue(
            sysElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppObj
        ) == .success, let focusedApp = focusedAppObj else { return false }

        // 获取焦点应用的焦点窗口
        var focusedWindowObj: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowObj
        ) == .success, let focusedWindow = focusedWindowObj else { return false }

        return windowLooksLikeFileDialog(focusedWindow as! AXUIElement)
    }

    /// 判断一个 AX 窗口是否是文件对话框
    private func windowLooksLikeFileDialog(_ win: AXUIElement) -> Bool {
        // 1. Role = AXSheet（sheet 形式，如 NSSavePanel.beginSheetModal）
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleValue) == .success,
           (roleValue as? String) == "AXSheet" { return true }

        // 2. Subrole = AXDialog（独立 modal 窗口，如 NSSavePanel.runModal）
        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           (subroleValue as? String) == "AXDialog" { return true }

        // 3. kAXModal = true（模态窗口，兜底检测）
        var modalValue: AnyObject?
        if AXUIElementCopyAttributeValue(win, kAXModalAttribute as CFString, &modalValue) == .success,
           (modalValue as? Bool) == true { return true }

        // 4. 窗口本身是普通窗口但附有 Sheet（父窗口场景）
        var sheetsValue: AnyObject?
        if AXUIElementCopyAttributeValue(win, "AXSheets" as CFString, &sheetsValue) == .success,
           let sheets = sheetsValue as? [AXUIElement], !sheets.isEmpty { return true }

        return false
    }
    
    // MARK: - 菜单栏动作
    
    /// 刷新最近目录列表
    @objc private func refreshFolders() {
        folderManager.refresh()
        folderManager.loadRecentFolders(maxResults: 5)
    }
    
    /// 从菜单栏检查权限
    @objc private func checkPermissionFromMenu() {
        checkAccessibilityPermission(showAlert: true)
    }
    
    /// 切换开机自启
    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        if LaunchManager.isEnabled {
            LaunchManager.disable()
            sender.state = .off
        } else {
            LaunchManager.enable()
            sender.state = .on
        }
    }

    /// 退出应用
    @objc private func quitApplication() {
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - 权限检查
    
    /// 检查辅助功能权限（Accessibility）
    private func checkAccessibilityPermission(showAlert: Bool = false) {
        // 检查 Accessibility 权限状态
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showAlert]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            if !hasShownPermissionAlert || showAlert {
                hasShownPermissionAlert = true
                showPermissionAlert(for: .accessibility)
            }
        } else {
            if showAlert {
                showPermissionGrantedAlert()
            }
        }
    }
    
    /// 权限类型
    private enum PermissionType {
        case accessibility
        case appleEvents
    }
    
    /// 显示权限引导弹窗
    private func showPermissionAlert(for type: PermissionType) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要授权才能使用 QuickFolderJump"
        
        switch type {
        case .accessibility:
            alert.informativeText = """
            QuickFolderJump 需要「辅助功能」权限来检测前台窗口和对话框，
            以便在您选择目录时自动导航。
            
            请点击「打开设置」，在系统偏好设置中勾选 QuickFolderJump。
            """
        case .appleEvents:
            alert.informativeText = """
            QuickFolderJump 需要控制 Finder 的权限来自动导航到选定目录。
            
            请点击「打开设置」，在系统偏好设置中授予权限。
            """
        }
        
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开辅助功能设置面板
            let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(prefPaneURL)
        }
    }
    
    /// 显示权限已获取的提示
    private func showPermissionGrantedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "权限检查通过"
        alert.informativeText = "QuickFolderJump 已获得所需的全部权限，可以正常使用。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
